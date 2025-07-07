use flutter_rust_bridge::frb;
pub use crate::api::bridge::*;
use crate::video::player::VideoPlayer as InternalVideoPlayer;
use crate::video::timeline_player::TimelinePlayer as InternalTimelinePlayer;
pub use crate::common::types::{FrameData, TimelineData, TimelineClip, TimelineTrack, TextureFrame};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gstreamer::prelude::*;
use crate::utils::testing;
use std::sync::{Arc, Mutex};
use anyhow::Result;
use crate::frb_generated::StreamSink;
use lazy_static::lazy_static;
use std::sync::Mutex as StdMutex;
use crate::video::pipeline::VideoPipeline;
use crate::video::frame_handler::FrameHandler;
use log::{info, warn};

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

    pub fn setup_position_stream(&mut self, sink: StreamSink<(f64, u64)>) -> Result<()> {
        self.inner.set_position_update_callback(Box::new(move |position, frame| {
            if let Err(e) = sink.add((position, frame)) {
                // Log or handle the error appropriately
                eprintln!("Failed to send position update to sink: {:?}", e);
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
            inner: InternalTimelinePlayer::new().expect("Failed to create TimelinePlayer"),
        }
    }


    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<(), String> {
        self.inner.load_timeline(timeline_data).map_err(|e| e.to_string())
    }

    pub fn set_position_ms(&mut self, position_ms: i32) {
        self.inner.seek(position_ms as u64).unwrap_or_else(|e| {
            eprintln!("Failed to seek to position: {}", e);
        });
    }

    #[frb(sync)]
    pub fn get_position_ms(&self) -> i32 {
        self.inner.get_current_position_ms() as i32
    }

    pub fn play(&mut self) -> Result<(), String> {
        self.inner.play().map_err(|e| e.to_string())
    }

    pub fn pause(&mut self) -> Result<(), String> {
        self.inner.pause().map_err(|e| e.to_string())
    }

    pub fn stop(&mut self) -> Result<(), String> {
        self.inner.dispose().map_err(|e| e.to_string())
    }

    #[frb(sync)]
    pub fn get_latest_frame(&self) -> Option<FrameData> {
        // TODO: Implement frame handling for timeline player
        None
    }
    
    /// Get the latest texture ID for GPU-based rendering
    #[frb(sync)]
    pub fn get_latest_texture_id(&self) -> u64 {
        // TODO: Implement texture ID for timeline player
        0
    }
    
    /// Get texture frame data for GPU-based rendering
    #[frb(sync)]
    pub fn get_texture_frame(&self) -> Option<TextureFrame> {
        // TODO: Implement texture frame for timeline player
        None
    }

    #[frb(sync)]
    pub fn is_playing(&self) -> bool {
        self.inner.is_playing()
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        self.inner.dispose().map_err(|e| e.to_string())
    }

    /// Test method to verify timeline logic - set position and check if frame should be shown
    #[frb(sync)]
    pub fn test_timeline_logic(&mut self, position_ms: i32) -> bool {
        self.inner.seek(position_ms as u64).unwrap_or_else(|e| {
            eprintln!("Failed to seek to position for test: {}", e);
        });
        // TODO: Implement frame checking logic
        true
    }
}

// GES timeline player implementation (currently using fallback to TimelinePlayer)
pub struct GESTimelinePlayer {
    inner: InternalTimelinePlayer,
}

impl GESTimelinePlayer {
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: InternalTimelinePlayer::new().expect("Failed to create GESTimelinePlayer"),
        }
    }


    /// Create texture for this player
    pub fn create_texture(&mut self, engine_handle: i64) -> Result<i64, String> {
        self.inner.create_texture(engine_handle).map_err(|e| e.to_string())
    }

    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<(), String> {
        self.inner.load_timeline(timeline_data).map_err(|e| e.to_string())
    }

    pub fn play(&mut self) -> Result<(), String> {
        self.inner.play().map_err(|e| e.to_string())
    }

    pub fn pause(&mut self) -> Result<(), String> {
        self.inner.pause().map_err(|e| e.to_string())
    }

    pub fn stop(&mut self) -> Result<(), String> {
        self.inner.dispose().map_err(|e| e.to_string())
    }

    pub fn seek_to_position(&mut self, position_ms: i32) -> Result<(), String> {
        self.inner.seek(position_ms as u64).map_err(|e| e.to_string())
    }

    #[frb(sync)]
    pub fn get_position_ms(&self) -> i32 {
        self.inner.get_current_position_ms() as i32
    }

    #[frb(sync)]
    pub fn get_duration_ms(&self) -> Option<i32> {
        self.inner.get_duration_ms().map(|d| d as i32)
    }

    #[frb(sync)]
    pub fn is_playing(&self) -> bool {
        self.inner.is_playing()
    }

    #[frb(sync)]
    pub fn is_seekable(&self) -> bool {
        true // GES timelines are always seekable
    }

    #[frb(sync)]
    pub fn get_latest_frame(&self) -> Option<FrameData> {
        None // Not implemented yet - need texture integration
    }

    #[frb(sync)]
    pub fn get_latest_texture_id(&self) -> u64 {
        0 // Not implemented yet - need texture integration
    }

    #[frb(sync)]
    pub fn get_texture_frame(&self) -> Option<TextureFrame> {
        None // Not implemented yet - need texture integration
    }

    /// Update position from GStreamer pipeline - call this regularly for smooth playhead updates
    #[frb(sync)]
    pub fn update_position(&self) {
        self.inner.update_position();
    }

    pub fn setup_frame_stream(&mut self, _sink: StreamSink<FrameData>) -> Result<()> {
        info!("Frame stream setup requested for GES timeline player (not yet implemented)");
        Ok(())
    }

    pub fn setup_position_stream(&mut self, sink: StreamSink<(f64, u64)>) -> Result<()> {
        self.inner.set_position_update_callback(Box::new(move |position, frame| {
            if let Err(e) = sink.add((position, frame)) {
                eprintln!("Failed to send position update to sink: {:?}", e);
            }
            Ok(())
        })).map_err(|e| anyhow::anyhow!(e.to_string()))?;
        Ok(())
    }

    pub fn setup_seek_completion_stream(&mut self, sink: StreamSink<i32>) -> Result<()> {
        self.inner.set_seek_completion_callback(Box::new(move |position_ms| {
            if let Err(e) = sink.add(position_ms as i32) {
                eprintln!("Failed to send seek completion to sink: {:?}", e);
            }
            Ok(())
        })).map_err(|e| anyhow::anyhow!(e.to_string()))?;
        Ok(())
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        self.inner.dispose().map_err(|e| e.to_string())
    }
}

// =================== IRONDASH TEXTURE API ===================

/// Create a new video texture using irondash for zero-copy rendering
#[frb(sync)]
pub fn create_video_texture(width: u32, height: u32, engine_handle: i64) -> Result<i64, String> {
    crate::video::irondash_texture::create_video_texture_on_main_thread(width, height, engine_handle)
        .map_err(|e| e.to_string())
}

/// Update video frame data for all irondash textures
#[frb(sync)]
pub fn update_video_frame(frame_data: FrameData) -> bool {
    // Only call the real irondash texture update function
    match crate::video::irondash_texture::update_video_frame(frame_data) {
        Ok(_) => true,
        Err(e) => {
            log::error!("Failed to update video frame: {}", e);
            false
        }
    }
}

/// Get the number of active irondash textures
#[frb(sync)]
pub fn get_texture_count() -> usize {
    crate::video::texture_registry::get_texture_count()
} 

/// Play a basic MP4 video and return irondash texture id
#[frb(sync)]
pub fn play_basic_video(file_path: String, engine_handle: i64) -> Result<i64, String> {
    // Create texture placeholder (1x1)
    let texture_id = crate::video::irondash_texture::create_video_texture_on_main_thread(1, 1, engine_handle)
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
    let texture_id = crate::video::irondash_texture::create_video_texture_on_main_thread(1, 1, engine_handle)
        .map_err(|e| e.to_string())?;

    let handler = FrameHandler::new();
    let vp = VideoPipeline::new_dual(&file_path_left, &file_path_right, Arc::new(Mutex::new(handler)))
        .map_err(|e| e.to_string())?;
    vp.play().map_err(|e| e.to_string())?;

    ACTIVE_VIDEOS.lock().unwrap().push(vp);

    Ok(texture_id)
}

/// Create and load a GES timeline player with timeline data (proper GES implementation)
pub fn create_ges_timeline_player(timeline_data: TimelineData, engine_handle: i64) -> Result<(GESTimelinePlayer, i64), String> {
    // Initialize GStreamer and GES
    gst::init().map_err(|e| format!("Failed to initialize GStreamer: {}", e))?;
    ges::init().map_err(|e| format!("Failed to initialize GES: {}", e))?;
    
    // Create GES timeline player with proper GES integration
    let mut ges_player = GESTimelinePlayer::new();
    
    // Create texture for this specific player
    let texture_id = ges_player.create_texture(engine_handle)?;
    
    // Load the timeline data
    ges_player.load_timeline(timeline_data.clone())?;
    
    log::info!("Created GES timeline player with {} tracks using proper GES Timeline", timeline_data.tracks.len());
    
    Ok((ges_player, texture_id))
}

/// Get video duration in milliseconds using GStreamer
/// This is a reliable way to get video duration without depending on fallback estimations
#[frb(sync)]
pub fn get_video_duration_ms(file_path: String) -> Result<u64, String> {
    // Initialize GStreamer if not already done
    if let Err(e) = gst::init() {
        return Err(format!("Failed to initialize GStreamer: {}", e));
    }
    
    // Check if file exists
    if !std::path::Path::new(&file_path).exists() {
        return Err(format!("Video file not found: {}", file_path));
    }
    
    info!("Getting video duration for: {}", file_path);
    
    // Create a minimal pipeline for duration query
    let pipeline = gst::Pipeline::new();
    
    // Create elements
    let source = gst::ElementFactory::make("filesrc")
        .property("location", &file_path)
        .build()
        .map_err(|e| format!("Failed to create filesrc: {}", e))?;
    
    let decodebin = gst::ElementFactory::make("decodebin")
        .build()
        .map_err(|e| format!("Failed to create decodebin: {}", e))?;
    
    let fakesink = gst::ElementFactory::make("fakesink")
        .build()
        .map_err(|e| format!("Failed to create fakesink: {}", e))?;
    
    // Add elements to pipeline
    pipeline.add_many(&[&source, &decodebin, &fakesink])
        .map_err(|e| format!("Failed to add elements to pipeline: {}", e))?;
    
    // Link source to decodebin
    source.link(&decodebin)
        .map_err(|e| format!("Failed to link source to decodebin: {}", e))?;
    
    // Set up decodebin pad-added callback to link to fakesink
    let fakesink_clone = fakesink.clone();
    decodebin.connect_pad_added(move |_src, src_pad| {
        // Just link the first pad to fakesink (we only need duration, not actual decoding)
        if let Some(sink_pad) = fakesink_clone.static_pad("sink") {
            if !sink_pad.is_linked() {
                let _ = src_pad.link(&sink_pad);
            }
        }
    });
    
    // Set pipeline to PAUSED state to get duration
    pipeline.set_state(gst::State::Paused)
        .map_err(|e| format!("Failed to set pipeline to PAUSED: {:?}", e))?;
    
    // Wait for pipeline to reach PAUSED state
    let timeout = std::time::Duration::from_secs(5);
    let start_time = std::time::Instant::now();
    
    while start_time.elapsed() < timeout {
        let (_, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(100_000_000)));
        if current_state == gst::State::Paused {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    
    // Query duration
    let duration_ms = if let Some(duration) = pipeline.query_duration::<gst::ClockTime>() {
        let duration_ns = duration.nseconds();
        let duration_ms = duration_ns / 1_000_000; // Convert nanoseconds to milliseconds
        info!("Successfully got video duration: {} ms", duration_ms);
        duration_ms
    } else {
        // Clean up pipeline
        pipeline.set_state(gst::State::Null).ok();
        return Err("Could not query video duration".to_string());
    };
    
    // Clean up pipeline
    pipeline.set_state(gst::State::Null)
        .map_err(|e| format!("Failed to clean up pipeline: {:?}", e))?;
    
    Ok(duration_ms)
} 