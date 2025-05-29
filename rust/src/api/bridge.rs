use flutter_rust_bridge::frb;
use gstreamer as gst;
use log::{info, error};
use crate::common::logging::setup_logger;

#[frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    
    // Setup platform-specific logging
    setup_logger();
    
    // Initialize GStreamer with proper threading support
    match gst::init() {
        Ok(_) => info!("GStreamer initialized successfully"),
        Err(e) => error!("Failed to initialize GStreamer: {}", e),
    }
    
    // Print GStreamer version
    let (major, minor, micro, nano) = gst::version();
    info!("GStreamer version: {}.{}.{}.{}", major, minor, micro, nano);
} 