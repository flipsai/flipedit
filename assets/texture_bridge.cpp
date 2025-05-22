#include <cstdint>
#include <cstring>

#ifdef _WIN32
#define EXPORT_API __declspec(dllexport)
#else
#define EXPORT_API __attribute__((visibility("default")))
#endif

extern "C" {
    /**
     * Copy frame data from a source buffer to a texture memory address
     * 
     * @param srcFrameData Pointer to the source RGBA frame data
     * @param destTexturePtr Pointer to the destination texture memory
     * @param width The width of the frame in pixels
     * @param height The height of the frame in pixels
     */
    EXPORT_API void copyFrameToTexture(void* srcFrameData, void* destTexturePtr, int32_t width, int32_t height) {
        if (!srcFrameData || !destTexturePtr || width <= 0 || height <= 0) {
            return;
        }
        
        // Calculate the size of the data in bytes (RGBA = 4 bytes per pixel)
        size_t dataSize = static_cast<size_t>(width * height * 4);
        
        // Copy the data directly to the texture memory
        std::memcpy(destTexturePtr, srcFrameData, dataSize);
    }
} 