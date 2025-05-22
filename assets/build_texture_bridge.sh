#!/bin/bash
# Script to build the texture bridge library for current platform

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
BUILD_DIR="$SCRIPT_DIR/build"
BIN_DIR="$SCRIPT_DIR/../bin"

# Make sure build directory exists
mkdir -p "$BUILD_DIR"
# Make sure bin directory exists
mkdir -p "$BIN_DIR"

echo "Building texture bridge in $BUILD_DIR"

# Change to build directory
cd "$BUILD_DIR"

# Run CMake
echo "Running CMake..."
cmake ..

# Build the library
echo "Building texture bridge..."
cmake --build . --config Release

# Copy the library to the bin directory
echo "Copying built library to $BIN_DIR"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    cp lib/*.dylib "$BIN_DIR/"
    chmod +x "$BIN_DIR/libtexture_bridge.dylib"
    echo "MacOS library built and copied to $BIN_DIR/libtexture_bridge.dylib"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    # Windows
    cp bin/Release/texture_bridge.dll "$BIN_DIR/"
    echo "Windows library built and copied to $BIN_DIR/texture_bridge.dll"
else
    # Linux
    cp lib/*.so "$BIN_DIR/"
    chmod +x "$BIN_DIR/libtexture_bridge.so"
    echo "Linux library built and copied to $BIN_DIR/libtexture_bridge.so"
fi

echo "Build complete!" 