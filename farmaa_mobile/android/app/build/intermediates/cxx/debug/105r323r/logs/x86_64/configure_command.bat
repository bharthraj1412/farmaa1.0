@echo off
"F:\\android sdk\\cmake\\3.22.1\\bin\\cmake.exe" ^
  "-HD:\\flutter\\flutter\\packages\\flutter_tools\\gradle\\src\\main\\scripts" ^
  "-DCMAKE_SYSTEM_NAME=Android" ^
  "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" ^
  "-DCMAKE_SYSTEM_VERSION=24" ^
  "-DANDROID_PLATFORM=android-24" ^
  "-DANDROID_ABI=x86_64" ^
  "-DCMAKE_ANDROID_ARCH_ABI=x86_64" ^
  "-DANDROID_NDK=F:\\android sdk\\ndk\\29.0.14206865" ^
  "-DCMAKE_ANDROID_NDK=F:\\android sdk\\ndk\\29.0.14206865" ^
  "-DCMAKE_TOOLCHAIN_FILE=F:\\android sdk\\ndk\\29.0.14206865\\build\\cmake\\android.toolchain.cmake" ^
  "-DCMAKE_MAKE_PROGRAM=F:\\android sdk\\cmake\\3.22.1\\bin\\ninja.exe" ^
  "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=G:\\farmaa project\\farmaa_mobile\\android\\app\\build\\intermediates\\cxx\\debug\\105r323r\\obj\\x86_64" ^
  "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=G:\\farmaa project\\farmaa_mobile\\android\\app\\build\\intermediates\\cxx\\debug\\105r323r\\obj\\x86_64" ^
  "-BG:\\farmaa project\\farmaa_mobile\\android\\app\\.cxx\\debug\\105r323r\\x86_64" ^
  -GNinja ^
  -Wno-dev ^
  --no-warn-unused-cli ^
  "-DCMAKE_BUILD_TYPE=debug"
