//! Project state management

use anyhow::Result;
use std::collections::HashMap;
use log::info;

use super::timeline::Timeline;
use super::types::{ClipInfo, TrackInfo, TimelineState};

pub struct Project {
    timeline: Timeline,
    clips: HashMap<String, ClipInfo>,
    tracks: HashMap<String, TrackInfo>,
    state: TimelineState,
}

impl Project {
    pub fn new() -> Result<Self> {
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
}