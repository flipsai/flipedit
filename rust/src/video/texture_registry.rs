use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use crate::common::types::FrameData;
use log::{debug, warn};

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

    /// Register a texture update function
    pub fn register_texture(&mut self, texture_id: i64, update_fn: Box<dyn Fn(FrameData) + Send + Sync>) {
        self.update_functions.insert(texture_id, update_fn);
        debug!("Registered texture {}", texture_id);
    }

    /// Unregister a texture
    pub fn unregister_texture(&mut self, texture_id: i64) {
        self.update_functions.remove(&texture_id);
        debug!("Unregistered texture {}", texture_id);
    }

    /// Update a specific texture with frame data
    pub fn update_texture(&self, texture_id: i64, frame_data: FrameData) {
        if let Some(update_fn) = self.update_functions.get(&texture_id) {
            update_fn(frame_data);
        } else {
            warn!("No update function found for texture {}", texture_id);
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

/// Register a texture with its update function
pub fn register_texture(texture_id: i64, update_fn: Box<dyn Fn(FrameData) + Send + Sync>) {
    if let Ok(mut registry) = TEXTURE_REGISTRY.lock() {
        registry.register_texture(texture_id, update_fn);
    }
}

/// Unregister a texture
pub fn unregister_texture(texture_id: i64) {
    if let Ok(mut registry) = TEXTURE_REGISTRY.lock() {
        registry.unregister_texture(texture_id);
    }
}

/// Update a specific texture with frame data
pub fn update_texture(texture_id: i64, frame_data: FrameData) -> bool {
    if let Ok(registry) = TEXTURE_REGISTRY.lock() {
        registry.update_texture(texture_id, frame_data);
        true
    } else {
        false
    }
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