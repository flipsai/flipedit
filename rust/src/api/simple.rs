use flutter_rust_bridge::frb;
pub use crate::api::bridge::*;
use crate::video::player::VideoPlayer as InternalVideoPlayer;
pub use crate::common::types::FrameData;
use crate::utils::testing;

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
    pub fn get_current_frame_number(&self) -> u64 {
        self.inner.get_current_frame_number()
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

    pub fn test_audio(&mut self) -> Result<(), String> {
        self.inner.test_audio()
    }

    pub fn test_pipeline(&self, file_path: String) -> Result<(), String> {
        testing::test_pipeline(file_path)
    }
} 