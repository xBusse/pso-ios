#!/usr/bin/env python3
"""Convert a GameCube CISO (compact ISO) to a plain ISO.

CISO layout: "CISO", u32 little-endian block size, then a 0x7FF8-byte map
(one byte per block, 1 = stored). Stored blocks follow in order from 0x8000;
missing blocks are zero. The output is padded to the full GameCube disc
size (1,459,978,240 bytes) so its hash matches a full dump.
"""
import struct
import sys

GC_DISC_SIZE = 1_459_978_240
HEADER_SIZE = 0x8000


def convert(src_path: str, dst_path: str) -> None:
    with open(src_path, "rb") as src, open(dst_path, "wb") as dst:
        header = src.read(HEADER_SIZE)
        if header[:4] != b"CISO":
            sys.exit(f"{src_path}: not a CISO file")
        (block_size,) = struct.unpack_from("<I", header, 4)
        block_map = header[8:HEADER_SIZE]
        zero = bytes(block_size)
        written = 0
        for present in block_map:
            if written >= GC_DISC_SIZE:
                break
            if present == 1:
                block = src.read(block_size)
                if len(block) != block_size:
                    sys.exit(f"{src_path}: truncated at block {written // block_size}")
                dst.write(block)
            else:
                dst.write(zero)
            written += block_size
        if written < GC_DISC_SIZE:
            dst.seek(GC_DISC_SIZE - 1)
            dst.write(b"\0")
        dst.truncate(GC_DISC_SIZE)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: ciso2iso.py <input.ciso> <output.iso>")
    convert(sys.argv[1], sys.argv[2])
