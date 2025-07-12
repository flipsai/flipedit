use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use crate::common::types::FrameData;

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
/// Get the number of registered textures
pub fn get_texture_count() -> usize {
    TEXTURE_REGISTRY.lock()
        .map(|registry| registry.texture_count())
        .unwrap_or(0)
}