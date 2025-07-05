//! Export functionality for different formats

use anyhow::{Result}; // Context removed
// gst, ges removed
use log::{info}; // debug, warn removed
use std::path::Path;

use crate::v2::core::Timeline;
use super::renderer::Renderer;

#[derive(Debug)] // Ensure this is on ExportFormat as well
pub enum ExportFormat {
    MP4,
    WebM,
    GIF,
    PNG,
}

#[derive(Debug)] // Added Debug derive
pub struct ExportSettings {
    pub format: ExportFormat,
    pub width: u32,
    pub height: u32,
    pub framerate: f64,
    pub audio_bitrate: u32,
    pub video_bitrate: u32,
}

impl Default for ExportSettings {
    fn default() -> Self {
        Self {
            format: ExportFormat::MP4,
            width: 1920,
            height: 1080,
            framerate: 30.0,
            audio_bitrate: 192000,  // 192 kbps
            video_bitrate: 8000000, // 8 Mbps
        }
    }
}

pub struct Exporter {
    renderer: Renderer,
}

impl Exporter {
    pub fn new(timeline: &Timeline) -> Result<Self> {
        let renderer = Renderer::new(timeline)?;
        
        Ok(Exporter {
            renderer,
        })
    }
    
    pub fn export(&mut self, output_path: &Path, settings: &ExportSettings) -> Result<()> { // Changed to &mut self
        info!("Starting export with settings: {:?}", settings);
        
        // Convert ExportFormat to string for renderer
        let format_str = match settings.format {
            ExportFormat::MP4 => "mp4",
            ExportFormat::WebM => "webm",
            ExportFormat::GIF => "gif",
            ExportFormat::PNG => "png",
        };
        
        // Start rendering
        self.renderer.render_to_file(output_path, format_str)?;
        
        Ok(())
    }
    
    pub fn cancel_export(&mut self) -> Result<()> { // Already &mut self, ensure this is correct
        self.renderer.cancel_rendering()?; // This requires self.renderer to be &mut, which it is via &mut self
        info!("Export canceled");
        Ok(())
    }
    
    pub fn get_progress(&self) -> f64 {
        self.renderer.get_progress().percent
    }
}

// Helper functions for common export presets

pub fn create_web_preset() -> ExportSettings {
    ExportSettings {
        format: ExportFormat::WebM,
        width: 1280,
        height: 720,
        framerate: 30.0,
        audio_bitrate: 128000,  // 128 kbps
        video_bitrate: 2500000, // 2.5 Mbps
        ..Default::default()
    }
}

pub fn create_hd_preset() -> ExportSettings {
    ExportSettings {
        format: ExportFormat::MP4,
        width: 1920,
        height: 1080,
        framerate: 30.0,
        audio_bitrate: 192000,  // 192 kbps
        video_bitrate: 8000000, // 8 Mbps
        ..Default::default()
    }
}

pub fn create_4k_preset() -> ExportSettings {
    ExportSettings {
        format: ExportFormat::MP4,
        width: 3840,
        height: 2160,
        framerate: 30.0,
        audio_bitrate: 320000,   // 320 kbps
        video_bitrate: 45000000, // 45 Mbps
        ..Default::default()
    }
}