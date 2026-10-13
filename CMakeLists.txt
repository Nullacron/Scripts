cmake_minimum_required(VERSION 3.15)
project(cvardumper CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Statically link the C++ runtime (/MT) so the DLL works on any PC without missing runtime errors
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Gather all source files in the root or src folder
file(GLOB_RECURSE SOURCES 
    "*.cpp"
    "*.hpp"
    "*.h"
)

# Build a dynamic library (.dll)
add_library(cvardumper SHARED ${SOURCES})

# Ensure standard symbol visibility
set_target_properties(cvardumper PROPERTIES
    OUTPUT_NAME "cvardumper"
    PREFIX ""
)
