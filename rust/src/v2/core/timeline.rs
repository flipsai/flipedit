//! Timeline management using GStreamer Editing Services

use anyhow::{Result, Context};
use gstreamer_editing_services as ges;
use gstreamer as gst;
use log::{info, warn, error};

use super::types::{VideoInfo, TimelineState};

pub struct Timeline {
    ges_timeline: ges::Timeline,
    layer: ges::Layer,
}

impl Timeline {
    pub fn new() -> Result<Self> {
        // Initialize GStreamer and GES
        gst::init().context("Failed to initialize GStreamer")?;
        ges::init().context("Failed to initialize GES")?;

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

        let clip_id = format!("clip_{}", clip.start().nseconds());
        info!("Added video clip: {} at {}ns for {}ns", uri, start, duration);

        Ok(clip_id)
    }

    pub fn get_timeline(&self) -> &ges::Timeline {
        &self.ges_timeline
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