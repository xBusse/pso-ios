# pso-ios

*Phantasy Star Online Episode I & II Plus* (GameCube, USA, `GPOE8P`) as a native iPhone and iPad app.

The game's PowerPC code is translated ahead of time into native ARM code (static recompilation), so the game
runs at full speed without a JIT. This is something an emulator can't do on a phone without jailbreaking or
special entitlements. Graphics, sound and the other GameCube hardware come from Dolphin's emulation code.

No game data is in this repo. You build the app from your own copy of the game, and the app reads the game
files from your own disc image.

## What you get

**Plays like a native app**
- Full speed on iPhone and iPad, with no JIT and no emulator setup.
- A start screen and settings menus that work with touch or a controller.
- **Game Files → Import disc image** takes an ISO, CISO, GCZ or RVZ from Files or iCloud Drive and sets the
  game up on the phone. It checks that the disc is the right game.
- Audio picks up again after calls and Siri. **Silent mode** chooses whether the ring switch mutes the game.

**Widescreen done in the game, not stretched**
- **Display**: Fill screen (default), Widescreen 16:9, Original 4:3 or Stretch.
- Fill screen and Widescreen show more of the 3D world rather than stretching it. The HP/TP panel, action
  palette, radar and the START menu's windows move to the screen's corners. Fades, the START menu backdrop
  and boss intro effects stretch across the whole screen. Other menus stay centered at their usual size.
- **HUD size** 50–150%.
- **Resolution** 1x–4x the GameCube's (2x by default).

**Touch controls built for PSO**
- A stick that's always shown, shown while your thumb is on it, or floating (appears where your thumb lands).
- **Tap action palette**: tap the game's own action palette to use an attack or technique. The chat icon
  presses Y and the R mark presses R.
- **Camera swipe**: drag sideways on the right half of the screen to turn the camera. **Camera speed** 50–400%.
  The original game can only recenter the camera behind you.
- **Edit touch layout**: move, resize, fade or remove any button.
- With the A button removed, tapping empty space presses A. With A and B both removed, a two-finger tap
  presses B. This lets you get through menus with the screen alone.
- **R button**: hold, or toggle (press once to switch to the second action palette, again to switch back).

**Controllers**
- Xbox, PlayStation and MFi controllers work. Touch controls hide while one is connected (configurable).
- **Controller** lets you choose which button presses each GameCube button.
- The right stick turns the camera.

**Online play**
- Play on community servers such as Schthack, or on a private server run by you or a friend (see
  [Online play](#online-play)).
- Works straight away. The app sets up the game's network settings for you, so you don't go through Sega's
  original setup program.

**Mods** (they switch off while you're on a public server)
- Infinite meseta, infinite HP/TP, and a mag you can feed at any time.
- **EXP boost** up to 1000x. The "+EXP" number after a kill shows the boosted amount.
- **Rare drop boost** up to 1024x, or Max, which makes every rare roll succeed.

## Online play

Settings → **Network** picks how the game goes online. In the game, choose **ONLINE GAME**. Leave the game's
own network settings (IP address and DNS) on automatic.

### Public server (for example Schthack)

1. Make an account on the server's website. It gives you a serial number, an access key and a password, and
   tells you which DNS address to use.
2. In the app, set **Network** to **Public server**. **Server address** is that DNS address. It's preset to
   Schthack's, so for Schthack you can leave it as it is.
3. Start the game and choose **ONLINE GAME**. The first time, the game asks for your serial number and access
   key (and possibly your password). It saves them on the memory card.

The game uses the phone's own internet connection. The DNS address points the game's lookups for Sega's old
servers at the community server instead.

### Private server ([newserv](https://github.com/fuzziqersoftware/newserv))

newserv is an open-source PSO server that runs on a computer (Mac, Linux or Windows). In this mode the app
doesn't use the phone's network stack for the game. It connects straight to newserv's "IP stack simulator",
which acts as the GameCube's whole network: it gives the game its IP address and answers its DNS lookups. The
app's server address is the computer running newserv, not a DNS server.

1. Build and set up newserv by following its README. In `system/config.json`, keep `"IPStackListen": [5059]`
   (the default port). To let anyone in without registering, set `"AllowUnregisteredUsers": true`.
2. Start newserv on the computer.
3. In the app, set **Network** to **Private server**. Set **Server address** to the computer's address, for
   example `192.168.1.20` on the same Wi-Fi. Port 5059 is used unless you add another one (`address:port`).
4. Start the game and choose **ONLINE GAME**.

To play with someone who isn't on your Wi-Fi, they need to reach port 5059 (TCP) on the computer running
newserv. You can forward that port on your router, or use a VPN such as Tailscale and enter the computer's
Tailscale name or address. Anyone else who connects to the same newserv (the app, or Dolphin with its
"tapserver" network adapter pointed at the same address) is on the same server and can join your games.

The first time the app goes online, iOS asks for permission to use the local network. A private server on
your Wi-Fi needs it.

## Building (Mac)

    brew install cmake ninja pkg-config
    git clone --recurse-submodules https://github.com/xBusse/pso-ios.git
    cd pso-ios
    make run DISC="/path/to/Phantasy Star Online Episode I & II Plus (USA) (Rev 2).ciso"

`DISC` takes an ISO or CISO and is only needed the first time. The build checks that `PsoV3.dol` matches
SHA-1 `0d85744b51d7379efb025a943d0cd5aaae2191a3`. A CISO converted back to ISO won't match the full-dump
hash, because CISO drops the disc's padding.

## Building for iOS without a Mac

[docs/build-with-github.md](docs/build-with-github.md) is a step-by-step guide to building the app on
GitHub's Macs from a browser: a private copy of this repo holds your `PsoV3.dol`, and the **Build iOS app**
workflow (`.github/workflows/build-ipa.yml`) builds the newest code from this repo and hands back the ipa.
It takes about 10 to 15 minutes: the **Build engine** workflow here (`.github/workflows/build-engine.yml`)
publishes a prebuilt engine for each change, the app and runtime with no game code, so a private build only
compiles the game module from its `PsoV3.dol` (`make ios-game`). Without an engine it falls back to a full build.

To get `PsoV3.dol` without Dolphin, open [the extractor page](https://xbusse.github.io/pso-ios/extract/)
(`docs/extract/`): it copies the file out of an ISO, CISO, GCZ or RVZ image inside your browser, uploads nothing,
and checks it's the right version.

## Building for iOS (Mac with Xcode)

    make ios                          # after `make extract DISC=...`, or:
    make ios DOL=/path/to/PsoV3.dol   # only the game program, copied out of the disc (e.g. with Dolphin)
    make ios-engine                   # the app without game code: build/pso-engine-<commit>.tar.gz
    make ios-game ENGINE=build/pso-engine-<commit>.tar.gz DOL=/path/to/PsoV3.dol
                                      # your game on a prebuilt engine (same commit), in minutes

This builds the recompiler if needed, recompiles `PsoV3.dol`, builds the runtime, game module and app for the
iOS SDK, and writes `build/PSO-unsigned-<date>-<time>.ipa` (`build/PSO-unsigned.ipa` links to the newest). Sign
and install it with your usual sideloading tool. If `iCloud Drive/pso-ios` exists, each new ipa is copied there too (`IPA_COPY_DIR=` to skip, or set another folder).

The game files aren't in the app. On the start screen, **Game Files → Import disc image** takes your ISO, CISO,
GCZ or RVZ from Files or iCloud Drive and extracts it on the phone (it checks the game ID and the `PsoV3.dol`
hash). This works with sideloading tools' "file picker fix", which only lets the picker hand over single files.
You can also drop the image into On My iPhone → PSO and use **Use disc image in app folder**, or copy an
`extracted/pso` folder there with Finder. Saves go to the app's `User` folder. `User/Logs` has `console.log`
and `dolphin.log` for debugging.

Put `background.png` or `background.jpg` in the app's folder to replace the start screen background.

App icon: `ios/icon/AppIcon.png` (1024×1024) goes into the app as an asset catalog. `make icon ICON=photo.png`
replaces it with your own picture (center-cropped); plain `make icon` redraws the default
(`scripts/make-icon.swift`). Then `make ios`. The menu font is Baloo 2 (SIL OFL, `ios/resources/fonts`).

## How it works

- **[DolRecomp](https://github.com/ExpansionPak/DolRecomp)** translates `PsoV3.dol`'s PowerPC code to C. The
  generated code keeps the GameCube's 32-bit, big-endian memory model, so the game logic runs unchanged.
- **[ModernGekko](https://github.com/ExpansionPak/ModernGekko)** is the runtime the generated C links against:
  Dolphin's video, audio and hardware emulation, without the CPU emulator.
- **[pso-decomp](https://github.com/xBusse/pso-decomp-ios)** supplies the names and boundaries of all 27,570
  functions (`make names`), used for debugging and patching. Its source is the reference for game behavior.

The disc's `sys/main.dol` is "switcher", a small launcher that only loads `files/PsoV3.dol`. `make extract`
puts `PsoV3.dol` in its place, so the real game is what gets recompiled.

How iOS differs from the Mac build (patches in `patches/`, all behind `IOS` / `DOLPHIN_IOS`):
- Video is Metal only; the app hands Dolphin a `CAMetalLayer` (`ios/src/PlatformIOS.mm`).
- No JIT: anything outside the recompiled code runs on Dolphin's interpreter, and vertex loading uses the
  portable loader. On the Mac, `STATICRECOMP_INTERPRETER=1` does the same, to reproduce iOS behavior.
- Audio goes through a RemoteIO AudioUnit (`AudioUnitStream`, `patches/dolphin-0002-ios-audio.patch`); Cubeb's
  CoreAudio code is macOS-only.
- Input comes from the on-screen pad or a connected controller.

Online play notes:
- The disc's other programs (such as `iwanaga.dol`, Sega's network setup program) aren't recompiled, so on
  iOS they'd run on the interpreter, which is far too slow. The game only starts that program when the memory
  card has no network settings file. The app ships one (`ios/resources/network`, automatic IP and DNS) and puts
  it on the card when it's missing.
- That file is tied to the memory card's serial number, which is why
  `patches/dolphin-0004-memcard-stable-serial.patch` makes the serial the same on every boot and every device.
- `patches/dolphin-0005-bba-builtin-no-spin.patch` stops the built-in network adapter's read thread from
  spinning while it waits.

Widescreen is done game-side by a ModernGekko mod, `mods/widescreen/widescreen.c` (linked into the iOS app; on
the Mac, `make run` builds it into `build/user/Mods` and `PSO_WIDE=1.3333` turns it on for 16:9 with the Stretch
aspect mode). It widens only the GPU copy of the game's main 3D projection, so the game's 2D keeps its 4:3
layout and shadow passes are untouched. While the HUD draws, it moves (and, for HUD size, scales) the status
panel, action palette, radar and START menu windows to the screen's edges. Full-screen quads (the START menu
backdrop, fades, boss intro motion blur) are stretched across the screen. Dolphin's widescreen hack isn't used:
it also widened the shadows and squeezed the HUD.

The Mods settings come from a second mod, `mods/cheats/cheats.c` (on the Mac,
`PSO_CHEATS=meseta,hp,mag,exp=4,rare=8`, any subset). Like the widescreen mod it only edits game memory around
hooked functions. It:
- refills HP/TP and meseta each frame, and raises HP while a hit is worked out so it can't kill;
- adds the extra EXP before the game's own level-limit clamp, and rewrites the "+EXP" popup to match;
- clears the mag's fullness when the item menu checks it;
- swaps the rare table's chances for higher ones during each drop roll.

It also turns the follow camera with the C-stick (`cam=` sets the speed in percent, 0 turns it off). That's
on whatever the cheat settings are.

## Status

- [x] Recompile: 1,085,944 instructions, 0 unknown; generated C compiles with clang
- [x] Runs on Mac (Metal) and on iPhone/iPad: menus, the whole game, controls, save/load
- [x] Online play on public servers (tested on Schthack) and private newserv servers
- [ ] Known issue: the "go to the calendar?" option from the clock prompt leads to a black screen
- [ ] Hosting a server from inside the app

## Credits

This project stands on other people's work:

- **[DolRecomp](https://github.com/ExpansionPak/DolRecomp)** and **[ModernGekko](https://github.com/ExpansionPak/ModernGekko)**
  by Hyperway and contributors (jw, Douglas Whittingham, smallington, flaffy, MrPoloGit and others): the recompiler
  and the runtime. ModernGekko in turn credits SpecialK / aharonahdoot's RecompCore.
- **[Dolphin](https://github.com/dolphin-emu/dolphin)** by the Dolphin Team: the video, audio and hardware
  emulation inside ModernGekko, and the emulator for everything not recompiled.
- **[pso-decomp](https://github.com/zeroz41/pso-decomp)** by zeroz and contributors: the decompilation that names
  the game's functions and documents how it works. It's built with encounter's
  [decomp-toolkit](https://github.com/encounter/decomp-toolkit) and [objdiff](https://github.com/encounter/objdiff).
- **[newserv](https://github.com/fuzziqersoftware/newserv)** by fuzziqersoftware: the open-source PSO server used for
  private play and for testing online support.
- **[Schthack](https://schtserv.com)**: the community server tested with.
- **[fzstd](https://github.com/101arrowz/fzstd)** by 101arrowz (MIT): Zstandard decoding in the extractor page.
- **[Baloo 2](https://github.com/EkType/Baloo2)** by Ek Type (SIL OFL): the menu font.

*Phantasy Star Online* is a trademark of SEGA. This project is not affiliated with or endorsed by SEGA or Nintendo,
and it includes no game data: you build it from your own copy of the game.
