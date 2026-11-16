cmake_minimum_required(VERSION 3.24)

# The game module on its own: the recompiled PsoV3.dol as an iOS dylib, for
# adding to a prebuilt engine (`make ios-game`). It needs only ModernGekko's
# vendored Dolphin sources (module-template, GXRuntime and the StaticRecomp
# ABI headers), not the runtime build or Dolphin's externals.
#
#   cmake -S ios/game-module -B build/ios/game -G Ninja -DCMAKE_SYSTEM_NAME=iOS \
#         -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
#         -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DPSO_GENERATED_DIR=<dolrecomp output>/generated
#   cmake --build build/ios/game --target gGPOE8P_recomp

project(PSOGameModule LANGUAGES C CXX)

if(NOT IOS)
  message(FATAL_ERROR "Configure this project with -DCMAKE_SYSTEM_NAME=iOS")
endif()

set(PSO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(DOLPHIN_DIR "${PSO_ROOT}/lib/ModernGekko/vendor/dolphin")
set(PSO_GENERATED_DIR "" CACHE PATH "DolRecomp output directory for PsoV3.dol (contains generated.h)")
set(PSO_MODULE_TARGET gGPOE8P_recomp)

if(NOT EXISTS "${PSO_GENERATED_DIR}/generated.h")
  message(FATAL_ERROR "Set PSO_GENERATED_DIR to the DolRecomp output (generated/) for PsoV3.dol")
endif()
if(NOT EXISTS "${DOLPHIN_DIR}/module-template/CMakeLists.txt")
  message(FATAL_ERROR "ModernGekko's Dolphin sources are missing; run `make module-sources`")
endif()

# Same switches the full iOS build sets for everything it compiles.
add_compile_definitions(DOLPHIN_IOS=1 DOLPHIN_NO_JIT=1)

include("${CMAKE_CURRENT_SOURCE_DIR}/../game-module.cmake")
