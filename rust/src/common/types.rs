use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::collections::VecDeque;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrameData {
    pub data: Vec<u8>, // Keep for backwards compatibility with CPU-based frames
    pub width: u32,
    pub height: u32,
    pub texture_id: Option<u64>, // GPU texture ID for direct rendering
}

// Frame buffer pool for reusing allocations (still used for CPU fallback)
pub struct FrameBufferPool {
    buffers: Arc<Mutex<VecDeque<Vec<u8>>>>,
    max_capacity: usize,
    buffer_size: usize,
}

// Texture ID data for GPU-centric rendering
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextureFrame {
    pub texture_id: u64,
    pub width: u32,
    pub height: u32,
    pub timestamp: Option<u64>, // Optional timestamp in nanoseconds
}

impl FrameBufferPool {
    pub fn new(buffer_size: usize, initial_capacity: usize) -> Self {
        let mut buffers = VecDeque::with_capacity(initial_capacity);
        
        // Pre-allocate buffers
        for _ in 0..initial_capacity {
            buffers.push_back(vec![0u8; buffer_size]);
        }
        
        Self {
            buffers: Arc::new(Mutex::new(buffers)),
            max_capacity: initial_capacity.max(16), // Increased buffer pool size
            buffer_size,
        }
    }

    pub fn get_buffer(&self) -> Vec<u8> {
        if let Ok(mut buffers) = self.buffers.lock() {
            if let Some(mut buffer) = buffers.pop_front() {
                // Resize buffer if needed
                if buffer.len() != self.buffer_size {
                    buffer.resize(self.buffer_size, 0);
                }
                return buffer;
            }
        }
        
        // Create new buffer if pool is empty
        vec![0u8; self.buffer_size]
    }

    pub fn return_buffer(&self, buffer: Vec<u8>) {
        if let Ok(mut buffers) = self.buffers.lock() {
            if buffers.len() < self.max_capacity {
                buffers.push_back(buffer);
            }
            // If pool is full, buffer will be dropped
        }
    }

    pub fn resize_for_dimensions(&mut self, width: u32, height: u32) {
        let new_size = (width * height * 4) as usize; // BGRA format
        if new_size != self.buffer_size {
            self.buffer_size = new_size;
            // Clear existing buffers as they're wrong size
            if let Ok(mut buffers) = self.buffers.lock() {
                buffers.clear();
                // Pre-allocate new buffers
                for _ in 0..4 {
                    buffers.push_back(vec![0u8; new_size]);
                }
            }
        }
    }
}

impl Default for FrameBufferPool {
    fn default() -> Self {
        // Default for 1080p BGRA with larger pool
        Self::new(1920 * 1080 * 4, 8)
    }
}

// Simple pipeline pool for reusing temporary pipelines
pub struct TempPipelinePool {
    available_pipelines: Arc<Mutex<VecDeque<String>>>, // Store pipeline IDs or paths
    max_capacity: usize,
}

impl TempPipelinePool {
    pub fn new(max_capacity: usize) -> Self {
        Self {
            available_pipelines: Arc::new(Mutex::new(VecDeque::with_capacity(max_capacity))),
            max_capacity,
        }
    }

    pub fn get_pipeline_id(&self) -> Option<String> {
        if let Ok(mut pipelines) = self.available_pipelines.lock() {
            pipelines.pop_front()
        } else {
            None
        }
    }

    pub fn return_pipeline_id(&self, pipeline_id: String) {
        if let Ok(mut pipelines) = self.available_pipelines.lock() {
            if pipelines.len() < self.max_capacity {
                pipelines.push_back(pipeline_id);
            }
        }
    }
}

impl Default for TempPipelinePool {
    fn default() -> Self {
        Self::new(3) // Keep max 3 temporary pipelines
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineClip {
    pub id: Option<i32>,
    pub track_id: i32,
    pub source_path: String,
    pub start_time_on_track_ms: i32,
    pub end_time_on_track_ms: i32,
    pub start_time_in_source_ms: i32,
    pub end_time_in_source_ms: i32,
    // Preview transformation properties for GES composition
    pub preview_position_x: f64,
    pub preview_position_y: f64,
    pub preview_width: f64,
    pub preview_height: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineTrack {
    pub id: i32,
    pub name: String,
    pub clips: Vec<TimelineClip>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineData {
    pub tracks: Vec<TimelineTrack>,
} 