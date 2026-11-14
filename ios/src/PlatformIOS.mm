// iOS host platform for the ModernGekko runtime: hands Dolphin a CAMetalLayer
// owned by the UIKit view, and runs the host loop on the runtime's thread.

#import "PSOHost.h"

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "Common/WindowSystemInfo.h"
#include "Core/Core.h"
#include "Core/System.h"
#include "DolphinNoGUI/Platform.h"
#include "InputCommon/ControllerInterface/Touch/InputOverrider.h"
#include "moderngekko/runtime.hpp"

namespace
{
CAMetalLayer* s_layer = nil;
float s_scale = 1.0f;

std::mutex s_runtime_mutex;
moderngekko::Runtime* s_runtime = nullptr;
std::atomic<bool> s_input_registered{false};

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
  const std::string game = game_dir.UTF8String;
  const std::string user = user_dir.UTF8String;
  const std::string module = module_path.UTF8String;

  NSThread* thread = [[NSThread alloc] initWithBlock:^{
    moderngekko::RuntimeConfig config;
    config.game_root = game;
    config.user_directory = user;
    config.module = moderngekko::ModuleSource::DynamicPath(module);
    config.graphics.backend = "Metal";
    config.show_fps_in_title = false;

    NSString* error = nil;
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

      {
        std::lock_guard lock(s_runtime_mutex);
        s_runtime = created.runtime.get();
      }
      const moderngekko::RuntimeRunResult result = created.runtime->Run();
      {
        std::lock_guard lock(s_runtime_mutex);
        s_runtime = nullptr;
      }
      s_input_registered = false;
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

void PSOSetInput(PSOInput input, double value)
{
  if (!s_input_registered)
    return;
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
  ciface::Touch::ClearControlState(0, ToControlID(input));
  if (input == PSOInputL)
    ciface::Touch::ClearControlState(0, ciface::Touch::GCPAD_L_ANALOG);
  else if (input == PSOInputR)
    ciface::Touch::ClearControlState(0, ciface::Touch::GCPAD_R_ANALOG);
}
