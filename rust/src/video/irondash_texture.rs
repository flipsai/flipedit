use irondash_texture::{Texture, PayloadProvider, BoxedPixelData, SimplePixelData};
use crate::common::types::FrameData;
use std::sync::{Arc, Mutex};
use log::{info, debug, warn};
use anyhow::Result;
use irondash_engine_context::EngineContext;
use std::sync::mpsc;

/// Frame provider that implements the PayloadProvider trait for irondash
/// This follows the exact pattern from the irondash texture example
pub struct FrameProvider {
    frame_data: Arc<Mutex<Option<FrameData>>>,
    width: u32,
    height: u32,
}

impl FrameProvider {
    pub fn new(width: u32, height: u32) -> Self {
        Self {
            frame_data: Arc::new(Mutex::new(None)),
            width,
            height,
        }
    }

    pub fn update_frame(&self, frame_data: FrameData) {
        if let Ok(mut guard) = self.frame_data.lock() {
            *guard = Some(frame_data);
        }
    }
}

impl PayloadProvider<BoxedPixelData> for FrameProvider {
    fn get_payload(&self) -> BoxedPixelData {
        if let Ok(frame_guard) = self.frame_data.lock() {
            if let Some(frame) = frame_guard.as_ref() {
                return SimplePixelData::new_boxed(
                    frame.width as i32,
                    frame.height as i32,
                    frame.data.clone()
                );
            }
        }

        // Return empty frame if no data available
        let empty_data = vec![0u8; (self.width * self.height * 4) as usize];
        SimplePixelData::new_boxed(self.width as i32, self.height as i32, empty_data)
    }
}

/// Create a new video texture using irondash - must be called from main thread
pub fn create_video_texture(width: u32, height: u32, engine_handle: i64) -> Result<i64> {
    let provider = Arc::new(FrameProvider::new(width, height));
    let texture = Texture::new_with_provider(engine_handle, provider)
        .map_err(|e| anyhow::anyhow!("Failed to create texture: {}", e))?;
    
    let texture_id = texture.id();
    info!("Created texture with ID: {}", texture_id);
    Ok(texture_id)
}

/// Create texture on main thread - this is the proper way for cross-thread calls
pub fn create_video_texture_on_main_thread(width: u32, height: u32, engine_handle: i64) -> Result<i64> {
    let (tx, rx) = mpsc::channel();

    // Schedule texture creation on main thread - this is critical for irondash
    EngineContext::perform_on_main_thread(move || {
        let result = create_video_texture(width, height, engine_handle);
        let _ = tx.send(result);
    })?;

    // Wait for result from main thread
    rx.recv().unwrap_or_else(|_| Err(anyhow::anyhow!("Failed to receive texture creation result")))
}

/// Create a texture with proper update mechanism for timeline player
/// This version handles cross-thread texture creation properly and provides GL context info
pub fn create_player_texture(width: u32, height: u32, engine_handle: i64) -> Result<(i64, Box<dyn Fn(FrameData) + Send + Sync>)> {
    let (tx, rx) = mpsc::channel();

    // Schedule texture creation on main thread
    EngineContext::perform_on_main_thread(move || {
        let result: Result<(i64, Box<dyn Fn(FrameData) + Send + Sync>)> = (|| {
            let provider = Arc::new(FrameProvider::new(width, height));
            let texture = Texture::new_with_provider(engine_handle, provider.clone())
                .map_err(|e| anyhow::anyhow!("Failed to create texture: {}", e))?;
            
            let texture_id = texture.id();
            
            // Convert to sendable texture for cross-thread frame invalidation
            let sendable_texture = texture.into_sendable_texture();
            
            // Create the REAL irondash update function
            let provider_weak = Arc::downgrade(&provider);
            let texture_id_for_logging = texture_id;
            let sendable_texture_for_global = sendable_texture.clone();
            let global_update_fn: Box<dyn Fn(FrameData) + Send + Sync> = Box::new(move |frame_data| {
                if let Some(provider) = provider_weak.upgrade() {
                    provider.update_frame(frame_data);
                    
                    // This is the critical part - mark frame available to trigger Flutter repaint
                    sendable_texture_for_global.mark_frame_available();
                } else {
                    debug!("Provider dropped for texture {}", texture_id_for_logging);
                }
            });
            
            // CRITICAL: Register this REAL update function in the global registry
            // This ensures update_video_frame() calls the actual irondash invalidation
            register_irondash_update_function(texture_id, global_update_fn);
            
            // Return a simple placeholder function (not used anymore)
            let return_update_fn: Box<dyn Fn(FrameData) + Send + Sync> = Box::new(move |_frame_data| {
                // No-op: all updates go through the global registry now
            });
            
            info!("Created player texture with ID: {} and registered REAL update function", texture_id);
            Ok((texture_id, return_update_fn))
        })();
        
        let _ = tx.send(result);
    })?;

    // Wait for result from main thread
    rx.recv().unwrap_or_else(|_| Err(anyhow::anyhow!("Failed to receive player texture creation result")))
}

/// Get Flutter's OpenGL context handle for sharing with GStreamer
/// This function extracts the GL context that Flutter is using so GStreamer can share it
pub fn get_flutter_gl_context_handle(_engine_handle: i64) -> Result<Option<u64>> {
    // For now, we return None since direct GL context extraction from Flutter
    // requires deeper integration with the Flutter engine's GL context
    // TODO: Implement proper GL context handle extraction from Flutter engine
    warn!("GL context handle extraction not yet implemented - using software rendering path");
    Ok(None)
}

/// Create a GL context message for GStreamer that references Flutter's GL context
/// This allows GStreamer GL elements to share the same GL context as Flutter
pub fn create_gl_context_message(flutter_gl_handle: Option<u64>) -> Option<String> {
    match flutter_gl_handle {
        Some(handle) => {
            info!("Creating GL context message with Flutter handle: {}", handle);
            // TODO: Create proper GStreamer GL context message
            // This would typically be: "gst-gl-context-handle=<handle>"
            Some(format!("gst-gl-context-handle={}", handle))
        },
        None => {
            warn!("No Flutter GL handle available - falling back to software rendering");
            None
        }
    }
}

/// Set GL context on GStreamer element for sharing
/// This function configures a GStreamer element to use the shared GL context
pub fn set_gl_context_on_element(_element: &gstreamer::Element, context_message: &str) -> Result<()> {
    // TODO: Implement proper GL context setting on GStreamer elements
    // This typically involves:
    // 1. Creating a GstGLContext from the handle
    // 2. Setting it on the GStreamer GL elements
    // 3. Ensuring the GL context is current during rendering
    warn!("GL context setting on element not yet implemented: {}", context_message);
    Ok(())
}

// Global registry for storing actual irondash texture update functions
lazy_static::lazy_static! {
    static ref IRONDASH_UPDATE_FUNCTIONS: Arc<Mutex<std::collections::HashMap<i64, Box<dyn Fn(FrameData) + Send + Sync>>>> = 
        Arc::new(Mutex::new(std::collections::HashMap::new()));
}

/// Register an irondash texture update function - this is the REAL update function
pub fn register_irondash_update_function(texture_id: i64, update_fn: Box<dyn Fn(FrameData) + Send + Sync>) {
    if let Ok(mut functions) = IRONDASH_UPDATE_FUNCTIONS.lock() {
        functions.insert(texture_id, update_fn);
        info!("Registered REAL irondash update function for texture {}", texture_id);
    }
}


/// Unregister an irondash texture update function
pub fn unregister_irondash_update_function(texture_id: i64) {
    if let Ok(mut functions) = IRONDASH_UPDATE_FUNCTIONS.lock() {
        functions.remove(&texture_id);
    }
}

/// Update video frame data - now calls the REAL irondash update functions
pub fn update_video_frame(frame_data: FrameData) -> Result<()> {
    let mut updated_count = 0;
    
    // Call the REAL irondash texture update functions
    if let Ok(functions) = IRONDASH_UPDATE_FUNCTIONS.lock() {
        for (texture_id, update_fn) in functions.iter() {
            update_fn(frame_data.clone());
            updated_count += 1;
        }
    }
    
    // Also call texture registry for compatibility
    crate::video::texture_registry::update_all_textures(frame_data);
    
    Ok(())
}

/// Get the number of active irondash textures
pub fn get_texture_count() -> usize {
    // Return count from texture registry for compatibility
    crate::video::texture_registry::get_texture_count()
}