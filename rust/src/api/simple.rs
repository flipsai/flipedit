use flutter_rust_bridge::frb;
pub use crate::api::bridge::*;
use crate::video::player::VideoPlayer as InternalVideoPlayer;
use crate::video::timeline_player::TimelinePlayer as InternalTimelinePlayer;
pub use crate::common::types::{FrameData, TimelineData, TimelineClip, TimelineTrack, TextureFrame};
use crate::utils::testing;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use anyhow::Result;
use crate::frb_generated::StreamSink;

// Position update callback type
pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) + Send + Sync>;

#[frb(sync)]
pub fn greet(name: String) -> String {
    crate::api::bridge::greet(name)
}

pub struct VideoPlayer {
    inner: InternalVideoPlayer,
    position_callback: Arc<Mutex<Option<PositionUpdateCallback>>>,
    position_thread_running: Arc<Mutex<bool>>,
}

impl VideoPlayer {
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: InternalVideoPlayer::new(),
            position_callback: Arc::new(Mutex::new(None)),
            position_thread_running: Arc::new(Mutex::new(false)),
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
        let result = self.inner.play();
        if result.is_ok() {
            self.start_position_reporting();
        }
        result
    }

    pub fn pause(&mut self) -> Result<(), String> {
        let result = self.inner.pause();
        self.stop_position_reporting();
        result
    }

    pub fn stop(&mut self) -> Result<(), String> {
        let result = self.inner.stop();
        self.stop_position_reporting();
        result
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

    /// Start position reporting thread
    fn start_position_reporting(&self) {
        let is_running = self.position_thread_running.clone();
        // Only start if not already running
        if *is_running.lock().unwrap() {
            return;
        }

        *is_running.lock().unwrap() = true;
        
        let callback_arc = Arc::clone(&self.position_callback);
        let thread_running_arc = Arc::clone(&is_running);
        
        // We need a way to get position from the inner player in the thread
        // For now, let's use a simpler approach and just expose this as a method
        // that Flutter can call periodically
    }

    /// Stop position reporting thread
    fn stop_position_reporting(&mut self) {
        *self.position_thread_running.lock().unwrap() = false;
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
        self.stop_position_reporting();
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