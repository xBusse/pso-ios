# The game module: the recompiled PsoV3.dol, built from ModernGekko's module
# template as a dylib the app loads from its Frameworks folder. Included by
# ios/CMakeLists.txt (the full build) and ios/game-module/CMakeLists.txt (the
# module on its own, for `make ios-game`). Expects DOLPHIN_DIR,
# PSO_GENERATED_DIR and PSO_MODULE_TARGET.

set(GAME_ID "GPOE8P" CACHE STRING "" FORCE)
set(GENERATED_DIR "${PSO_GENERATED_DIR}" CACHE PATH "" FORCE)
set(GXRUNTIME_DIR "${DOLPHIN_DIR}/GXRuntime" CACHE PATH "" FORCE)
set(CHASSIS_ABI_DIR "${DOLPHIN_DIR}/Source/Core/Core/PowerPC/StaticRecomp" CACHE PATH "" FORCE)
add_subdirectory("${DOLPHIN_DIR}/module-template" game-module EXCLUDE_FROM_ALL)
set_target_properties(${PSO_MODULE_TARGET} PROPERTIES
  INSTALL_NAME_DIR "@rpath"
  BUILD_WITH_INSTALL_NAME_DIR ON)
