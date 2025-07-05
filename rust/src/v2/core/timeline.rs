//! Timeline management using GStreamer Editing Services

use anyhow::{Result, Context}; // Context might be unused if all .context calls are removed/changed
use gstreamer_editing_services as ges;
use gstreamer as gst;
use gstreamer::prelude::Cast;
use gstreamer_editing_services::prelude::*; // For TimelineExt, TimelineElementExt, LayerExt
use rand::Rng; // Changed for more specific import
use log::{info};

use super::types::{VideoInfo};
use crate::v2::utils;

pub struct Timeline {
    ges_timeline: ges::Timeline,
    layer: ges::Layer,
}

// Note: crate::v2::utils is already imported below where it's used.
// No, it's better to have 'use' at the top level of the module.
// use crate::v2::utils; // This was a bit misplaced, should be with other uses if not scoped.

impl Timeline {
    pub fn new() -> Result<Self> {
        utils::gst_utils::init_gstreamer().context("Failed to initialize GStreamer/GES in Timeline::new")?;

        // Create timeline and layer
        let ges_timeline = ges::Timeline::new_audio_video();
        let layer = ges_timeline.append_layer();

        info!("Created new timeline with audio/video layer");

        Ok(Timeline {
            ges_timeline,
            layer,
        })
    }

    pub fn add_video_clip(&mut self, uri: &str, start: u64, duration: u64) -> Result<String> {
        let clip = ges::UriClip::new(uri)
            .context("Failed to create URI clip")?;
        
        clip.set_start(gst::ClockTime::from_nseconds(start));
        clip.set_duration(gst::ClockTime::from_nseconds(duration));

        self.layer.add_clip(&clip)
            .context("Failed to add clip to layer")?;

        // Generate a unique ID for the clip. Using a more robust UUID is recommended for production.
        // For now, using timestamp and a random number part.
        let random_part: u32 = rand::thread_rng().gen();
        let clip_id = format!("clip_{}_{}", clip.start().nseconds(), random_part);

        // Set the name of the ges::TimelineElement to this clip_id so we can find it later.
        // ges::Clip inherits from ges::TimelineElement.
        clip.upcast_ref::<ges::TimelineElement>().set_name(Some(&clip_id));

        info!("Added video clip: {} (ID: {}) at {}ns for {}ns", uri, clip_id, start, duration);

        Ok(clip_id)
    }

    pub fn get_timeline(&self) -> &ges::Timeline {
        &self.ges_timeline
    }

    pub fn get_layer(&self) -> &ges::Layer { // Added getter for the layer
        &self.layer
    }

    pub fn get_duration(&self) -> u64 {
        self.ges_timeline.duration().nseconds()
    }

    pub fn get_video_info(&self) -> Option<VideoInfo> {
        // This would typically be extracted from the first video clip
        // For now, return a default
        Some(VideoInfo {
            width: 1920,
            height: 1080,
            fps: 30.0,
            duration: self.get_duration(),
        })
    }
}