cmake_minimum_required(VERSION 3.22.1)
project(telegram_bridge LANGUAGES CXX)

add_library(tdjson SHARED IMPORTED)
set_target_properties(
    tdjson
    PROPERTIES IMPORTED_LOCATION "${TDLIB_JNI_DIR}/${ANDROID_ABI}/libtdjson.so"
)

add_library(telegram_bridge SHARED telegram_bridge.cpp)
target_compile_features(telegram_bridge PRIVATE cxx_std_17)
target_compile_options(telegram_bridge PRIVATE -Wall -Wextra -Werror)
target_link_libraries(telegram_bridge PRIVATE tdjson log)
