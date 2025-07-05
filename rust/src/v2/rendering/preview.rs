//! Preview rendering for Flutter integration

use anyhow::{Result, Context};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gstreamer_app::AppSink;
use gstreamer_app::prelude::*; // Added for AppSinkBuilderExt etc.
use gstreamer::prelude::*;
use gstreamer_editing_services::prelude::*;
use irondash_texture::{Texture, TextureId, BoxedPixelData}; // Added BoxedPixelData
use log::{info, error, debug};
use std::sync::Arc;

use crate::v2::core::Timeline;

pub struct PreviewRenderer {
    pipeline: gst::Pipeline,
    _texture_id: TextureId,
    appsink: AppSink,
}

impl PreviewRenderer {
    // Note: The caller (e.g., flutter_bridge) will need to manage Texture creation and provide an Arc<Texture>.
    // This constructor assumes it receives the TextureId and the Arc<Texture> it should update.
    pub fn new(timeline: &Timeline, texture_id: TextureId, texture: Arc<Texture<BoxedPixelData>>) -> Result<Self> { // Specified BoxedPixelData
        let ges_pipeline = ges::Pipeline::new();

        ges_pipeline.set_timeline(timeline.get_timeline())
            .context("Failed to set timeline on pipeline")?;

        let appsink_caps = gst::Caps::builder("video/x-raw")
            .field("format", "RGBA")
            .build();
        let appsink = AppSink::builder().name("preview_appsink")
            .emit_signals(true) // AppSinkBuilderExt for emit_signals
            .caps(&appsink_caps)
            .build();

        let weak_texture = Arc::downgrade(&texture);
        appsink.set_callbacks(
            gstreamer_app::AppSinkCallbacks::builder()
                .new_sample(move |appsink_instance| {
                    let sample = appsink_instance.pull_sample().map_err(|_| {
                        error!("AppSink: Failed to pull sample");
                        gst::FlowError::Eos
                    })?;

                    let buffer = sample.buffer().ok_or_else(|| {
                        error!("AppSink: Sample has no buffer");
                        gst::FlowError::Error
                    })?;

                    let map = buffer.map_readable().map_err(|_| {
                        error!("AppSink: Failed to map buffer readable");
                        gst::FlowError::Error
                    })?;

                    let caps = sample.caps().ok_or_else(|| {
                        error!("AppSink: Sample has no caps");
                        gst::FlowError::Error
                    })?;

                    let s = caps.structure(0).ok_or_else(|| {
                        error!("AppSink: Caps has no structure");
                        gst::FlowError::Error
                    })?;

                    let width = s.get::<i32>("width").map_err(|_| {
                        error!("AppSink: Failed to get width from caps");
                        gst::FlowError::Error
                    })? as u32;
                    let height = s.get::<i32>("height").map_err(|_| {
                        error!("AppSink: Failed to get height from caps");
                        gst::FlowError::Error
                    })? as u32;

                    if let Some(upgraded_texture) = weak_texture.upgrade() {
                        // TODO: Ensure data format from GStreamer (e.g. via videoconvert) matches RGBA.
                        // The AppSink caps request RGBA, but upstream elements might not provide it without conversion.
                        // A videoconvert element might be needed in the ges_pipeline's video processing chain
                        // before the point where video-sink is connected, or the bin set as video-sink.
                        match upgraded_texture.update_with_data(map.as_slice(), width, height) {
                            Ok(_) => { /* debug!("Texture updated {}x{}", width, height); */ }
                            Err(e) => {
                                error!("AppSink: Failed to update texture: {:?}", e);
                                return Err(gst::FlowError::Error);
                            }
                        }
                    } else {
                        debug!("AppSink: Texture for preview appsink dropped");
                        return Err(gst::FlowError::Eos);
                    }
                    Ok(gst::FlowSuccess::Ok) // Changed to FlowSuccess::Ok
                })
                .build()
        );

        // It's often necessary to have a videoconvert element before the appsink
        // to ensure the format is RGBA as expected by the texture.
        // We create a bin for this: videoconvert ! capsfilter ! appsink_element
        let videoconvert = gst::ElementFactory::make("videoconvert")
            .name("preview_videoconvert")
            .build()
            .context("Failed to create videoconvert for preview")?;

        let capsfilter = gst::ElementFactory::make("capsfilter")
            .name("preview_capsfilter")
            .property("caps", &appsink_caps)
            .build()
            .context("Failed to create capsfilter for preview")?;

        let sink_bin = gst::Bin::with_name("preview_sink_bin");
        sink_bin.add_many(&[&videoconvert, &capsfilter, &appsink.clone().upcast()]) // GstBinExtManual for add_many
            .context("Failed to add elements to preview sink_bin")?;

        gst::Element::link_many(&[&videoconvert, &capsfilter, &appsink.clone().upcast()])
            .context("Failed to link elements in preview sink_bin")?;

        let sink_pad = videoconvert.static_pad("sink").expect("Videoconvert should have a sink pad");
        let ghost_pad = gst::GhostPad::with_target(Some(&sink_pad), Some("sink")) // Use with_target(target, name)
            .map_err(|e| anyhow::anyhow!("Failed to create ghost pad for preview_sink_bin: {}", e))?;
        sink_bin.add_pad(&ghost_pad) // GstBinExt for add_pad
            .context("Failed to add ghost pad to preview_sink_bin")?;

        // Set the custom bin as the video-sink for the ges_pipeline
        ges_pipeline.set_property("video-sink", &sink_bin.upcast::<gst::Element>()); // ObjectExt for set_property. Returns (), panics on error.
        // No .context() needed here. If property setting fails, it will panic.

        let gst_pipeline_final = ges_pipeline.upcast::<gst::Pipeline>(); // Cast
        info!("Created preview renderer with AppSink and videoconvert to RGBA");

        Ok(PreviewRenderer {
            pipeline: gst_pipeline_final,
            _texture_id: texture_id,
            appsink,
        })
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
