//! Audio clip operations

use anyhow::{Result, Context};
use gstreamer_editing_services as ges;
use gstreamer as gst;
use log::{info, debug};

use crate::v2::core::types::ClipInfo;

pub struct AudioClip {
    clip_id: String,
    ges_clip: ges::Clip,
    info: ClipInfo,
}

impl AudioClip {
    pub fn new(ges_clip: ges::Clip, info: ClipInfo) -> Self {
        AudioClip {
            clip_id: info.id.clone(),
            ges_clip,
            info,
        }
    }

    pub fn set_start(&mut self, start_time: u64) -> Result<()> {
        self.ges_clip.set_start(gst::ClockTime::from_nseconds(start_time));
        self.info.start_time = start_time;
        debug!("Set audio clip {} start time to {}ns", self.clip_id, start_time);
        Ok(())
    }

    pub fn set_duration(&mut self, duration: u64) -> Result<()> {
        self.ges_clip.set_duration(gst::ClockTime::from_nseconds(duration));
        self.info.duration = duration;
        debug!("Set audio clip {} duration to {}ns", self.clip_id, duration);
        Ok(())
    }

    pub fn set_in_point(&mut self, in_point: u64) -> Result<()> {
        self.ges_clip.set_inpoint(gst::ClockTime::from_nseconds(in_point));
        self.info.in_point = in_point;
        debug!("Set audio clip {} in-point to {}ns", self.clip_id, in_point);
        Ok(())
    }

    pub fn set_volume(&mut self, volume: f64) -> Result<()> {
        // Find the audio element in the clip
        if let Some(element) = self.ges_clip.find_track_element(None, ges::TrackType::AUDIO) {
            element.set_child_property("volume", &volume)
                .context("Failed to set audio volume")?;
            debug!("Set audio clip {} volume to {}", self.clip_id, volume);
        }
        Ok(())
    }

    pub fn get_info(&self) -> &ClipInfo {
        &self.info
    }

    pub fn get_ges_clip(&self) -> &ges::Clip {
        &self.ges_clip
    }
}