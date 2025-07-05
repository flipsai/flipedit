//! Project state management

use anyhow::Result;
use std::collections::HashMap;
use log::info;
use gstreamer_editing_services::prelude::*; // For LayerExt, TimelineElementExt
use gstreamer::prelude::Cast; // For downcast
use gstreamer_editing_services as ges; // To use ges::Clip type directly

use super::timeline::Timeline;
use super::types::{ClipInfo, TrackInfo, TimelineState};

pub struct Project {
    timeline: Timeline,
    pub clips: HashMap<String, ClipInfo>, // Made public for bridge access
    tracks: HashMap<String, TrackInfo>, // Keep private for now
    state: TimelineState,
}

// SAFETY: Project is designed to be used from a single thread at a time
unsafe impl Send for Project {}
unsafe impl Sync for Project {}

impl Project {
    pub fn new() -> Result<Self> {
        // Ensure GStreamer is initialized when a project is created.
        // Timeline::new() already calls init_gstreamer.
        let timeline = Timeline::new()?;
        
        let state = TimelineState {
            position: 0,
            duration: 0,
            is_playing: false,
        };

        info!("Created new project");

        Ok(Project {
            timeline,
            clips: HashMap::new(),
            tracks: HashMap::new(),
            state,
        })
    }

    pub fn add_video_file(&mut self, file_path: &str) -> Result<String> {
        let uri = format!("file://{}", file_path);
        
        // For now, add the entire video duration
        // In a real implementation, you'd get this from the file
        let duration = 10_000_000_000; // 10 seconds in nanoseconds
        
        let clip_id = self.timeline.add_video_clip(&uri, 0, duration)?;
        
        let clip_info = ClipInfo {
            id: clip_id.clone(),
            name: file_path.split('/').last().unwrap_or("unknown").to_string(),
            start_time: 0,
            duration,
            in_point: 0,
            clip_type: super::types::ClipType::Video,
        };

        self.clips.insert(clip_id.clone(), clip_info);
        self.state.duration = self.timeline.get_duration();

        info!("Added video file: {}", file_path);
        
        Ok(clip_id)
    }

    pub fn get_timeline(&self) -> &Timeline {
        &self.timeline
    }

    pub fn get_state(&self) -> &TimelineState {
        &self.state
    }

    pub fn get_clips(&self) -> &HashMap<String, ClipInfo> {
        &self.clips
    }

    // Helper to find a ges::Clip in the project's main layer by its ID (name)
    // Made public for bridge access.
    pub fn find_ges_clip_by_id(&self, clip_id_to_find: &str) -> Option<ges::Clip> { // Now ges::Clip can be used
        // Assuming clips are on the first layer, which is typical for simple setups.
        // self.timeline.layer is the ges::Layer object.
        for element in self.timeline.get_layer().clips() { // LayerExt provides .clips()
            if let Some(name) = element.name() { // TimelineElementExt provides .name()
                if name == clip_id_to_find {
                    // Attempt to downcast TimelineElement to Clip
                    // This returns a new GObject reference (cloned). Operations on it affect the original.
                    return element.downcast::<ges::Clip>().ok(); // ges::Clip can be used
                }
            }
        }
        None
    }
}