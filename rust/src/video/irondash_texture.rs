use irondash_texture::{Texture, PayloadProvider, BoxedPixelData, SimplePixelData};
use crate::common::types::FrameData;
use std::sync::{Arc, Mutex};
use log::{info, debug};
use anyhow::Result;


/// Frame provider that implements the PayloadProvider trait for irondash
struct FrameProvider {
    frame_data: Arc<Mutex<Option<FrameData>>>,
    width: u32,
    height: u32,
}

impl PayloadProvider<BoxedPixelData> for FrameProvider {
    fn get_payload(&self) -> BoxedPixelData {
        // Get the latest frame data
        if let Ok(frame_guard) = self.frame_data.lock() {
            if let Some(frame) = frame_guard.as_ref() {
                // Use the frame data from the video player
                return SimplePixelData::new_boxed(
                    frame.width as i32,
                    frame.height as i32,
                    frame.data.clone()
                );
            }
        }

        // Return empty frame if no data available
        debug!("No frame data available, returning empty frame");
        let empty_data = vec![0u8; (self.width * self.height * 4) as usize];
        SimplePixelData::new_boxed(self.width as i32, self.height as i32, empty_data)
    }
}

// Global storage for texture providers (simpler approach)
lazy_static::lazy_static! {
    static ref TEXTURE_PROVIDERS: Arc<Mutex<Vec<Arc<FrameProvider>>>> = Arc::new(Mutex::new(Vec::new()));
}

/// Create a new video texture using irondash
pub fn create_video_texture(width: u32, height: u32, engine_handle: i64) -> Result<i64> {
    let provider = Arc::new(FrameProvider {
        frame_data: Arc::new(Mutex::new(None)),
        width,
        height,
    });
    
    let texture = Texture::new_with_provider(engine_handle, provider.clone())?;
    let texture_id = texture.id();
    
    // Store the provider for frame updates
    if let Ok(mut providers) = TEXTURE_PROVIDERS.lock() {
        providers.push(provider);
    }
    
    // Note: We're not storing the texture itself as it's not needed for updates
    // The provider holds the frame data and irondash handles the texture lifecycle
    
    info!("Created irondash texture with ID: {}", texture_id);
    Ok(texture_id)
}

/// Update video frame data for all irondash textures
pub fn update_video_frame(frame_data: FrameData) -> Result<()> {
    if let Ok(providers) = TEXTURE_PROVIDERS.lock() {
        for provider in providers.iter() {
            if let Ok(mut frame_guard) = provider.frame_data.lock() {
                *frame_guard = Some(frame_data.clone());
            }
        }
    }
    debug!("Updated {} texture providers with new frame data", 
           TEXTURE_PROVIDERS.lock().map(|p| p.len()).unwrap_or(0));
    Ok(())
}

/// Get the number of active irondash textures
pub fn get_texture_count() -> usize {
    TEXTURE_PROVIDERS.lock().map(|p| p.len()).unwrap_or(0)
}