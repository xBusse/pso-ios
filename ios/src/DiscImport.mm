// Extracts the PSO disc on the device, so a single disc image can be imported
// (sideloading tools' file picker fix only lets the picker hand over files).
// Produces the same layout as `make extract`: sys/ with PsoV3.dol as main.dol
// (the disc's own main.dol, "switcher", kept as switcher.dol) and files/.

#import "PSOHost.h"

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "Common/Crypto/SHA1.h"
#include "Common/FileUtil.h"
#include "DiscIO/DiscExtractor.h"
#include "DiscIO/Enums.h"
#include "DiscIO/Filesystem.h"
#include "DiscIO/Volume.h"

namespace
{
constexpr const char* kGameID = "GPOE8P";
constexpr const char* kPsoV3Sha1 = "0d85744b51d7379efb025a943d0cd5aaae2191a3";

u64 TotalSize(const DiscIO::FileInfo& dir)
{
  u64 total = 0;
  for (const DiscIO::FileInfo& f : dir)
    total += f.IsDirectory() ? TotalSize(f) : f.GetSize();
  return total;
}

struct Extractor
{
  const DiscIO::Volume& volume;
  DiscIO::Partition partition;
  u64 total = 1;
  u64 done = 0;
  std::string failed;
  void (^progress)(double) = nil;
  double last_reported = -1;

  void Export(const DiscIO::FileInfo& dir, const std::string& folder)
  {
    File::CreateFullPath(folder + "/");
    for (const DiscIO::FileInfo& f : dir)
    {
      if (!failed.empty())
        return;
      const std::string path = folder + "/" + f.GetName();
      if (f.IsDirectory())
      {
        Export(f, path);
        continue;
      }
      if (!DiscIO::ExportFile(volume, partition, &f, path))
      {
        failed = f.GetPath();
        return;
      }
      done += f.GetSize();
      const double fraction = static_cast<double>(done) / static_cast<double>(total);
      if (fraction - last_reported >= 0.005)
      {
        last_reported = fraction;
        void (^p)(double) = progress;
        dispatch_async(dispatch_get_main_queue(), ^{
          p(fraction);
        });
      }
    }
  }
};

std::string HexDigest(const Common::SHA1::Digest& digest)
{
  std::string hex;
  char buf[3];
  for (u8 b : digest)
  {
    std::snprintf(buf, sizeof(buf), "%02x", b);
    hex += buf;
  }
  return hex;
}

NSString* Extract(const std::string& image, const std::string& dest, void (^progress)(double))
{
  std::unique_ptr<DiscIO::Volume> volume = DiscIO::CreateVolume(image);
  if (!volume)
    return @"That file isn't a disc image this app can read (ISO, CISO, GCZ, RVZ or WIA).";
  if (volume->GetVolumeType() != DiscIO::Platform::GameCubeDisc)
    return @"That disc image isn't a GameCube disc.";
  const DiscIO::Partition partition = volume->GetGamePartition();
  const std::string id = volume->GetGameID(partition);
  if (id != kGameID)
  {
    return [NSString stringWithFormat:@"That disc is %s, not Phantasy Star Online Episode I & II Plus "
                                      @"(USA, %s).",
                                      id.c_str(), kGameID];
  }
  const DiscIO::FileSystem* fs = volume->GetFileSystem(partition);
  if (!fs || !fs->IsValid())
    return @"Couldn't read the disc's file system. The image may be damaged.";

  File::DeleteDirRecursively(dest);
  if (!DiscIO::ExportSystemData(*volume, partition, dest))
    return @"Couldn't write the disc's system files. Is the iPhone out of space?";

  const DiscIO::FileInfo& root = fs->GetRoot();
  Extractor extractor{*volume, partition};
  extractor.total = std::max<u64>(1, TotalSize(root));
  extractor.progress = progress;
  extractor.Export(root, dest + "/files");
  if (!extractor.failed.empty())
  {
    return [NSString stringWithFormat:@"Couldn't extract %s. Is the iPhone out of space?",
                                      extractor.failed.c_str()];
  }

  const std::string psov3 = dest + "/files/PsoV3.dol";
  std::string dol;
  if (!File::ReadFileToString(psov3, dol))
    return @"The disc has no PsoV3.dol. Is it the right game?";
  const std::string sha1 = HexDigest(Common::SHA1::CalculateDigest(dol));
  if (sha1 != kPsoV3Sha1)
  {
    return [NSString stringWithFormat:@"PsoV3.dol on this disc doesn't match the version the app was built "
                                      @"for (SHA-1 %s). The app needs the USA v1.02 (Rev 2) disc.",
                                      sha1.c_str()];
  }
  if (!File::Rename(dest + "/sys/main.dol", dest + "/sys/switcher.dol") ||
      !File::WriteStringToFile(dest + "/sys/main.dol", dol))
  {
    return @"Couldn't set up sys/main.dol.";
  }
  return nil;
}
}  // namespace

void PSOExtractDisc(NSString* image_path, NSString* dest, void (^progress)(double fraction),
                    void (^done)(NSString* error))
{
  const std::string image = image_path.fileSystemRepresentation;
  const std::string final_dest = dest.fileSystemRepresentation;
  void (^p)(double) = [progress copy];
  void (^d)(NSString*) = [done copy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    // Extract next to the destination, then swap it in, so a failed import
    // never leaves half a game behind.
    const std::string partial = final_dest + ".partial";
    NSString* error = Extract(image, partial, p);
    if (!error)
    {
      File::DeleteDirRecursively(final_dest);
      if (!File::Rename(partial, final_dest))
        error = @"Couldn't move the extracted files into place.";
    }
    if (error)
      File::DeleteDirRecursively(partial);
    dispatch_async(dispatch_get_main_queue(), ^{
      d(error);
    });
  });
}
