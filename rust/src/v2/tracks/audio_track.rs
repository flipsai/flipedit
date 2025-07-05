//! Audio track management

use anyhow::{Result, Context};
use gstreamer_editing_services as ges;
use log::{info, debug};

use crate::v2::core::types::{TrackInfo, TrackType};
use crate::v2::clips::AudioClip;

pub struct AudioTrack {
    track_id: String,
    ges_track: ges::Track,
    info: TrackInfo,
}

impl AudioTrack {
    pub fn new(ges_track: ges::Track, name: &str) -> Result<Self> {
        let track_id = format!("audio_track_{}", name);
        
        let info = TrackInfo {
            id: track_id.clone(),
            name: name.to_string(),
            track_type: TrackType::Audio,
            clips: Vec::new(),
        };
        
        Ok(AudioTrack {
            track_id,
            ges_track,
            info,
        })
    }
    
    pub fn add_clip(&mut self, clip: &AudioClip) -> Result<()> {
        // In a real implementation, you would add the clip to the track
        // For now, we just update our internal state
        self.info.clips.push(clip.get_info().clone());
        debug!("Added clip {} to audio track {}", clip.get_info().id, self.track_id);
        Ok(())
    }
    
    pub fn remove_clip(&mut self, clip_id: &str) -> Result<()> {
        // Remove the clip from our internal state
        self.info.clips.retain(|c| c.id != clip_id);
        debug!("Removed clip {} from audio track {}", clip_id, self.track_id);
        Ok(())
    }
    
    pub fn set_name(&mut self, name: &str) -> Result<()> {
        self.info.name = name.to_string();
        debug!("Set audio track {} name to {}", self.track_id, name);
        Ok(())
    }
    
    pub fn set_volume(&mut self, volume: f64) -> Result<()> {
        // In a real implementation, you would set the volume on the GES track
        // For now, we just log it
        debug!("Set audio track {} volume to {}", self.track_id, volume);
        Ok(())
    }
    
    pub fn get_info(&self) -> &TrackInfo {
        &self.info
    }
    
    pub fn get_ges_track(&self) -> &ges::Track {
        &self.ges_track
    }
}