use crate::common::types::{FrameData, TimelineData, TimelineClip, FrameBufferPool, TextureFrame};
use std::sync::{Arc, Mutex, atomic::{AtomicU64, Ordering}};
use log::debug;

#[derive(Clone)]
pub struct FrameHandler {
    pub latest_frame: Arc<Mutex<Option<FrameData>>>, // Keep for backwards compatibility
    pub latest_texture_id: Arc<AtomicU64>, // Current GPU texture ID
    pub texture_ptr: Option<i64>, // Flutter texture pointer
    pub width: Arc<Mutex<i32>>,
    pub height: Arc<Mutex<i32>>,
    pub frame_rate: Arc<Mutex<f64>>,
    pub timeline_data: Arc<Mutex<Option<TimelineData>>>,
    pub current_time_ms: Arc<Mutex<i32>>,
    pub buffer_pool: Arc<Mutex<FrameBufferPool>>, // Keep for CPU fallback
}

impl FrameHandler {
    pub fn new() -> Self {
        Self {
            latest_frame: Arc::new(Mutex::new(None)),
            latest_texture_id: Arc::new(AtomicU64::new(0)),
            texture_ptr: None,
            width: Arc::new(Mutex::new(0)),
            height: Arc::new(Mutex::new(0)),
            frame_rate: Arc::new(Mutex::new(25.0)),
            timeline_data: Arc::new(Mutex::new(None)),
            current_time_ms: Arc::new(Mutex::new(0)),
            buffer_pool: Arc::new(Mutex::new(FrameBufferPool::default())),
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
                let mut black_data = if let Ok(pool) = self.buffer_pool.lock() {
                    pool.get_buffer()
                } else {
                    vec![0u8; (width * height * 4) as usize]
                };
                
                let required_size = (width * height * 4) as usize;
                if black_data.len() != required_size {
                    black_data.resize(required_size, 0);
                }
                
                // Fill with black pixels
                black_data.fill(0);
                
                debug!("Returning black frame ({}x{}) - no active clip", width, height);
                return Some(FrameData {
                    data: black_data,
                    width: width as u32,
                    height: height as u32,
                    texture_id: None,
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
            // Return old frame buffer to pool if it exists
            if let Some(old_frame) = latest_frame.replace(frame_data) {
                self.return_buffer_to_pool(old_frame.data);
            }
            debug!("Stored frame data for Dart retrieval");
        }
    }
    
    /// Update the current texture ID for GPU-based rendering
    pub fn update_texture_id(&self, texture_id: u64) {
        self.latest_texture_id.store(texture_id, Ordering::Relaxed);
        debug!("Updated texture ID: {}", texture_id);
    }
    
    /// Get the latest texture ID for GPU-based rendering
    pub fn get_latest_texture_id(&self) -> u64 {
        self.latest_texture_id.load(Ordering::Relaxed)
    }
    
    /// Get texture frame data for GPU-based rendering
    pub fn get_texture_frame(&self) -> Option<TextureFrame> {
        let texture_id = self.get_latest_texture_id();
        if texture_id > 0 {
            let (width, height) = self.get_video_dimensions();
            Some(TextureFrame {
                texture_id,
                width: width as u32,
                height: height as u32,
                timestamp: None,
            })
        } else {
            None
        }
    }
    

    pub fn update_dimensions(&self, width: u32, height: u32) {
        let mut changed = false;
        
        if let Ok(mut width_guard) = self.width.try_lock() {
            if *width_guard != width as i32 {
                *width_guard = width as i32;
                changed = true;
            }
        }
        if let Ok(mut height_guard) = self.height.try_lock() {
            if *height_guard != height as i32 {
                *height_guard = height as i32;
                changed = true;
            }
        }
        
        if changed {
            // Update buffer pool for new dimensions
            if let Ok(mut pool) = self.buffer_pool.lock() {
                pool.resize_for_dimensions(width, height);
            }
            debug!("Updated video dimensions: {}x{}", width, height);
        }
    }

    pub fn get_buffer_from_pool(&self) -> Vec<u8> {
        if let Ok(pool) = self.buffer_pool.lock() {
            pool.get_buffer()
        } else {
            // Fallback to default 1080p buffer
            vec![0u8; 1920 * 1080 * 4]
        }
    }

    pub fn return_buffer_to_pool(&self, buffer: Vec<u8>) {
        if let Ok(pool) = self.buffer_pool.lock() {
            pool.return_buffer(buffer);
        }
    }

    pub fn update_frame_rate(&self, fps: f64) {
        if let Ok(mut frame_rate_guard) = self.frame_rate.try_lock() {
            if (*frame_rate_guard - fps).abs() > 0.01 {
                *frame_rate_guard = fps;
                debug!("Updated frame rate: {} fps", fps);
            }
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