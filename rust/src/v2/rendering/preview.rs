//! Preview rendering for Flutter integration

use anyhow::{Result, Context};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gstreamer::prelude::{ElementExt, ElementExtManual, Cast};
use gstreamer_editing_services::prelude::GESPipelineExt;
use log::info;

use crate::v2::core::Timeline;

pub struct PreviewRenderer {
    pipeline: gst::Pipeline,
}

impl PreviewRenderer {
    pub fn new(timeline: &Timeline) -> Result<Self> {
        let pipeline = ges::Pipeline::new();

        // Set the timeline on the pipeline
        pipeline.set_timeline(timeline.get_timeline())
            .context("Failed to set timeline on pipeline")?;

        // Convert to gst::Pipeline for easier handling
        let gst_pipeline = pipeline.upcast::<gst::Pipeline>();

        info!("Created preview renderer");

        Ok(PreviewRenderer {
            pipeline: gst_pipeline,
        })
    }

    pub fn setup_texture_output(&mut self, engine_handle: i64, width: u32, height: u32) -> Result<i64> {
        // For now, return a dummy texture ID since the texture API has changed significantly
        // This will allow the basic pipeline to work without texture rendering
        let dummy_texture_id = 12345i64;

        info!("Setup texture output: {}x{}, ID: {:?}", width, height, dummy_texture_id);

        Ok(dummy_texture_id)
    }

    pub fn play(&self) -> Result<()> {
        self.pipeline.set_state(gst::State::Playing)
            .context("Failed to start playback")?;

        info!("Started preview playback");
        Ok(())
    }

    pub fn pause(&self) -> Result<()> {
        self.pipeline.set_state(gst::State::Paused)
            .context("Failed to pause playback")?;

        info!("Paused preview playback");
        Ok(())
    }

    pub fn stop(&self) -> Result<()> {
        self.pipeline.set_state(gst::State::Null)
            .context("Failed to stop playback")?;

        info!("Stopped preview playback");
        Ok(())
    }

    pub fn seek(&self, position: u64) -> Result<()> {
        self.pipeline.seek_simple(
            gst::SeekFlags::FLUSH | gst::SeekFlags::KEY_UNIT,
            gst::ClockTime::from_nseconds(position),
        ).context("Failed to seek")?;

        info!("Seeked to position: {}ns", position);
        Ok(())
    }
}
