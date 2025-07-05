//! Preview rendering for Flutter integration

use anyhow::{Result, Context};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gstreamer_gl as gst_gl;
use gstreamer::prelude::{ElementExt, ElementExtManual, Cast};
use gstreamer_editing_services::prelude::GESPipelineExt;
use irondash_texture::{Texture, BoxedPixelData};
use log::{info, error};

use crate::v2::core::Timeline;

pub struct PreviewRenderer {
    pipeline: gst::Pipeline,
    texture: Option<Texture>,
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
            texture: None,
        })
    }

    pub fn setup_texture_output(&mut self, width: u32, height: u32) -> Result<TextureId> {
        // Create texture for Flutter
        let texture = Texture::new_with_size(width, height)
            .context("Failed to create texture")?;

        let texture_id = texture.id();

        // Set up the pipeline to render to the texture
        // This is a simplified version - in practice you'd need to set up
        // the GL context and configure the pipeline properly

        self.texture = Some(texture);

        info!("Setup texture output: {}x{}, ID: {:?}", width, height, texture_id);

        Ok(texture_id)
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
