use crate::common::types::FrameData;
use std::sync::{Arc, Mutex};
use log::debug;

#[derive(Clone)]
pub struct FrameHandler {
    pub latest_frame: Arc<Mutex<Option<FrameData>>>,
    pub texture_ptr: Option<i64>,
    pub width: Arc<Mutex<i32>>,
    pub height: Arc<Mutex<i32>>,
    pub frame_rate: Arc<Mutex<f64>>,
}

impl FrameHandler {
    pub fn new() -> Self {
        Self {
            latest_frame: Arc::new(Mutex::new(None)),
            texture_ptr: None,
            width: Arc::new(Mutex::new(0)),
            height: Arc::new(Mutex::new(0)),
            frame_rate: Arc::new(Mutex::new(25.0)),
        }
    }

    pub fn set_texture_ptr(&mut self, ptr: i64) {
        self.texture_ptr = Some(ptr);
    }

    pub fn get_video_dimensions(&self) -> (i32, i32) {
        let width = *self.width.lock().unwrap();
        let height = *self.height.lock().unwrap();
        (width, height)
    }

    pub fn get_latest_frame(&self) -> Option<FrameData> {
        if let Ok(latest_frame) = self.latest_frame.lock() {
            latest_frame.clone()
        } else {
            None
        }
    }

    pub fn store_frame(&self, frame_data: FrameData) {
        if let Ok(mut latest_frame) = self.latest_frame.try_lock() {
            *latest_frame = Some(frame_data);
            debug!("Stored frame data for Dart retrieval");
        }
    }

    pub fn update_dimensions(&self, width: u32, height: u32) {
        if let Ok(mut width_guard) = self.width.try_lock() {
            *width_guard = width as i32;
        }
        if let Ok(mut height_guard) = self.height.try_lock() {
            *height_guard = height as i32;
        }
        debug!("Updated video dimensions: {}x{}", width, height);
    }

    pub fn update_frame_rate(&self, fps: f64) {
        if let Ok(mut frame_rate_guard) = self.frame_rate.try_lock() {
            *frame_rate_guard = fps;
            debug!("Updated frame rate: {} fps", fps);
        }
    }

    pub fn get_frame_rate(&self) -> f64 {
        *self.frame_rate.lock().unwrap()
    }

    pub fn get_current_frame_number(&self, position_seconds: f64) -> u64 {
        let frame_rate = self.get_frame_rate();
        (position_seconds * frame_rate) as u64
    }

    pub fn get_total_frames(&self, duration_seconds: f64) -> u64 {
        let frame_rate = self.get_frame_rate();
        (duration_seconds * frame_rate) as u64
    }
}

impl Default for FrameHandler {
    fn default() -> Self {
        Self::new()
    }
} 