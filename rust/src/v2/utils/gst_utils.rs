//! GStreamer utilities

use anyhow::{Result, Context};
use gstreamer; // Direct use instead of alias for is_initialized
use gstreamer_editing_services; // Direct use instead of alias for is_initialized
use gstreamer_pbutils; // For Discoverer
use gstreamer as gst; // Keep alias for other uses like gst::ClockTime, gst::Element etc.
use gstreamer_editing_services as ges; // Keep alias for other uses
use log::{info, debug, warn};
use std::path::Path;

/// Initialize GStreamer and GES
pub fn init_gstreamer() -> Result<()> {
    if !gstreamer::is_initialized() { // Use full path
        gstreamer::init().context("Failed to initialize GStreamer")?;
        info!("GStreamer initialized");
    }
    
    if !gstreamer_editing_services::is_initialized() { // Use full path
        gstreamer_editing_services::init().context("Failed to initialize GES")?;
        info!("GES initialized");
    }
    
    Ok(())
}

/// Check if a file exists and is a valid media file
pub fn check_media_file(file_path: &Path) -> Result<bool> {
    if !file_path.exists() {
        warn!("File does not exist: {:?}", file_path);
        return Ok(false);
    }
    
    // Create a discoverer to check the file
    let timeout = gst::ClockTime::from_seconds(5); // gst alias is fine here
    let discoverer = gstreamer_pbutils::Discoverer::new(timeout) // Use full path for Discoverer
        .context("Failed to create GStreamer Discoverer")?;
    
    // Convert path to URI
    let uri = format!("file://{}", file_path.to_string_lossy());
    
    // Discover the file
    match discoverer.discover_uri(&uri) {
        Ok(info) => {
            let has_video = info.video_streams().len() > 0;
            let has_audio = info.audio_streams().len() > 0;
            
            if has_video || has_audio {
                debug!("Valid media file: {:?} (video: {}, audio: {})", 
                       file_path, has_video, has_audio);
                Ok(true)
            } else {
                warn!("File is not a valid media file: {:?}", file_path);
                Ok(false)
            }
        },
        Err(err) => {
            warn!("Failed to discover file: {:?} - {}", file_path, err);
            Ok(false)
        }
    }
}

/// Get media file information
pub fn get_media_info(file_path: &Path) -> Result<gstreamer_pbutils::DiscovererInfo> { // Use full path for DiscovererInfo
    // Create a discoverer to check the file
    let timeout = gst::ClockTime::from_seconds(5); // gst alias is fine here
    let discoverer = gstreamer_pbutils::Discoverer::new(timeout) // Use full path for Discoverer
        .context("Failed to create GStreamer Discoverer")?;
    
    // Convert path to URI
    let uri = format!("file://{}", file_path.to_string_lossy());
    
    // Discover the file
    let info = discoverer.discover_uri(&uri)
        .context("Failed to discover media file")?;
    
    Ok(info)
}

/// Create a GStreamer element with properties
pub fn create_element(factory_name: &str, name: Option<&str>) -> Result<gst::Element> {
    let element = match name {
        Some(name) => gst::ElementFactory::make(factory_name)
            .name(name)
            .build()
            .with_context(|| format!("Failed to create element: {}", factory_name))?,
        None => gst::ElementFactory::make(factory_name)
            .build()
            .with_context(|| format!("Failed to create element: {}", factory_name))?,
    };
    
    Ok(element)
}

/// Link multiple GStreamer elements
pub fn link_elements(elements: &[&gst::Element]) -> Result<()> {
    gst::Element::link_many(elements)
        .context("Failed to link elements")?;
    
    Ok(())
}