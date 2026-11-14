# pso-ios

A static-recompilation port of *Phantasy Star Online Episode I & II Plus* (GameCube, USA v1.02, `GPOE8P`),
aimed at iOS. Private, for personal use. No game data is in this repo; you supply your own disc.

## How it works

- **[DolRecomp](https://github.com/ExpansionPak/DolRecomp)** translates `PsoV3.dol`'s PowerPC code to C. The
  generated code keeps the GameCube's 32-bit, big-endian memory model, so the game logic runs unchanged.
- **[ModernGekko](https://github.com/ExpansionPak/ModernGekko)** is the runtime the generated C links against:
  Dolphin's video, audio and hardware emulation, without the CPU emulator.
- **[pso-decomp](https://github.com/xBusse/pso-decomp-ios)** supplies the names and boundaries of all 27,570
  functions (`make names`), used for debugging and patching. Its source is the reference for game behavior.

The disc's `sys/main.dol` is "switcher", a small launcher that only loads `files/PsoV3.dol`. `make extract`
puts `PsoV3.dol` in its place, so the real game is what gets recompiled.

## Building (Mac)

    brew install cmake ninja pkg-config
    git clone --recurse-submodules https://github.com/xBusse/pso-ios.git
    cd pso-ios
    make run DISC="/path/to/Phantasy Star Online Episode I & II Plus (USA) (Rev 2).ciso"

`DISC` takes an ISO or CISO and is only needed the first time. The build checks that `PsoV3.dol` matches
SHA-1 `0d85744b51d7379efb025a943d0cd5aaae2191a3`. A CISO converted back to ISO won't match the full-dump
hash, because CISO drops the disc's padding.

## Building for iOS (Mac with Xcode)

    make ios

This builds the Mac tools if needed, recompiles `PsoV3.dol`, builds the runtime, game module and app for the
iOS SDK, and writes `build/PSO-unsigned.ipa`. Sign and install it with your usual sideloading tool.

The game files aren't in the app. Copy them over once: connect the iPhone, open it in Finder, go to **Files**,
and drag `extracted/pso` onto **PSO**. Saves go to the app's `User` folder.

How iOS differs from the Mac build (patches in `patches/`, all behind `IOS` / `DOLPHIN_IOS`):
- Video is Metal only; the app hands Dolphin a `CAMetalLayer` (`ios/src/PlatformIOS.mm`).
- No JIT: anything outside the recompiled code runs on the interpreter, and vertex loading uses the portable loader.
- Input comes from the on-screen pad or a connected controller (Xbox/PlayStation/MFi).

## Status

- [x] Disc handling: CISO conversion, extraction, DOL check
- [x] Recompile: 1,085,944 instructions, 0 unknown; generated C compiles with clang
- [x] ModernGekko runtime built on macOS (local build, no CI)
- [x] Game module recompiles and loads (entry 0x8000C040)
- [x] Runs on Mac (Metal): menus, first area, controls, save/load all work
- [ ] Known issue: the "go to the calendar?" option from the clock prompt leads to a black screen
- [x] Metal video backend
- [ ] iOS: runtime builds for the iOS SDK, app boots, touch controls
