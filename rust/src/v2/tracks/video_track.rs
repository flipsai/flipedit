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
    
    pub fn add_clip(&mut self, clip: &VideoClip) -> Result<()> {
        // In a real implementation, you would add the clip to the track
        // For now, we just update our internal state
        self.info.clips.push(clip.get_info().clone());
        debug!("Added clip {} to video track {}", clip.get_info().id, self.track_id);
        Ok(())
    }
    
    pub fn remove_clip(&mut self, clip_id: &str) -> Result<()> {
        // Remove the clip from our internal state
        self.info.clips.retain(|c| c.id != clip_id);
        debug!("Removed clip {} from video track {}", clip_id, self.track_id);
        Ok(())
    }
    
    pub fn set_name(&mut self, name: &str) -> Result<()> {
        self.info.name = name.to_string();
        debug!("Set video track {} name to {}", self.track_id, name);
        Ok(())
    }
    
    pub fn get_info(&self) -> &TrackInfo {
        &self.info
    }
    
    pub fn get_ges_track(&self) -> &ges::Track {
        &self.ges_track
    }
}