//! Video track management

use anyhow::{Result, Context};
use gstreamer_editing_services as ges;
use log::{info, debug};

use crate::v2::core::types::{TrackInfo, TrackType};
use crate::v2::clips::VideoClip;

pub struct VideoTrack {
    track_id: String,
    ges_track: ges::Track,
    info: TrackInfo,
}

impl VideoTrack {
    pub fn new(ges_track: ges::Track, name: &str) -> Result<Self> {
        let track_id = format!("video_track_{}", name);
        
        let info = TrackInfo {
            id: track_id.clone(),
            name: name.to_string(),
            track_type: TrackType::Video,
            clips: Vec::new(),
        };
        
        Ok(VideoTrack {
            track_id,
            ges_track,
            info,
        })
    }
    
    // Note: Clips are added to ges::Layers, not directly to ges::Tracks.
    // A ges::Track typically represents a category (e.g., all video) within the timeline
    // rather than directly holding clips. Clip management is done at the Layer or Project level.
    // pub fn add_clip(&mut self, clip: &VideoClip) -> Result<()> { ... }
    // pub fn remove_clip(&mut self, clip_id: &str) -> Result<()> { ... }

    // Placeholder for track name removed as per current focus.
    // Real implementation would interact with ges_track properties.
    // pub fn set_name(&mut self, name: &str) -> Result<()> {
    //     self.info.name = name.to_string();
    //     // self.ges_track.set_property("name", name)... // Example
    //     debug!("Set video track {} name to {}", self.track_id, name);
    //     Ok(())
    // }
    
    pub fn get_info(&self) -> &TrackInfo {
        &self.info
    }
    
    pub fn get_ges_track(&self) -> &ges::Track {
        &self.ges_track
    }
}