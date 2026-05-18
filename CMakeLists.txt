cmake_minimum_required(VERSION 3.10)
project(VuronEngine)

# 1. Use the Modern C++ Standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 2. Automatically find all .cpp and .mm (Objective-C++) files
file(GLOB_RECURSE SOURCES "src/*.cpp" "src/*.mm")

# 3. Create the executable
add_executable(vuron_engine ${SOURCES}
        src/renderer/MetalRenderer.h)

# 4. Link the Apple Frameworks (Cocoa for Window, CoreVideo for Heartbeat)
# --- APPLE FRAMEWORKS ---
# We tell CMake to explicitly locate the exact paths to the macOS hardware libraries
find_library(COCOA_FW Cocoa)
find_library(COREVIDEO_FW CoreVideo)
find_library(METAL_FW Metal)
find_library(QUARTZCORE_FW QuartzCore)

# Then we hand those exact paths to our engine
target_link_libraries(vuron_engine PRIVATE
        ${COCOA_FW}
        ${COREVIDEO_FW}
        ${METAL_FW}
        ${QUARTZCORE_FW}
)

# 5. Set Include Directories (This lets you use #include "core/Memory.h" anywhere)
target_include_directories(vuron_engine PRIVATE src)

# 6. Optimization Flag (Optional: Forces -O3 in Release mode)
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")