cmake_minimum_required(VERSION 3.10)

# Set the project name and version
project(Vuron VERSION 1.0)

# Specify the C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Define where header (.hpp) files are located
include_directories(include)

# Find all source files (.cpp)
file(GLOB_RECURSE SOURCES "src/*.cpp")

# Add the executable
add_executable(Vuron ${SOURCES}
        src/platform/platform.h
        src/platform/mac/MacWindow.h
        src/core/Memory.h
        src/core/Memory.cpp)

# Platform-specific configurations
if(APPLE)
    message(STATUS "Configuring for macOS")
    # Mac-specific libraries or definitions go here
elseif(WIN32)
    message(STATUS "Configuring for Windows")
    # Windows-specific libraries or definitions go here
endif()