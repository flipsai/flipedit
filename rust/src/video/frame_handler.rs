use crate::common::types::{FrameData, TimelineData, TimelineClip};
use std::sync::{Arc, Mutex};
use log::debug;

#[derive(Clone)]
pub struct FrameHandler {
    pub latest_frame: Arc<Mutex<Option<FrameData>>>,
    pub texture_ptr: Option<i64>,
    pub width: Arc<Mutex<i32>>,
    pub height: Arc<Mutex<i32>>,
    pub frame_rate: Arc<Mutex<f64>>,
    pub timeline_data: Arc<Mutex<Option<TimelineData>>>,
    pub current_time_ms: Arc<Mutex<i32>>,
}

impl FrameHandler {
    pub fn new() -> Self {
        Self {
            latest_frame: Arc::new(Mutex::new(None)),
            texture_ptr: None,
            width: Arc::new(Mutex::new(0)),
            height: Arc::new(Mutex::new(0)),
            frame_rate: Arc::new(Mutex::new(25.0)),
            timeline_data: Arc::new(Mutex::new(None)),
            current_time_ms: Arc::new(Mutex::new(0)),
        }
    }

    pub fn set_texture_ptr(&mut self, ptr: i64) {
        self.texture_ptr = Some(ptr);
    }

    pub fn set_timeline_data(&self, timeline_data: TimelineData) {
        if let Ok(mut timeline_guard) = self.timeline_data.lock() {
            *timeline_guard = Some(timeline_data);
            debug!("Timeline data set in FrameHandler");
        }
    }

    pub fn update_current_time(&self, time_ms: i32) {
        if let Ok(mut current_time_guard) = self.current_time_ms.lock() {
            *current_time_guard = time_ms;
        }
    }

    pub fn get_current_time_ms(&self) -> i32 {
        *self.current_time_ms.lock().unwrap()
    }

    pub fn should_show_frame(&self) -> bool {
        let current_time = self.get_current_time_ms();
        
        if let Ok(timeline_guard) = self.timeline_data.lock() {
            if let Some(timeline) = timeline_guard.as_ref() {
                // Check if current time falls within any clip
                for track in &timeline.tracks {
                    for clip in &track.clips {
                        if current_time >= clip.start_time_on_track_ms && current_time < clip.end_time_on_track_ms {
                            debug!("Time {}ms is within clip: {} ({}ms - {}ms)", 
                                   current_time, clip.source_path, 
                                   clip.start_time_on_track_ms, clip.end_time_on_track_ms);
                            return true;
                        }
                    }
                }
                debug!("Time {}ms is not within any clip - will show empty frame", current_time);
                return false;
            }
        }
        
        // Default to showing frame if no timeline data available
        true
    }

    pub fn find_active_clip_at_current_time(&self) -> Option<TimelineClip> {
        let current_time = self.get_current_time_ms();
        
        if let Ok(timeline_guard) = self.timeline_data.lock() {
            if let Some(timeline) = timeline_guard.as_ref() {
                for track in &timeline.tracks {
                    for clip in &track.clips {
                        if current_time >= clip.start_time_on_track_ms && current_time < clip.end_time_on_track_ms {
                            return Some(clip.clone());
                        }
                    }
                }
            }
        }
        None
    }

    pub fn get_video_dimensions(&self) -> (i32, i32) {
        let width = *self.width.lock().unwrap();
        let height = *self.height.lock().unwrap();
        (width, height)
    }

    pub fn get_latest_frame(&self) -> Option<FrameData> {
        if !self.should_show_frame() {
            // Return empty/black frame when not within any clip
            let (width, height) = self.get_video_dimensions();
            if width > 0 && height > 0 {
                let black_frame_size = (width * height * 4) as usize; // RGBA
                let black_data = vec![0u8; black_frame_size];
                debug!("Returning black frame ({}x{}) - no active clip", width, height);
                return Some(FrameData {
                    data: black_data,
                    width: width as u32,
                    height: height as u32,
                });
            }
            return None;
        }

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