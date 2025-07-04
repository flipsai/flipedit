use flutter_rust_bridge::frb;
pub use crate::api::bridge::*;
use crate::video::player::VideoPlayer as InternalVideoPlayer;
use crate::video::timeline_player::TimelinePlayer as InternalTimelinePlayer;
pub use crate::common::types::{FrameData, TimelineData, TimelineClip, TimelineTrack, TextureFrame};
use crate::utils::testing;
use std::sync::{Arc, Mutex};
use anyhow::Result;
use crate::frb_generated::StreamSink;
use lazy_static::lazy_static;
use std::sync::Mutex as StdMutex;
use crate::video::pipeline::VideoPipeline;
use crate::video::frame_handler::FrameHandler;
use log::{debug, info};

lazy_static! {
    static ref ACTIVE_VIDEOS: StdMutex<Vec<VideoPipeline>> = StdMutex::new(Vec::new());
}

// Position update callback type
pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) + Send + Sync>;

#[frb(sync)]
pub fn greet(name: String) -> String {
    crate::api::bridge::greet(name)
}

pub struct VideoPlayer {
    inner: InternalVideoPlayer,
}

impl VideoPlayer {
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: InternalVideoPlayer::new(),
        }
    }

    #[frb(sync)]
    pub fn new_player() -> Self {
        Self::new()
    }

    #[frb(sync)]
    pub fn set_texture_ptr(&mut self, ptr: i64) {
        self.inner.set_texture_ptr(ptr);
    }

    pub fn load_video(&mut self, file_path: String) -> Result<(), String> {
        self.inner.load_video(file_path)
    }

    pub fn play(&mut self) -> Result<(), String> {
        self.inner.play()
    }

    pub fn pause(&mut self) -> Result<(), String> {
        self.inner.pause()
    }

    pub fn stop(&mut self) -> Result<(), String> {
        self.inner.stop()
    }

    pub fn setup_frame_stream(&mut self, sink: StreamSink<FrameData>) -> Result<()> {
        self.inner.set_frame_callback(Box::new(move |frame| {
            if let Err(e) = sink.add(frame) {
                // Log or handle the error appropriately
                // For now, we'll just print it to stderr
                eprintln!("Failed to send frame to sink: {:?}", e);
            }
            Ok(())
        }))?;
        Ok(())
    }

    /// Get current position and frame - Flutter can call this periodically
    #[frb(sync)]
    pub fn get_current_position_and_frame(&self) -> (f64, u64) {
        let position_seconds = self.inner.get_position_seconds();
        let frame_number = self.inner.get_current_frame_number();
        (position_seconds, frame_number)
    }

    #[frb(sync)]
    pub fn get_video_dimensions(&self) -> (i32, i32) {
        self.inner.get_video_dimensions()
    }

    #[frb(sync)]
    pub fn is_playing(&self) -> bool {
        self.inner.is_playing()
    }

    #[frb(sync)]
    pub fn get_latest_frame(&self) -> Option<FrameData> {
        self.inner.get_latest_frame()
    }
    
    /// Get the latest texture ID for GPU-based rendering
    #[frb(sync)]
    pub fn get_latest_texture_id(&self) -> u64 {
        self.inner.get_latest_texture_id()
    }
    
    /// Get texture frame data for GPU-based rendering
    #[frb(sync)]
    pub fn get_texture_frame(&self) -> Option<TextureFrame> {
        self.inner.get_texture_frame()
    }

    #[frb(sync)]
    pub fn has_audio(&self) -> bool {
        self.inner.has_audio()
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        self.inner.dispose()
    }

    #[frb(sync)]
    pub fn get_duration_seconds(&self) -> f64 {
        self.inner.get_duration_seconds()
    }

    #[frb(sync)]
    pub fn get_position_seconds(&self) -> f64 {
        self.inner.get_position_seconds()
    }

    #[frb(sync)]
    pub fn is_seekable(&self) -> bool {
        self.inner.is_seekable()
    }

    #[frb(sync)]
    pub fn get_frame_rate(&self) -> f64 {
        self.inner.get_frame_rate()
    }

    #[frb(sync)]
    pub fn get_total_frames(&self) -> u64 {
        self.inner.get_total_frames()
    }

    /// Extract frame at specific position for preview without seeking main pipeline
    pub fn extract_frame_at_position(&mut self, seconds: f64) -> Result<(), String> {
        self.inner.extract_frame_at_position(seconds)
    }

    /// Seek to final position with pause/resume control - used when releasing slider  
    pub fn seek_and_pause_control(&mut self, seconds: f64, was_playing_before: bool) -> Result<f64, String> {
        self.inner.seek_and_pause_control(seconds, was_playing_before)
    }

    /// Force synchronization between pipeline state and internal state
    pub fn sync_playing_state(&mut self) -> bool {
        self.inner.sync_playing_state()
    }

    pub fn seek_to_frame(&mut self, frame_number: u64) -> Result<(), String> {
        self.inner.seek_to_frame(frame_number).map(|_| ())
    }

    pub fn test_pipeline(&self, file_path: String) -> Result<(), String> {
        testing::test_pipeline(file_path)
    }
}

pub struct TimelinePlayer {
    inner: InternalTimelinePlayer,
}

impl TimelinePlayer {
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: InternalTimelinePlayer::new(),
        }
    }

    #[frb(sync)]
    pub fn set_texture_ptr(&mut self, ptr: i64) {
        self.inner.set_texture_ptr(ptr);
    }

    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<(), String> {
        self.inner.load_timeline(timeline_data)
    }

    pub fn set_position_ms(&mut self, position_ms: i32) {
        self.inner.set_position_ms(position_ms);
    }

    #[frb(sync)]
    pub fn get_position_ms(&self) -> i32 {
        self.inner.get_position_ms()
    }

    pub fn play(&mut self) -> Result<(), String> {
        self.inner.play()
    }

    pub fn pause(&mut self) -> Result<(), String> {
        self.inner.pause()
    }

    pub fn stop(&mut self) -> Result<(), String> {
        self.inner.stop()
    }

    #[frb(sync)]
    pub fn get_latest_frame(&self) -> Option<FrameData> {
        self.inner.frame_handler.get_latest_frame()
    }
    
    /// Get the latest texture ID for GPU-based rendering
    #[frb(sync)]
    pub fn get_latest_texture_id(&self) -> u64 {
        self.inner.frame_handler.get_latest_texture_id()
    }
    
    /// Get texture frame data for GPU-based rendering
    #[frb(sync)]
    pub fn get_texture_frame(&self) -> Option<TextureFrame> {
        self.inner.frame_handler.get_texture_frame()
    }

    #[frb(sync)]
    pub fn is_playing(&self) -> bool {
        self.inner.is_playing()
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        self.inner.dispose()
    }

    /// Test method to verify timeline logic - set position and check if frame should be shown
    #[frb(sync)]
    pub fn test_timeline_logic(&mut self, position_ms: i32) -> bool {
        self.inner.set_position_ms(position_ms);
        self.inner.frame_handler.should_show_frame()
    }
}

// =================== IRONDASH TEXTURE API ===================

/// Create a new video texture using irondash for zero-copy rendering
#[frb(sync)]
pub fn create_video_texture(width: u32, height: u32, engine_handle: i64) -> Result<i64, String> {
    crate::video::irondash_texture::create_video_texture(width, height, engine_handle)
        .map_err(|e| e.to_string())
}

/// Update video frame data for all irondash textures
#[frb(sync)]
pub fn update_video_frame(frame_data: FrameData) -> Result<(), String> {
    crate::video::irondash_texture::update_video_frame(frame_data)
        .map_err(|e| format!("Failed to update video frame: {}", e))
}

/// Get the number of active irondash textures
#[frb(sync)]
pub fn get_texture_count() -> usize {
    crate::video::irondash_texture::get_texture_count()
} 

/// Play a basic MP4 video and return irondash texture id
#[frb(sync)]
pub fn play_basic_video(file_path: String, engine_handle: i64) -> Result<i64, String> {
    // Create texture placeholder (1x1)
    let texture_id = crate::video::irondash_texture::create_video_texture(1, 1, engine_handle)
        .map_err(|e| e.to_string())?;

    // Build pipeline
    let handler = FrameHandler::new();
    let vp = VideoPipeline::new(&file_path, std::sync::Arc::new(std::sync::Mutex::new(handler)))
        .map_err(|e| e.to_string())?;
    vp.play().map_err(|e| e.to_string())?;

    ACTIVE_VIDEOS.lock().unwrap().push(vp);

    Ok(texture_id)
} 

#[frb(sync)]
pub fn play_dual_video(file_path_left: String, file_path_right: String, engine_handle: i64) -> Result<i64, String> {
    let texture_id = crate::video::irondash_texture::create_video_texture(1, 1, engine_handle)
        .map_err(|e| e.to_string())?;

    let handler = FrameHandler::new();
    let vp = VideoPipeline::new_dual(&file_path_left, &file_path_right, Arc::new(Mutex::new(handler)))
        .map_err(|e| e.to_string())?;
    vp.play().map_err(|e| e.to_string())?;

    ACTIVE_VIDEOS.lock().unwrap().push(vp);

    Ok(texture_id)
} 