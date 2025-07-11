use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use crate::common::types::FrameData;
use log::{debug};

/// Global texture registry that maps texture IDs to update functions
/// This provides a safe way to update textures from any thread
pub struct TextureRegistry {
    update_functions: HashMap<i64, Box<dyn Fn(FrameData) + Send + Sync>>,
}

impl TextureRegistry {
    pub fn new() -> Self {
        Self {
            update_functions: HashMap::new(),
        }
    }

    /// Update all registered textures with the same frame data
    pub fn update_all_textures(&self, frame_data: FrameData) {
        for (texture_id, update_fn) in &self.update_functions {
            debug!("Updating texture {} with frame data", texture_id);
            update_fn(frame_data.clone());
        }
    }

    /// Get the number of registered textures
    pub fn texture_count(&self) -> usize {
        self.update_functions.len()
    }
}

lazy_static::lazy_static! {
    /// Global texture registry instance
    pub static ref TEXTURE_REGISTRY: Arc<Mutex<TextureRegistry>> = 
        Arc::new(Mutex::new(TextureRegistry::new()));
}

/// Update all registered textures with the same frame data  
pub fn update_all_textures(frame_data: FrameData) {
    if let Ok(registry) = TEXTURE_REGISTRY.lock() {
        registry.update_all_textures(frame_data);
    }
}

/// Get the number of registered textures
pub fn get_texture_count() -> usize {
    TEXTURE_REGISTRY.lock()
        .map(|registry| registry.texture_count())
        .unwrap_or(0)
}