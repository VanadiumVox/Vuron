cmake_minimum_required(VERSION 3.10)
project(VuronEngine)

# 1. Use the Modern C++ Standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 2. Automatically find all .cpp and .mm (Objective-C++) files
file(GLOB_RECURSE SOURCES "src/*.cpp" "src/*.mm")

# 3. Create the executable
add_executable(vuron_engine ${SOURCES})

# 4. Link the Apple Frameworks (Cocoa for Window, CoreVideo for Heartbeat)
target_link_libraries(vuron_engine "-framework Cocoa" "-framework CoreVideo")

# 5. Set Include Directories (This lets you use #include "core/Memory.h" anywhere)
target_include_directories(vuron_engine PRIVATE src)

# 6. Optimization Flag (Optional: Forces -O3 in Release mode)
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")