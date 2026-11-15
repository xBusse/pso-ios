cmake_minimum_required(VERSION 3.24)

# iOS app for the PSO static recomp. Configure with the iOS SDK, e.g.:
#   cmake -S ios -B build/ios/cmake -G Ninja -DCMAKE_SYSTEM_NAME=iOS \
#         -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
#         -DPSO_GENERATED_DIR=<dolrecomp output>/generated
# `make ios` in the repo root does all of this.

project(PSOiOS LANGUAGES C CXX OBJC OBJCXX)

if(NOT IOS)
  message(FATAL_ERROR "Configure this project with -DCMAKE_SYSTEM_NAME=iOS")
endif()

set(PSO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(MG_DIR "${PSO_ROOT}/lib/ModernGekko")
set(DOLPHIN_DIR "${MG_DIR}/vendor/dolphin")
set(PSO_GENERATED_DIR "" CACHE PATH "DolRecomp output directory for PsoV3.dol (contains generated.h)")
set(PSO_BUNDLE_ID "com.xbusse.pso" CACHE STRING "App bundle identifier")
set(PSO_VERSION "0.1" CACHE STRING "App version")

if(NOT EXISTS "${PSO_GENERATED_DIR}/generated.h")
  message(FATAL_ERROR "Set PSO_GENERATED_DIR to the DolRecomp output (generated/) for PsoV3.dol")
endif()

# ---- Runtime (ModernGekko + Dolphin), built for iOS --------------------------

# Compile-time switches the iOS patches key on.
add_compile_definitions(DOLPHIN_IOS=1 DOLPHIN_NO_JIT=1)

# Dolphin looks up these macOS frameworks by name; iOS has none of them.
# Point them at Foundation so the link lines stay valid.
foreach(_lib APPKIT APPSERV CARBON COCOA FORCEFEEDBACK IOB IOK OPENGL)
  set(${_lib}_LIBRARY "-framework Foundation" CACHE STRING "" FORCE)
endforeach()
set(CORESERV_LIBRARY "-framework CoreServices" CACHE STRING "" FORCE)
set(COREFOUNDATION_LIBRARY "-framework CoreFoundation" CACHE STRING "" FORCE)
set(FOUNDATION_LIBRARY "-framework Foundation" CACHE STRING "" FORCE)

# Always use Dolphin's bundled libraries: anything found on the Mac (Homebrew)
# is built for macOS and can't link into an iOS app.
set(USE_SYSTEM_LIBS OFF CACHE STRING "" FORCE)

# curl's feature probes misfire when cross-compiling (struct timeval reported
# missing, pipe2 found in an SDK newer than the deployment target). Use its
# known-good Unix answers instead, which also mark pipe2 unavailable on Apple.
set(_CURL_PREFILL ON CACHE BOOL "" FORCE)

set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(MODERNGEKKO_ENABLE_DOLPHIN_TESTS OFF CACHE BOOL "" FORCE)
set(MODERNGEKKO_ENABLE_DISC_TOOL OFF CACHE BOOL "" FORCE)
set(ENABLE_VULKAN OFF CACHE BOOL "" FORCE)
set(USE_BUNDLED_MOLTENVK OFF CACHE BOOL "" FORCE)
set(MACOS_CODE_SIGNING OFF CACHE BOOL "" FORCE)
set(ENABLE_X11 OFF CACHE BOOL "" FORCE)

add_subdirectory("${MG_DIR}" moderngekko EXCLUDE_FROM_ALL)

# ---- Game module: the recompiled PsoV3.dol -----------------------------------

set(GAME_ID "GPOE8P" CACHE STRING "" FORCE)
set(GENERATED_DIR "${PSO_GENERATED_DIR}" CACHE PATH "" FORCE)
set(GXRUNTIME_DIR "${DOLPHIN_DIR}/GXRuntime" CACHE PATH "" FORCE)
set(CHASSIS_ABI_DIR "${DOLPHIN_DIR}/Source/Core/Core/PowerPC/StaticRecomp" CACHE PATH "" FORCE)
add_subdirectory("${DOLPHIN_DIR}/module-template" game-module EXCLUDE_FROM_ALL)
set(PSO_MODULE_TARGET gGPOE8P_recomp)
set_target_properties(${PSO_MODULE_TARGET} PROPERTIES
  INSTALL_NAME_DIR "@rpath"
  BUILD_WITH_INSTALL_NAME_DIR ON)

# ---- App ---------------------------------------------------------------------

add_executable(PSO MACOSX_BUNDLE
  src/main.mm
  src/PlatformIOS.mm
  src/GameViewController.mm
  src/TouchControls.mm
)
add_dependencies(PSO ${PSO_MODULE_TARGET})

set_target_properties(PSO PROPERTIES
  OUTPUT_NAME "PSO"
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
  MACOSX_BUNDLE_GUI_IDENTIFIER "${PSO_BUNDLE_ID}"
  MACOSX_BUNDLE_BUNDLE_NAME "PSO"
  MACOSX_BUNDLE_BUNDLE_VERSION "${PSO_VERSION}"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "${PSO_VERSION}"
  BUILD_RPATH "@executable_path/Frameworks"
  CXX_STANDARD 23
  CXX_STANDARD_REQUIRED ON
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)

target_compile_options(PSO PRIVATE -fobjc-arc)
target_compile_definitions(PSO PRIVATE _M_ARM_64=1 _ARCH_64=1
  PSO_MODULE_FILE="${PSO_MODULE_TARGET}.dylib")
target_include_directories(PSO PRIVATE
  "${MG_DIR}/include"
  "${DOLPHIN_DIR}/Source/Core"
  "${CMAKE_BINARY_DIR}/moderngekko/vendor/dolphin/Source/Core")

target_link_libraries(PSO PRIVATE
  moderngekko
  core
  uicommon
  inputcommon
  common
  "-framework UIKit"
  "-framework Metal"
  "-framework QuartzCore"
  "-framework GameController"
  "-framework AVFoundation"
  "-framework AudioToolbox"
  "-framework CoreAudio"
  "-framework CoreMotion"
  "-framework UniformTypeIdentifiers")

# Bundle layout: Dolphin's Sys data next to the executable, the game module in
# Frameworks/ (the app loads it with dlopen).
add_custom_command(TARGET PSO POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_directory "${DOLPHIN_DIR}/Data/Sys" "$<TARGET_BUNDLE_DIR:PSO>/Sys"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "$<TARGET_BUNDLE_DIR:PSO>/Frameworks"
  COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:${PSO_MODULE_TARGET}>" "$<TARGET_BUNDLE_DIR:PSO>/Frameworks/"
  COMMENT "Copying Sys data and the game module into PSO.app")
