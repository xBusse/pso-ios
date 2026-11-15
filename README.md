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
iOS SDK, and writes `build/PSO-unsigned-<date>-<time>.ipa` (`build/PSO-unsigned.ipa` links to the newest). Sign
and install it with your usual sideloading tool. If `iCloud Drive/pso-ios` exists, each new ipa is copied there too (`IPA_COPY_DIR=` to skip, or set another folder).

The game files aren't in the app. On the start screen, **Game Files → Import disc image** takes your ISO, CISO,
GCZ or RVZ from Files or iCloud Drive and extracts it on the phone (it checks the game ID and the `PsoV3.dol`
hash). This works with sideloading tools' "file picker fix", which only lets the picker hand over single files.
You can also drop the image into On My iPhone → PSO and use **Use disc image in app folder**, or copy an
`extracted/pso` folder there with Finder. Saves go to the app's `User` folder; `User/Logs` has `console.log`
and `dolphin.log` for debugging.

The app opens on a start screen (Play, Settings, Controls, Game Files), driven by touch or a controller
(d-pad/stick, A, B). In game, the ≡ button at the top (or the controller's Options button) pauses and opens
Resume / Settings / Edit touch controls / Quit. Settings:
- **Display**: Fill screen (default; widens the 3D view to the whole screen and moves the HUD and the START menu's
  windows to its corners; other menus stay centered), Widescreen 16:9, Original 4:3, Stretch.
- **HUD size** 50–150%: the HP/TP panel, action palette, radar (moved up into the corner, clear of the palette)
  and the START menu's windows, each kept in its corner.
- **Resolution** 1x–4x (default 2x), **Volume**, **Silent mode** (whether the ring switch mutes the game).
- **R button**: Hold, or Toggle (press once for the second action palette, again to go back).
- **Touch controls**: Auto (hidden while a controller is connected), Always, Hidden; overall opacity.
- **Stick**: always shown, shown only while your thumb is on it, or floating (appears where your thumb lands on
  the left half).
- **Tap action palette**: tapping a slot of the game's own action palette presses its button (A, B or X), the
  chat icon above them presses Y and the R mark presses R.
- **Camera swipe**: dragging sideways on empty space in the right half turns the camera, like a controller's right
  stick (the C-stick, which the cheats mod below makes turn the camera; the game itself only recenters it with L).
  **Camera speed** 50–400%.
- **Edit touch layout**: drag any control; select one to change its size and opacity, or remove it (removed
  controls show as a dashed outline in the editor, where they can be restored).
- **Controller**: choose which button on a Bluetooth controller presses each GameCube button (A, B, X, Y, Z, L, R,
  Start). Options/Home always open the pause menu.
- **Mods**: infinite meseta, infinite HP/TP, mag always hungry (feed any time), EXP boost (up to 10x) and rare
  drop boost (up to 32x). They apply to your own character, offline.

Put `background.png` or `background.jpg` in the app's folder to replace the start screen background.

App icon: `ios/icon/AppIcon.png` (1024×1024) goes into the app as an asset catalog. `make icon ICON=photo.png`
replaces it with your own picture (center-cropped); plain `make icon` redraws the default
(`scripts/make-icon.swift`). Then `make ios`. The menu font is Baloo 2 (SIL OFL, `ios/resources/fonts`).

How iOS differs from the Mac build (patches in `patches/`, all behind `IOS` / `DOLPHIN_IOS`):
- Video is Metal only; the app hands Dolphin a `CAMetalLayer` (`ios/src/PlatformIOS.mm`).
- No JIT: anything outside the recompiled code runs on the interpreter, and vertex loading uses the portable loader.
- Audio goes through a RemoteIO AudioUnit (`AudioUnitStream`, `patches/dolphin-0002-ios-audio.patch`); Cubeb's
  CoreAudio code is macOS-only.
- Input comes from the on-screen pad or a connected controller (Xbox/PlayStation/MFi).
- Audio recovers from interruptions (calls, Siri): the session is reactivated and the output unit restarted.

Widescreen is done game-side by a ModernGekko mod, `mods/widescreen/widescreen.c` (linked into the iOS app; on
the Mac, `make run` builds it into `build/user/Mods` and `PSO_WIDE=1.3333` turns it on for 16:9 with the Stretch
aspect mode). It widens only the GPU copy of the game's main 3D projection, so the game's 2D keeps its 4:3
layout and shadow passes are untouched, and moves (and sizes, for HUD size) the status panel, action palette, radar and START menu windows to the
screen's edges while they draw; the START menu's backdrop and the fades to black are stretched across the screen. Dolphin's widescreen hack isn't used: it also widened the shadows and squeezed the HUD.

The Mods settings come from a second mod, `mods/cheats/cheats.c` (on the Mac, `PSO_CHEATS=meseta,hp,mag,exp=4,rare=8`,
any subset). Like the widescreen mod it only edits game memory around hooked functions: it refills HP/TP and
meseta each frame, raises HP while a hit is worked out so it can't kill, adds the extra EXP before the game's own
level-limit clamp (and rewrites the "EXP+" popup to match), clears the mag's fullness when the item menu checks it, and swaps the rare table's chances for
higher ones during each drop roll. It also turns the follow camera with the C-stick (`cam=` sets the speed in
percent, 0 turns it off), which is on whatever the cheat settings.

## Status

- [x] Disc handling: CISO conversion, extraction, DOL check
- [x] Recompile: 1,085,944 instructions, 0 unknown; generated C compiles with clang
- [x] ModernGekko runtime built on macOS (local build, no CI)
- [x] Game module recompiles and loads (entry 0x8000C040)
- [x] Runs on Mac (Metal): menus, first area, controls, save/load all work
- [ ] Known issue: the "go to the calendar?" option from the clock prompt leads to a black screen
- [x] Metal video backend
- [ ] iOS: runtime builds for the iOS SDK, app boots, touch controls
