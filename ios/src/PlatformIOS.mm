// iOS host platform for the ModernGekko runtime: hands Dolphin a CAMetalLayer
// owned by the UIKit view, and runs the host loop on the runtime's thread.

#import "PSOHost.h"
#import "Settings.h"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <chrono>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "AudioCommon/AudioCommon.h"
#include "AudioCommon/SoundStream.h"
#include "Common/Config/Config.h"
#include "Common/WindowSystemInfo.h"
#include "Core/Config/GraphicsSettings.h"
#include "Core/Config/MainSettings.h"
#include "Core/Core.h"
#include "Core/CoreTiming.h"
#include "Core/HW/EXI/EXI.h"
#include "Core/HW/EXI/EXI_Device.h"
#include "Core/System.h"
#include "DolphinNoGUI/Platform.h"
#include "InputCommon/ControllerInterface/Touch/InputOverrider.h"
#include "VideoCommon/VideoConfig.h"
#include "moderngekko/runtime.hpp"
#include "pso_cheats.h"
#include "pso_widescreen.h"

namespace
{
CAMetalLayer* s_layer = nil;
float s_scale = 1.0f;

std::mutex s_runtime_mutex;
moderngekko::Runtime* s_runtime = nullptr;
std::atomic<bool> s_input_registered{false};
std::atomic<bool> s_booted{false};
std::atomic<bool> s_mods_loaded{false};
std::atomic<bool> s_game_started{false};

// Settings, kept here so they can be (re)applied once the runtime exists.
struct VideoSettings
{
  PSODisplayMode mode = PSODisplayFill;
  int screen_width = 16;
  int screen_height = 9;
  int scale = 2;
};
std::mutex s_settings_mutex;
VideoSettings s_video;
int s_volume = 100;

struct NetworkSettings
{
  PSONetworkMode mode = PSONetworkOff;
  std::string address;
};
NetworkSettings s_network;

// R toggle state. Only touched on the main thread (touch + controller input).
bool s_r_toggle = false;
bool s_r_down = false;
bool s_r_latched = false;
void (^s_r_handler)(bool) = nil;

void ApplySettingsNow()
{
  VideoSettings v;
  int volume;
  {
    std::lock_guard lock(s_settings_mutex);
    v = s_video;
    volume = s_volume;
  }
  // Widening is done game-side by the widescreen mod (mods/widescreen): the
  // 3D gets a wider projection, the 2D keeps its 4:3 layout with the HUD
  // moved to the screen edges, and Dolphin stretches the 4:3 frame to the
  // picture's aspect. Dolphin's own widescreen hack stays off: it also
  // widened the shadow pass and the HUD.
  Config::SetBase(Config::GFX_WIDESCREEN_HACK, false);
  float picture_aspect = 4.0f / 3.0f;
  switch (v.mode)
  {
  case PSODisplayOriginal: Config::SetBase(Config::GFX_ASPECT_RATIO, AspectMode::ForceStandard); break;
  case PSODisplayWidescreen:
    Config::SetBase(Config::GFX_ASPECT_RATIO, AspectMode::CustomStretch);
    Config::SetBase(Config::GFX_CUSTOM_ASPECT_RATIO_WIDTH, 16);
    Config::SetBase(Config::GFX_CUSTOM_ASPECT_RATIO_HEIGHT, 9);
    picture_aspect = 16.0f / 9.0f;
    break;
  case PSODisplayFill:
    Config::SetBase(Config::GFX_ASPECT_RATIO, AspectMode::CustomStretch);
    Config::SetBase(Config::GFX_CUSTOM_ASPECT_RATIO_WIDTH, std::max(1, v.screen_width));
    Config::SetBase(Config::GFX_CUSTOM_ASPECT_RATIO_HEIGHT, std::max(1, v.screen_height));
    picture_aspect = float(std::max(1, v.screen_width)) / float(std::max(1, v.screen_height));
    break;
  case PSODisplayStretch: Config::SetBase(Config::GFX_ASPECT_RATIO, AspectMode::Stretch); break;
  }
  pso_widescreen_set_factor(picture_aspect / (4.0f / 3.0f));
  Config::SetBase(Config::GFX_EFB_SCALE, std::clamp(v.scale, 1, 4));
  Config::SetBase(Config::MAIN_AUDIO_VOLUME, std::clamp(volume, 0, 100));
  if (s_booted)
    AudioCommon::UpdateSoundStream(Core::System::GetInstance());
}

// Points Dolphin's serial port 1 at the adapter for the chosen network mode. Returns the
// device type, for swapping it live.
ExpansionInterface::EXIDeviceType ApplyNetworkConfig()
{
  NetworkSettings n;
  {
    std::lock_guard lock(s_settings_mutex);
    n = s_network;
  }
  using ExpansionInterface::EXIDeviceType;
  EXIDeviceType type = EXIDeviceType::None;
  if (n.mode == PSONetworkPublic && !n.address.empty())
  {
    type = EXIDeviceType::EthernetBuiltIn;
    Config::SetBase(Config::MAIN_BBA_BUILTIN_DNS, n.address);
  }
  else if (n.mode == PSONetworkPrivate && !n.address.empty())
  {
    type = EXIDeviceType::EthernetTapServer;
    std::string dest = n.address;
    if (dest.find(':') == std::string::npos)
      dest += ":5059";
    Config::SetBase(Config::MAIN_BBA_TAPSERVER_DESTINATION, dest);
  }
  Config::SetBase(Config::MAIN_SERIAL_PORT_1, type);
  printf("PSO: network mode=%d address=%s\n", int(n.mode), n.address.c_str());
  return type;
}

// Runs `job` on the host loop thread while the game is up, so Dolphin's state
// is only touched from one place.
void RunOnHost(std::function<void(Core::System&)> job)
{
  if (s_booted)
    Core::QueueHostJob(std::move(job));
}

void SetRLatched(bool latched)
{
  if (s_r_latched == latched)
    return;
  s_r_latched = latched;
  if (s_r_handler)
  {
    void (^handler)(bool) = s_r_handler;
    dispatch_async(dispatch_get_main_queue(), ^{
      handler(latched);
    });
  }
}

class PlatformIOS final : public Platform
{
public:
  bool Init() override { return s_layer != nil; }
  void SetTitle(const std::string&) override {}

  void MainLoop() override
  {
    while (IsRunning())
    {
      UpdateRunningFlag();
      Core::HostDispatchJobs(Core::System::GetInstance());
      std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
  }

  WindowSystemInfo GetWindowSystemInfo() const override
  {
    // Dolphin's Metal backend takes a CAMetalLayer directly as the render
    // surface; on iOS its PrepareWindow step is a no-op.
    WindowSystemInfo wsi;
    wsi.type = WindowSystemType::MacOS;
    wsi.render_window = (__bridge void*)s_layer;
    wsi.render_surface = (__bridge void*)s_layer;
    wsi.render_surface_scale = s_scale;
    return wsi;
  }
};

// Diagnostics the user can read from the Files app (On My iPhone > PSO > User > Logs):
// console.log gets stdout/stderr (the static-recomp core prints there), and
// Dolphin's own log goes to dolphin.log. Logger.ini is only written if missing,
// so it can be edited on the device.
void SetUpLogging(NSString* user_dir)
{
  NSFileManager* fm = NSFileManager.defaultManager;
  NSString* logs = [user_dir stringByAppendingPathComponent:@"Logs"];
  NSString* config = [user_dir stringByAppendingPathComponent:@"Config"];
  [fm createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
  [fm createDirectoryAtPath:config withIntermediateDirectories:YES attributes:nil error:nil];

  const char* console = [logs stringByAppendingPathComponent:@"console.log"].fileSystemRepresentation;
  if (freopen(console, "w", stdout))
    setvbuf(stdout, nullptr, _IOLBF, 0);
  if (freopen(console, "a", stderr))
    setvbuf(stderr, nullptr, _IONBF, 0);

  NSString* ini = [config stringByAppendingPathComponent:@"Logger.ini"];
  if (![fm fileExistsAtPath:ini])
  {
    // Verbosity 4 = info. Types are Dolphin's short log names.
    NSString* text = @"[Options]\nWriteToFile = True\nWriteToConsole = True\nVerbosity = 4\n"
                     @"[Logs]\nBOOT = True\nCOMMON = True\nCORE = True\nDVD = True\nMI = True\n"
                     @"OSREPORT = True\nOSREPORT_HLE = True\nPowerPC = True\nVideo = True\n"
                     @"Host GPU = True\nAudio = True\nMASTER = True\n";
    [text writeToFile:ini atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
}

// Without a network settings file on the memory card, ONLINE GAME hands over to Sega's network
// setup program (iwanaga.dol on the disc). Only PsoV3.dol is recompiled, so that program runs on
// the interpreter and is far too slow on a phone. The app ships a settings file made on this
// build's memory card (automatic IP and DNS) and puts it on the card when there isn't one. The
// file is tied to the card's serial number, which dolphin-0004 keeps the same on every device.
void InstallNetworkSettings(NSString* user_dir)
{
  NSFileManager* fm = NSFileManager.defaultManager;
  NSString* card = [user_dir stringByAppendingPathComponent:@"GC/USA/Card A"];
  for (NSString* name in [fm contentsOfDirectoryAtPath:card error:nil])
  {
    if ([name hasSuffix:@"sega_network_information.gci"])
      return;
  }
  NSString* bundled = [NSBundle.mainBundle pathForResource:@"8P-G9AE-sega_network_information"
                                                    ofType:@"gci"
                                               inDirectory:@"network"];
  if (!bundled)
    return;
  [fm createDirectoryAtPath:card withIntermediateDirectories:YES attributes:nil error:nil];
  NSError* error = nil;
  if ([fm copyItemAtPath:bundled toPath:[card stringByAppendingPathComponent:bundled.lastPathComponent]
                   error:&error])
    printf("PSO: installed network settings on the memory card\n");
  else
    printf("PSO: couldn't install network settings: %s\n", error.localizedDescription.UTF8String);
}

ciface::Touch::ControlID ToControlID(PSOInput input)
{
  using namespace ciface::Touch;
  switch (input)
  {
  case PSOInputA: return GCPAD_A_BUTTON;
  case PSOInputB: return GCPAD_B_BUTTON;
  case PSOInputX: return GCPAD_X_BUTTON;
  case PSOInputY: return GCPAD_Y_BUTTON;
  case PSOInputZ: return GCPAD_Z_BUTTON;
  case PSOInputStart: return GCPAD_START_BUTTON;
  case PSOInputDpadUp: return GCPAD_DPAD_UP;
  case PSOInputDpadDown: return GCPAD_DPAD_DOWN;
  case PSOInputDpadLeft: return GCPAD_DPAD_LEFT;
  case PSOInputDpadRight: return GCPAD_DPAD_RIGHT;
  case PSOInputL: return GCPAD_L_DIGITAL;
  case PSOInputR: return GCPAD_R_DIGITAL;
  case PSOInputStickX: return GCPAD_MAIN_STICK_X;
  case PSOInputStickY: return GCPAD_MAIN_STICK_Y;
  case PSOInputCStickX: return GCPAD_C_STICK_X;
  case PSOInputCStickY: return GCPAD_C_STICK_Y;
  }
  return GCPAD_A_BUTTON;
}
}  // namespace

std::unique_ptr<Platform> MODERNGEKKO_CreateExternalPlatform()
{
  return std::make_unique<PlatformIOS>();
}

void PSOSetRenderLayer(CAMetalLayer* layer, float scale)
{
  s_layer = layer;
  s_scale = scale;
}

void PSOStartGame(NSString* game_dir, NSString* user_dir, NSString* module_path,
                  void (^on_exit)(NSString* error))
{
  SetUpLogging(user_dir);
  InstallNetworkSettings(user_dir);
  printf("PSO: game=%s user=%s module=%s\n", game_dir.UTF8String, user_dir.UTF8String,
         module_path.UTF8String);
  printf("PSO: layer bounds=%.0fx%.0f scale=%.1f\n", s_layer.bounds.size.width,
         s_layer.bounds.size.height, s_scale);

  const std::string game = game_dir.UTF8String;
  const std::string user = user_dir.UTF8String;
  const std::string module = module_path.UTF8String;

  // Read on the main thread, before the runtime thread starts.
  // Troubleshooting: an empty file named "no-mods" in the User folder starts the game
  // with no mods at all. Otherwise widescreen always loads (Settings > Display controls
  // it) and the cheats load unless Settings > Mods > LOAD CHEATS is off.
  const bool no_mods =
      [NSFileManager.defaultManager fileExistsAtPath:[user_dir stringByAppendingPathComponent:@"no-mods"]];
  const bool load_cheats = PSOSettings.modsEnabled && !no_mods;
  s_mods_loaded = load_cheats;
  s_game_started = true;
  const bool speed_log = PSOSettings.speedLog;
  NSThread* thread = [[NSThread alloc] initWithBlock:^{
    moderngekko::RuntimeConfig config;
    config.game_root = game;
    config.user_directory = user;
    // With the game module (built from your own PsoV3.dol) the game runs recompiled.
    // Without it -- the public build, which has no game code -- the runtime runs the
    // game's own code from the disc on the CachedInterpreter.
    if ([NSFileManager.defaultManager fileExistsAtPath:@(module.c_str())])
    {
      config.module = moderngekko::ModuleSource::DynamicPath(module);
    }
    else
    {
      printf("PSO: no game module in the app, running on the interpreter\n");
      config.allow_interpreter = true;
    }
    // Settings > Debug > SPEED LOG: speed and CPU position every 2 s in console.log (User/Logs).
    if (speed_log)
      setenv("STATICRECOMP_HEARTBEAT", "1", 1);
    if (no_mods)
      printf("PSO: User/no-mods found, starting without mods\n");
    else
      config.attached_mods.push_back(pso_widescreen_descriptor());
    if (load_cheats)
      config.attached_mods.push_back(pso_cheats_descriptor());
    else if (!no_mods)
      printf("PSO: cheats turned off, starting without them\n");
    config.graphics.backend = "Metal";
    config.show_fps_in_title = false;

    NSString* error = nil;
    printf("PSO: creating runtime\n");
    auto created = moderngekko::Runtime::Create(std::move(config));
    if (!created)
    {
      error = [NSString stringWithFormat:@"Couldn't start the game: %s",
                                         created.error ? created.error->message.c_str() : "unknown error"];
    }
    else
    {
      for (int id = ciface::Touch::FIRST_GC_CONTROL; id <= ciface::Touch::LAST_GC_CONTROL; ++id)
        ciface::Touch::ClearControlState(0, static_cast<ciface::Touch::ControlID>(id));
      ciface::Touch::RegisterGameCubeInputOverrider(0);
      s_input_registered = true;
      ApplySettingsNow();
      ApplyNetworkConfig();
      s_booted = true;

      {
        std::lock_guard lock(s_runtime_mutex);
        s_runtime = created.runtime.get();
      }
      printf("PSO: runtime created, running\n");
      const moderngekko::RuntimeRunResult result = created.runtime->Run();
      printf("PSO: runtime returned%s%s\n", result.error ? ": " : "",
             result.error ? result.error->message.c_str() : "");
      {
        std::lock_guard lock(s_runtime_mutex);
        s_runtime = nullptr;
      }
      s_input_registered = false;
      s_booted = false;
      if (result.error)
        error = [NSString stringWithUTF8String:result.error->message.c_str()];
      created.runtime.reset();
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      on_exit(error);
    });
  }];
  thread.name = @"PSO runtime";
  thread.stackSize = 16 * 1024 * 1024;
  thread.qualityOfService = NSQualityOfServiceUserInteractive;
  [thread start];
}

void PSOSetPaused(bool paused)
{
  std::lock_guard lock(s_runtime_mutex);
  if (!s_runtime)
    return;
  if (paused)
    s_runtime->Pause();
  else
    s_runtime->Resume();
}

void PSORequestStop(void)
{
  std::lock_guard lock(s_runtime_mutex);
  if (s_runtime)
    s_runtime->RequestStop();
}

static void SetTrigger(ciface::Touch::ControlID digital, ciface::Touch::ControlID analog, double value)
{
  ciface::Touch::SetControlState(0, digital, value > 0.5 ? 1.0 : 0.0);
  ciface::Touch::SetControlState(0, analog, value);
}

void PSOSetInput(PSOInput input, double value)
{
  if (!s_input_registered)
    return;
  if (input == PSOInputR && s_r_toggle)
  {
    // Flip on each press (rising edge); hold the latched state otherwise.
    const bool down = value > 0.5;
    if (down && !s_r_down)
      SetRLatched(!s_r_latched);
    s_r_down = down;
    SetTrigger(ciface::Touch::GCPAD_R_DIGITAL, ciface::Touch::GCPAD_R_ANALOG, s_r_latched ? 1.0 : 0.0);
    return;
  }
  ciface::Touch::SetControlState(0, ToControlID(input), value);
  // Triggers: drive the analog value with the digital press.
  if (input == PSOInputL)
    ciface::Touch::SetControlState(0, ciface::Touch::GCPAD_L_ANALOG, value);
  else if (input == PSOInputR)
    ciface::Touch::SetControlState(0, ciface::Touch::GCPAD_R_ANALOG, value);
}

void PSOClearInput(PSOInput input)
{
  if (!s_input_registered)
    return;
  if (input == PSOInputR && s_r_toggle)
  {
    s_r_down = false;  // releasing the button keeps the latched state
    return;
  }
  ciface::Touch::ClearControlState(0, ToControlID(input));
  if (input == PSOInputL)
    ciface::Touch::ClearControlState(0, ciface::Touch::GCPAD_L_ANALOG);
  else if (input == PSOInputR)
    ciface::Touch::ClearControlState(0, ciface::Touch::GCPAD_R_ANALOG);
}

void PSOClearAllInputs(void)
{
  s_r_down = false;
  SetRLatched(false);
  if (!s_input_registered)
    return;
  for (int id = ciface::Touch::FIRST_GC_CONTROL; id <= ciface::Touch::LAST_GC_CONTROL; ++id)
    ciface::Touch::ClearControlState(0, static_cast<ciface::Touch::ControlID>(id));
}

void PSOSetRToggle(bool enabled)
{
  if (s_r_toggle == enabled)
    return;
  s_r_toggle = enabled;
  s_r_down = false;
  SetRLatched(false);
  if (s_input_registered)
  {
    ciface::Touch::ClearControlState(0, ciface::Touch::GCPAD_R_DIGITAL);
    ciface::Touch::ClearControlState(0, ciface::Touch::GCPAD_R_ANALOG);
  }
}

bool PSOIsRLatched(void)
{
  return s_r_latched;
}

void PSOSetRLatchHandler(void (^handler)(bool latched))
{
  s_r_handler = [handler copy];
}

void PSOSetVideoSettings(PSODisplayMode mode, int screen_width, int screen_height, int resolution_scale)
{
  {
    std::lock_guard lock(s_settings_mutex);
    s_video = {mode, screen_width, screen_height, resolution_scale};
  }
  RunOnHost([](Core::System&) { ApplySettingsNow(); });
}

void PSOSetNetwork(PSONetworkMode mode, NSString* address)
{
  {
    std::lock_guard lock(s_settings_mutex);
    const std::string addr = address.UTF8String ?: "";
    // Settings are re-sent wholesale (e.g. on a display change); replugging the adapter then
    // would drop a live connection.
    if (s_network.mode == mode && s_network.address == addr)
      return;
    s_network = {mode, addr};
  }
  RunOnHost([](Core::System& system) {
    const auto type = ApplyNetworkConfig();
    // Unplugs the adapter for a second and plugs in the new one, as Dolphin's own settings do.
    system.GetExpansionInterface().ChangeDevice(ExpansionInterface::Slot::SP1, type,
                                                CoreTiming::FromThread::NON_CPU);
  });
}

void PSOSetHUDScale(int percent)
{
  pso_widescreen_set_hud_scale(std::clamp(percent, 25, 200) / 100.0f);
}

void PSOSetCheats(bool infinite_meseta, bool infinite_hp_tp, bool mag_always_hungry, int exp_multiplier,
                  int rare_multiplier)
{
  pso_cheats_set_infinite_meseta(infinite_meseta);
  pso_cheats_set_infinite_hp_tp(infinite_hp_tp);
  pso_cheats_set_mag_always_hungry(mag_always_hungry);
  pso_cheats_set_exp_multiplier(exp_multiplier);
  pso_cheats_set_rare_multiplier(rare_multiplier);
}

bool PSOModsLoaded(void)
{
  // Before the game starts (the start screen's settings), the mods load if the setting says so.
  return s_game_started ? s_mods_loaded.load() : (bool)PSOSettings.modsEnabled;
}

void PSOSetCameraSpeed(int percent)
{
  pso_cheats_set_camera_speed(percent);
}

void PSOSetVolume(int percent)
{
  {
    std::lock_guard lock(s_settings_mutex);
    s_volume = percent;
  }
  RunOnHost([](Core::System&) { ApplySettingsNow(); });
}

void PSORestartAudio(void)
{
  RunOnHost([](Core::System& system) {
    // After an interruption iOS has stopped the output unit behind Dolphin's
    // back; Dolphin still thinks it's running. Stop and start it again.
    SoundStream* stream = system.GetSoundStream();
    if (!stream || !system.IsSoundStreamRunning())
      return;
    stream->SetRunning(false);
    stream->SetRunning(true);
    AudioCommon::UpdateSoundStream(system);
  });
}

bool PSOIsGameRunning(void)
{
  return s_booted;
}

bool PSOIsActionPaletteVisible(void)
{
  return s_booted && pso_widescreen_action_palette_visible();
}
