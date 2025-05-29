use flutter_rust_bridge::frb;
pub use crate::api::bridge::*;
use crate::video::player::VideoPlayer as InternalVideoPlayer;
use crate::video::timeline_composer::{TimelineComposer as InternalTimelineComposer, TimelineClipData};
use crate::video::frame_handler::FrameHandler;
pub use crate::common::types::FrameData;
use crate::utils::testing;
use log::{debug, error};

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

// Simple timeline composer functions using raw pointers
#[frb(sync)]
pub fn timeline_composer_create() -> i64 {
    let frame_handler = FrameHandler::new();
    let composer = InternalTimelineComposer::new(frame_handler);
    let boxed = Box::new(composer);
    Box::into_raw(boxed) as i64
}

#[frb(sync)]
pub fn timeline_composer_set_texture_ptr(handle: i64, ptr: i64) {
    unsafe {
        let composer = &mut *(handle as *mut InternalTimelineComposer);
        composer.set_texture_ptr(ptr);
    }
}

pub fn timeline_composer_update_timeline(handle: i64, clips: Vec<TimelineClipData>) -> Result<(), String> {
    debug!("timeline_composer_update_timeline called with handle: {}, clips: {}", handle, clips.len());
    unsafe {
        let composer = &mut *(handle as *mut InternalTimelineComposer);
        let result = composer.update_timeline(clips);
        if let Err(ref e) = result {
            error!("timeline_composer_update_timeline failed: {}", e);
        } else {
            debug!("timeline_composer_update_timeline succeeded");
        }
        result
    }
}

pub fn timeline_composer_play(handle: i64) -> Result<(), String> {
    debug!("timeline_composer_play called with handle: {}", handle);
    unsafe {
        let composer = &mut *(handle as *mut InternalTimelineComposer);
        let result = composer.play();
        if let Err(ref e) = result {
            error!("timeline_composer_play failed: {}", e);
        }
        result
    }
}

pub fn timeline_composer_pause(handle: i64) -> Result<(), String> {
    debug!("timeline_composer_pause called with handle: {}", handle);
    unsafe {
        let composer = &mut *(handle as *mut InternalTimelineComposer);
        let result = composer.pause();
        if let Err(ref e) = result {
            error!("timeline_composer_pause failed: {}", e);
        }
        result
    }
}

pub fn timeline_composer_seek(handle: i64, position_ms: i64) -> Result<(), String> {
    unsafe {
        let composer = &mut *(handle as *mut InternalTimelineComposer);
        composer.seek(position_ms)
    }
}

#[frb(sync)]
pub fn timeline_composer_get_position(handle: i64) -> i64 {
    unsafe {
        let composer = &*(handle as *const InternalTimelineComposer);
        composer.get_position()
    }
}

#[frb(sync)]
pub fn timeline_composer_get_duration(handle: i64) -> i64 {
    unsafe {
        let composer = &*(handle as *const InternalTimelineComposer);
        composer.get_duration()
    }
}

#[frb(sync)]
pub fn timeline_composer_is_playing(handle: i64) -> bool {
    unsafe {
        let composer = &*(handle as *const InternalTimelineComposer);
        composer.is_playing()
    }
}

#[frb(sync)]
pub fn timeline_composer_get_latest_frame(handle: i64) -> Option<FrameData> {
    unsafe {
        let composer = &*(handle as *const InternalTimelineComposer);
        composer.get_latest_frame()
    }
}

pub fn timeline_composer_dispose(handle: i64) -> Result<(), String> {
    unsafe {
        let mut composer = Box::from_raw(handle as *mut InternalTimelineComposer);
        composer.dispose();
        Ok(())
    }
} 