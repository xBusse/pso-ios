// Reads PsoV3.dol out of a GameCube disc image (ISO, CISO, GCZ or RVZ), entirely in the browser.
//
// The disc image is read in small slices with Blob.slice, so it never has to fit in memory and never
// leaves the device. Formats follow Dolphin's readers (Source/Core/DiscIO: CISOBlob, CompressedBlob,
// WIABlob). RVZ needs fzstd.js (loaded before this file) for Zstandard-compressed images.
//
// API: PSOExtract.extractDol(blob, onProgress) -> Promise<{dol: Uint8Array, sha1: string, format: string}>
//      PSOExtract.EXPECTED_SHA1, PSOExtract.GAME_ID
(function (global) {
  "use strict";

  const GAME_ID = "GPOE8P";
  const DOL_NAME = "psov3.dol";
  const EXPECTED_SHA1 = "0d85744b51d7379efb025a943d0cd5aaae2191a3";

  class ExtractError extends Error {}

  async function readBytes(blob, offset, length) {
    if (offset < 0 || offset + length > blob.size)
      throw new ExtractError("The file ends early. It may be incomplete or damaged.");
    return new Uint8Array(await blob.slice(offset, offset + length).arrayBuffer());
  }

  const be32 = (b, o) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
  const be64 = (b, o) => be32(b, o) * 4294967296 + be32(b, o + 4);
  const le32 = (b, o) => (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
  const le64 = (b, o) => le32(b, o + 4) * 4294967296 + le32(b, o);
  const ascii = (b, o, n) => String.fromCharCode(...b.subarray(o, o + n));

  async function inflate(data) {
    // zlib stream (with header), as Dolphin's GCZ writer produces.
    const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate"));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  function unzstd(data) {
    if (!global.fzstd)
      throw new ExtractError("The Zstandard decoder didn't load. Reload the page and try again.");
    return global.fzstd.decompress(data);
  }

  // Each reader exposes size and read(offset, length) over the plain disc.

  function isoReader(blob) {
    return { format: "ISO", size: blob.size, read: (o, n) => readBytes(blob, o, n) };
  }

  async function cisoReader(blob) {
    const HEADER = 0x8000;
    const head = await readBytes(blob, 0, HEADER);
    const blockSize = le32(head, 4);
    if (!blockSize) throw new ExtractError("This CISO file's header is damaged.");
    const map = head.subarray(8);
    const slot = new Int32Array(map.length).fill(-1);
    let used = 0;
    for (let i = 0; i < map.length; ++i) if (map[i] === 1) slot[i] = used++;
    return {
      format: "CISO",
      size: map.length * blockSize,
      async read(offset, length) {
        const out = new Uint8Array(length);
        let done = 0;
        while (done < length) {
          const block = Math.floor((offset + done) / blockSize);
          const inBlock = (offset + done) % blockSize;
          const n = Math.min(blockSize - inBlock, length - done);
          if (block < slot.length && slot[block] >= 0)
            out.set(await readBytes(blob, HEADER + slot[block] * blockSize + inBlock, n), done);
          done += n;
        }
        return out;
      },
    };
  }

  async function gczReader(blob) {
    const head = await readBytes(blob, 0, 32);
    const compressedSize = le64(head, 8);
    const dataSize = le64(head, 16);
    const blockSize = le32(head, 24);
    const blocks = le32(head, 28);
    const table = await readBytes(blob, 32, blocks * 8);
    const dataStart = 32 + blocks * 12; // after the block pointers and the per-block hashes
    // Bit 63 of a block pointer marks a block stored uncompressed.
    const pointer = (i) => {
      const hi = le32(table, i * 8 + 4);
      return { raw: (hi & 0x80000000) !== 0, offset: (hi & 0x7fffffff) * 4294967296 + le32(table, i * 8) };
    };
    const cache = new Map();
    async function block(i) {
      if (cache.has(i)) return cache.get(i);
      const p = pointer(i);
      const end = i + 1 < blocks ? pointer(i + 1).offset : compressedSize;
      const stored = p.raw ? blockSize : end - p.offset;
      const bytes = await readBytes(blob, dataStart + p.offset, stored);
      const data = p.raw ? bytes : await inflate(bytes);
      if (cache.size > 8) cache.delete(cache.keys().next().value);
      cache.set(i, data);
      return data;
    }
    return {
      format: "GCZ",
      size: dataSize,
      async read(offset, length) {
        const out = new Uint8Array(length);
        let done = 0;
        while (done < length) {
          const i = Math.floor((offset + done) / blockSize);
          const inBlock = (offset + done) % blockSize;
          const n = Math.min(blockSize - inBlock, length - done);
          const data = await block(i);
          if (data.length < inBlock + n) throw new ExtractError("A block in this GCZ file is damaged.");
          out.set(data.subarray(inBlock, inBlock + n), done);
          done += n;
        }
        return out;
      },
    };
  }

  // RVZ (and WIA without compression). GameCube discs have no partitions, so every byte after the first
  // 0x80 (kept in header 2) lives in "raw data" entries, split into chunk-sized groups.
  async function rvzReader(blob, isRvz) {
    const h1 = await readBytes(blob, 0, 0x48);
    const h2Size = be32(h1, 12);
    const isoSize = be64(h1, 0x24);
    const h2 = await readBytes(blob, 0x48, h2Size);
    const compression = be32(h2, 4); // 0 none, 1 purge, 2 bzip2, 3 lzma, 4 lzma2, 5 zstd
    const chunkSize = be32(h2, 12);
    const discHeader = h2.subarray(16, 16 + 0x80);
    const rawCount = be32(h2, 0xb4);
    const rawOffset = be64(h2, 0xb8);
    const rawSize = be32(h2, 0xc0);
    const groupCount = be32(h2, 0xc4);
    const groupOffset = be64(h2, 0xc8);
    const groupSize = be32(h2, 0xd0);

    if (compression !== 0 && compression !== 5) {
      const names = { 1: "Purge", 2: "bzip2", 3: "LZMA", 4: "LZMA2" };
      throw new ExtractError(
        `This ${isRvz ? "RVZ" : "WIA"} file uses ${names[compression] || "an unknown"} compression, which this ` +
          "page can't read. In Dolphin, convert it to RVZ with Zstandard (the default), or to ISO.");
    }
    if (!isRvz && compression !== 0)
      throw new ExtractError("WIA files with compression aren't supported. Convert it to RVZ or ISO in Dolphin.");

    const tableBytes = async (offset, size) => {
      const bytes = await readBytes(blob, offset, size);
      return compression === 5 ? unzstd(bytes) : bytes;
    };
    const rawTable = await tableBytes(rawOffset, rawSize);
    const raws = [];
    for (let i = 0; i < rawCount; ++i) {
      const o = i * 24;
      raws.push({ offset: be64(rawTable, o), size: be64(rawTable, o + 8), group: be32(rawTable, o + 16), groups: be32(rawTable, o + 20) });
    }
    const entry = isRvz ? 12 : 8;
    const groupTable = await tableBytes(groupOffset, groupSize);
    const groups = [];
    for (let i = 0; i < groupCount; ++i) {
      const o = i * entry;
      const size = be32(groupTable, o + 4);
      groups.push({
        offset: be32(groupTable, o) * 4,
        size: isRvz ? size & 0x7fffffff : size,
        compressed: isRvz ? (size & 0x80000000) !== 0 && compression === 5 : compression === 5,
        packed: isRvz ? be32(groupTable, o + 8) : 0,
      });
    }

    // RVZ "packing": runs of literal bytes and runs of generated junk (padding Nintendo's mastering tools
    // filled with pseudo-random data). Junk is never part of a file, so it comes back as zeros here.
    function unpack(data, length) {
      const out = new Uint8Array(length);
      let i = 0;
      let o = 0;
      while (o < length && i + 4 <= data.length) {
        const word = be32(data, i);
        i += 4;
        const n = Math.min(word & 0x7fffffff, length - o);
        if (word & 0x80000000) {
          i += 68; // junk generator seed
        } else {
          out.set(data.subarray(i, i + n), o);
          i += word & 0x7fffffff;
        }
        o += n;
      }
      return out;
    }

    const cache = new Map();
    async function group(index, length) {
      if (cache.has(index)) return cache.get(index);
      const g = groups[index];
      let data;
      if (!g) throw new ExtractError("This RVZ file's group table is damaged.");
      if (g.size === 0) data = new Uint8Array(length);
      else {
        let bytes = await readBytes(blob, g.offset, g.size);
        if (g.compressed) bytes = unzstd(bytes);
        data = g.packed ? unpack(bytes, length) : bytes;
      }
      if (cache.size > 8) cache.delete(cache.keys().next().value);
      cache.set(index, data);
      return data;
    }

    async function readAt(offset, out, at, n) {
      if (offset < 0x80) {
        const k = Math.min(0x80 - offset, n);
        out.set(discHeader.subarray(offset, offset + k), at);
        return k;
      }
      for (const r of raws) {
        if (offset < r.offset || offset >= r.offset + r.size) continue;
        const skipped = r.offset % 0x8000; // entries are laid out from a 0x8000-aligned start
        const start = r.offset - skipped;
        const size = r.size + skipped;
        const index = Math.floor((offset - start) / chunkSize);
        const inGroup = offset - start - index * chunkSize;
        const length = Math.min(chunkSize, size - index * chunkSize);
        const data = await group(r.group + index, length);
        const k = Math.min(length - inGroup, n);
        if (data.length < inGroup + k) throw new ExtractError("A group in this RVZ file is damaged.");
        out.set(data.subarray(inGroup, inGroup + k), at);
        return k;
      }
      // Not stored: reads as zeros.
      return Math.min(n, 0x8000 - (offset % 0x8000));
    }

    return {
      format: isRvz ? "RVZ" : "WIA",
      size: isoSize,
      async read(offset, length) {
        const out = new Uint8Array(length);
        let done = 0;
        while (done < length) done += await readAt(offset + done, out, done, length - done);
        return out;
      },
    };
  }

  async function openDisc(blob) {
    if (blob.size < 0x440) throw new ExtractError("This file is too small to be a GameCube disc image.");
    const magic = await readBytes(blob, 0, 4);
    if (ascii(magic, 0, 4) === "CISO") return cisoReader(blob);
    if (le32(magic, 0) === 0xb10bc001) return gczReader(blob);
    if (ascii(magic, 0, 4) === "RVZ\x01") return rvzReader(blob, true);
    if (ascii(magic, 0, 4) === "WIA\x01") return rvzReader(blob, false);
    if (ascii(magic, 0, 4) === "WBFS")
      throw new ExtractError("WBFS is a Wii format. Use an ISO, CISO, GCZ or RVZ of the GameCube disc.");
    const head = await readBytes(blob, 0x1c, 4);
    if (be32(head, 0) === 0xc2339f3d) return isoReader(blob);
    throw new ExtractError("This doesn't look like a GameCube disc image (ISO, CISO, GCZ or RVZ).");
  }

  async function sha1Hex(bytes) {
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", bytes));
    return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
  }

  async function extractDol(blob, onProgress) {
    const progress = onProgress || (() => {});
    progress("Reading the disc image…");
    const disc = await openDisc(blob);

    const header = await disc.read(0, 0x440);
    if (be32(header, 0x1c) !== 0xc2339f3d)
      throw new ExtractError("This isn't a GameCube disc image. (Wii discs aren't supported.)");
    const id = ascii(header, 0, 6);
    const title = ascii(header, 0x20, 0x40).replace(/\0.*$/s, "").trim();
    if (id !== GAME_ID)
      throw new ExtractError(
        `This disc is ${title || "another game"} (${id}). You need Phantasy Star Online Episode I & II ` +
          `Plus for GameCube, USA version (${GAME_ID}).`);

    progress("Finding PsoV3.dol…");
    const fstOffset = be32(header, 0x424);
    const fstSize = be32(header, 0x428);
    if (!fstSize || fstSize > 16 * 1024 * 1024) throw new ExtractError("This disc's file list is damaged.");
    const fst = await disc.read(fstOffset, fstSize);
    const count = be32(fst, 8);
    const names = count * 12;
    let file = null;
    for (let i = 1; i < count && names < fst.length; ++i) {
      const o = i * 12;
      if (fst[o] !== 0) continue; // directory
      const nameAt = names + (be32(fst, o) & 0xffffff);
      let end = nameAt;
      while (end < fst.length && fst[end] !== 0) ++end;
      if (ascii(fst, nameAt, end - nameAt).toLowerCase() === DOL_NAME) {
        file = { offset: be32(fst, o + 4), size: be32(fst, o + 8) };
        break;
      }
    }
    if (!file) throw new ExtractError("PsoV3.dol isn't on this disc. The image may be damaged or trimmed.");

    progress(`Copying PsoV3.dol (${(file.size / 1048576).toFixed(1)} MB)…`);
    const dol = await disc.read(file.offset, file.size);
    progress("Checking it…");
    const sha1 = await sha1Hex(dol);
    return { dol, sha1, format: disc.format, ok: sha1 === EXPECTED_SHA1 };
  }

  global.PSOExtract = { extractDol, ExtractError, EXPECTED_SHA1, GAME_ID };
})(typeof self !== "undefined" ? self : globalThis);
