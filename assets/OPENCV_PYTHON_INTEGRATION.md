# OpenCV Python Integration for FlipEdit

This directory contains the files needed to enable direct frame processing and rendering from Python to Flutter using OpenCV and shared textures.

## Architecture Overview

The integration uses a combination of:

1. **Python with OpenCV** for frame processing
2. **C/C++ Bridge Library** for direct memory sharing
3. **Flutter Texture** for efficient display without copying data

Data flows directly from Python to Flutter texture memory for maximum performance.

## Setup Instructions

### Prerequisites

- CMake 3.10+
- C++ compiler (gcc, clang, or MSVC)
- Python 3.7+ with pip

### Building the Texture Bridge

1. Navigate to this directory in your terminal
2. Make the build script executable: `chmod +x build_texture_bridge.sh`
3. Run the build script: `./build_texture_bridge.sh`

This will compile the C++ bridge library for your platform and place it in the `bin` directory.

### Python Environment

The required Python dependencies are automatically installed by the UvManager class when it initializes. The dependencies include:

- websockets
- opencv-python
- numpy
- flask
- sqlalchemy

## How It Works

1. **Texture Creation**:
   - Flutter creates a texture using the TextureRgbaRenderer
   - The texture memory address is passed to Python via WebSocket

2. **Data Flow**:
   - Python generates frames using OpenCV
   - Frames are written directly to the texture memory using our C++ bridge
   - Flutter displays the texture without any data copying

3. **Control Flow**:
   - Flutter sends commands to Python via WebSocket (play/pause/frame change)
   - Python processes these commands and updates the rendering accordingly

## File Overview

- `main.py` - The Python WebSocket server that processes frames
- `texture_bridge.cpp` - C++ code for direct memory sharing
- `CMakeLists.txt` - CMake build file for the bridge library
- `build_texture_bridge.sh` - Script to build the bridge library

## Troubleshooting

### Common Issues

1. **Texture not showing**: Check that the texture ID is valid and being passed correctly

2. **Memory access violations**: Ensure the bridge library is built correctly for your platform

3. **Python crashes**: Check the Python logs for errors, especially related to OpenCV

4. **Poor performance**: Adjust the frame size or processing logic in Python

### Logs

- Python logs are visible in the Flutter console
- Check for errors in the bridge library during initialization

## Extending

To add new video processing effects:

1. Add new command handlers in `main.py`
2. Implement the OpenCV processing in Python
3. Update the Flutter UI to expose these new features 