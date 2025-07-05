//! Video clip operations

use anyhow::{Result}; // Removed unused Context
use gstreamer_editing_services as ges;
use gstreamer as gst;
use gstreamer_editing_services::prelude::*; // For TimelineElementExt
use log::{debug}; // Removed unused info

use crate::v2::core::types::ClipInfo;

pub struct VideoClip {
    clip_id: String,
    ges_clip: ges::Clip,
    info: ClipInfo,
}

impl VideoClip {
    pub fn new(ges_clip: ges::Clip, info: ClipInfo) -> Self {
        VideoClip {
            clip_id: info.id.clone(),
            ges_clip,
            info,
        }
    }

    pub fn set_start(&mut self, start_time: u64) -> Result<()> {
        self.ges_clip.set_start(gst::ClockTime::from_nseconds(start_time));
        self.info.start_time = start_time;
        debug!("Set clip {} start time to {}ns", self.clip_id, start_time);
        Ok(())
    }

    pub fn set_duration(&mut self, duration: u64) -> Result<()> {
        self.ges_clip.set_duration(gst::ClockTime::from_nseconds(duration));
        self.info.duration = duration;
        debug!("Set clip {} duration to {}ns", self.clip_id, duration);
        Ok(())
    }

    pub fn set_in_point(&mut self, in_point: u64) -> Result<()> {
        self.ges_clip.set_inpoint(gst::ClockTime::from_nseconds(in_point));
        self.info.in_point = in_point;
        debug!("Set clip {} in-point to {}ns", self.clip_id, in_point);
        Ok(())
    }

    pub fn get_info(&self) -> &ClipInfo {
        &self.info
    }

    pub fn get_ges_clip(&self) -> &ges::Clip {
        &self.ges_clip
    }
}