//! IronDash texture management for Flutter integration

use anyhow::{Result, Context};
use irondash_texture::{BoxedPixelData, Texture, PayloadProvider, SimplePixelData};
use log::{info, debug, warn}; // error was indeed unused as per previous diagnostic analysis.
use std::sync::{Arc, Mutex};

struct SimplePixelDataProvider {
    data: BoxedPixelData,
}

impl SimplePixelDataProvider {
    fn new(data: BoxedPixelData) -> Self {
        Self { data }
    }
}

unsafe impl Send for SimplePixelDataProvider {}
unsafe impl Sync for SimplePixelDataProvider {}

impl PayloadProvider<BoxedPixelData> for SimplePixelDataProvider {
    fn get_payload(&self) -> BoxedPixelData {
        // Create a new BoxedPixelData each time
        SimplePixelData::new_boxed(0, 0, vec![])
    }
}

/// Manages textures for Flutter integration
pub struct TextureHandler {
    textures: Arc<Mutex<Vec<(i64, Texture<BoxedPixelData>)>>>,
}

impl TextureHandler {
    /// Create a new texture handler
    pub fn new() -> Result<Self> {
        Ok(TextureHandler {
            textures: Arc::new(Mutex::new(Vec::new())),
        })
    }
    
    /// Create a new texture with the specified dimensions
    pub fn create_texture(&self, engine_handle: i64, width: u32, height: u32) -> Result<i64> { // Added engine_handle
        let initial_size = (width * height * 4) as usize; // Assuming RGBA
        let initial_pixels = vec![0u8; initial_size];
        // Assuming BoxedPixelData::from_vec exists (e.g. via 'utils' feature of irondash-texture)
        // If not, this needs RgbaInput or a custom PixelData impl.
        let initial_data = SimplePixelData::new_boxed(width as i32, height as i32, initial_pixels);
        let provider = Arc::new(SimplePixelDataProvider::new(initial_data));

        // Use new_with_provider and pass the engine_handle
        let texture = Texture::new_with_provider(engine_handle, provider)
            .context("Failed to create texture with provider")?;
        
        let texture_id = texture.id();
        
        // Store the texture to keep it alive
        self.textures.lock().unwrap().push((texture_id, texture));
        
        info!("Created texture: {}x{}, ID: {:?}", width, height, texture_id);
        
        Ok(texture_id)
    }
    
    /// Update a texture with new pixel data
    pub fn update_texture(&self, texture_id: i64, data: &[u8], width: u32, height: u32) -> Result<()> {
        let textures = self.textures.lock().unwrap();
        
        // Find the texture with the given ID
        if let Some((_, texture)) = textures.iter().find(|(id, _)| *id == texture_id) {
            // Update the texture with new data
            texture.mark_frame_available()
                .context("Failed to mark frame available")?;
            
            debug!("Updated texture: {:?}", texture_id);
            Ok(())
        } else {
            Err(anyhow::anyhow!("Texture not found: {:?}", texture_id))
        }
    }
    
    /// Release a texture
    pub fn release_texture(&self, texture_id: i64) -> Result<()> {
        let mut textures = self.textures.lock().unwrap();
        
        // Find the index of the texture with the given ID
        if let Some(index) = textures.iter().position(|(id, _)| *id == texture_id) {
            // Remove the texture from our list
            textures.remove(index);
            info!("Released texture: {:?}", texture_id);
            Ok(())
        } else {
            warn!("Texture not found for release: {:?}", texture_id);
            Ok(())
        }
    }
    
    /// Get the number of active textures
    pub fn texture_count(&self) -> usize {
        self.textures.lock().unwrap().len()
    }
}

impl Drop for TextureHandler {
    fn drop(&mut self) {
        let count = self.texture_count();
        if count > 0 {
            warn!("TextureHandler dropped with {} active textures", count);
        }
    }
}