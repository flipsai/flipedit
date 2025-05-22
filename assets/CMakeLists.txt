cmake_minimum_required(VERSION 3.10)
project(texture_bridge)

# Set C++ standard
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Define output directories
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Specify platform-specific output names
if(WIN32)
    set(TEXTURE_BRIDGE_OUTPUT_NAME "texture_bridge.dll")
elseif(APPLE)
    set(TEXTURE_BRIDGE_OUTPUT_NAME "libtexture_bridge.dylib")
else()
    set(TEXTURE_BRIDGE_OUTPUT_NAME "libtexture_bridge.so")
endif()

# Create the shared library
add_library(texture_bridge SHARED texture_bridge.cpp)

# Set output name
set_target_properties(texture_bridge PROPERTIES
    LIBRARY_OUTPUT_NAME "texture_bridge"
    RUNTIME_OUTPUT_NAME "texture_bridge"
)

# Installation rules
install(TARGETS texture_bridge
    LIBRARY DESTINATION ${PROJECT_SOURCE_DIR}/../bin
    RUNTIME DESTINATION ${PROJECT_SOURCE_DIR}/../bin
) 