//! Main rendering engine

use anyhow::{Result, Context};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gstreamer::glib; // For glib::Continue
use gstreamer::bus::BusWatchGuard; // Correct path
use gstreamer::prelude::*; // For ElementExt, GstBinExt, GstBinExtManual, ObjectExt, PadExt, Cast, ElementExtManual
use gstreamer_editing_services::prelude::*; // For GESPipelineExt
use log::{info, debug, warn, error};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};


use crate::v2::core::Timeline;

#[derive(Clone)] // Added Clone for RenderProgress
pub struct RenderProgress {
    pub position: u64,
    pub duration: u64,
    pub percent: f64,
}

pub struct Renderer {
    pipeline: gst::Pipeline, // This is the ges::Pipeline upcasted
    is_rendering: Arc<AtomicBool>,
    progress: Arc<Mutex<RenderProgress>>,
    // We need to keep the bus watch ID to remove it later if necessary,
    // though dropping the pipeline should also clean up watches.
    bus_watch_id: Option<BusWatchGuard>, // Corrected path
}

impl Renderer {
    pub fn new(timeline: &Timeline) -> Result<Self> {
        let ges_pipeline = ges::Pipeline::new();
        
        ges_pipeline.set_timeline(timeline.get_timeline()) // GESPipelineExt
            .context("Failed to set timeline on pipeline")?;

        let gst_pipeline = ges_pipeline.upcast::<gst::Pipeline>(); // Cast
        
        let progress = RenderProgress {
            position: 0,
            duration: timeline.get_duration(), // Assuming get_duration on Timeline is up-to-date
            percent: 0.0,
        };

        info!("Created renderer");

        Ok(Renderer {
            pipeline: gst_pipeline,
            is_rendering: Arc::new(AtomicBool::new(false)),
            progress: Arc::new(Mutex::new(progress)),
            bus_watch_id: None,
        })
    }

    pub fn render_to_file(&mut self, output_path: &Path, format: &str) -> Result<()> {
        if self.is_rendering.load(Ordering::SeqCst) {
            return Err(anyhow::anyhow!("Rendering is already in progress"));
        }

        let filesink = gst::ElementFactory::make("filesink")
            .name("file_sink")
            .property("location", output_path.to_str().ok_or_else(|| anyhow::anyhow!("Invalid output path"))?)
            .build()
            .context("Failed to create file sink")?;
        
        let (video_encoder_name, muxer_name) = match format.to_lowercase().as_str() {
            "mp4" => ("x264enc", "mp4mux"),
            "webm" => ("vp8enc", "webmmux"),
            _ => return Err(anyhow::anyhow!("Unsupported format: {}", format)),
        };

        let video_encoder = gst::ElementFactory::make(video_encoder_name)
            .name("video_encoder")
            .build()
            .with_context(|| format!("Failed to create video encoder: {}", video_encoder_name))?;
        
        let muxer = gst::ElementFactory::make(muxer_name)
            .name("muxer")
            .build()
            .with_context(|| format!("Failed to create muxer: {}", muxer_name))?;

        // Create a new bin for the sink elements: videoconvert ! encoder ! muxer ! filesink
        // The ges::Pipeline's video-sink property will be set to this bin.
        let render_sink_bin = gst::Bin::with_name("render_sink_bin");

        let videoconvert = gst::ElementFactory::make("videoconvert")
            .name("render_videoconvert")
            .build()
            .context("Failed to create videoconvert for rendering")?;

        // Note: Audio encoding would need a similar chain (audioconvert, audioencoder)
        // and then both video_encoder and audio_encoder would link to the muxer.
        // For simplicity, this example focuses on video. If audio is present in the
        // timeline, the muxer might complain or produce a file with no audio track
        // unless an audio path is also provided to it.

        render_sink_bin.add_many(&[&videoconvert, &video_encoder, &muxer, &filesink])
            .context("Failed to add elements to render_sink_bin")?;

        // Link: videoconvert -> video_encoder -> muxer -> filesink
        gst::Element::link_many(&[&videoconvert, &video_encoder, &muxer, &filesink])
            .context("Failed to link elements in render_sink_bin")?;
        
        // Create a ghost pad for the render_sink_bin to accept input
        let sink_bin_sink_pad = videoconvert.static_pad("sink") // PadExt
            .ok_or_else(|| anyhow::anyhow!("Videoconvert should have a sink pad"))?;
        let ghost_pad = gst::GhostPad::new_from_target(Some("sink"), &sink_bin_sink_pad) // Corrected constructor
            .context("Failed to create ghost pad for render_sink_bin")?; // Anyhow context for Result
        render_sink_bin.add_pad(&ghost_pad) // GstBinExt
            .context("Failed to add ghost pad to render_sink_bin")?;

        // Set this new bin as the video sink for the ges_pipeline (self.pipeline)
        self.pipeline.set_property("video-sink", &render_sink_bin.upcast::<gst::Element>()) // ObjectExt, Cast
            .context("Failed to set video-sink property on pipeline")?;
        
        // TODO: Add audio sink configuration if audio is to be rendered.
        // Example: self.pipeline.set_property("audio-sink", &audio_render_bin)?;

        // Set up progress tracking
        let progress_clone = Arc::clone(&self.progress);
        // Initialize progress for this render pass
        {
            let mut p = progress_clone.lock().unwrap();
            p.position = 0;
            // p.duration should be set from timeline when Renderer is created or before render
            p.duration = self.pipeline.query_duration::<gst::ClockTime>().map_or(0, |d| d.nseconds());
            p.percent = 0.0;
        }
        let pipeline_weak = self.pipeline.downgrade(); // Use weak ref in bus watch

        let bus = self.pipeline.bus().ok_or_else(|| anyhow::anyhow!("Failed to get pipeline bus"))?;
        
        let bus_watch_guard = bus.add_watch(move |_, msg| {
            let pipeline = match pipeline_weak.upgrade() {
                Some(p) => p,
                None => return glib::Continue(false), // Pipeline is gone // Corrected to use glib::Continue
            };

            match msg.view() {
                gst::MessageView::Eos(_) => {
                    info!("Rendering: End of stream reached.");
                    let mut p_lock = progress_clone.lock().unwrap();
                    if p_lock.duration > 0 {
                        p_lock.position = p_lock.duration;
                        p_lock.percent = 100.0;
                    }
                    return glib::Continue(false);
                },
                gst::MessageView::Error(err) => {
                    error!("Rendering Error: {}, Debug: {:?}", err.error(), err.debug());
                    return glib::Continue(false);
                },
                gst::MessageView::StateChanged(state_changed) => {
                    if state_changed.src().map_or(false, |s| s == pipeline.upcast_ref::<gst::Element>()) { // Cast
                        debug!("Renderer pipeline state changed from {:?} to {:?} (pending {:?})",
                               state_changed.old(), state_changed.current(), state_changed.pending());
                    }
                    return glib::Continue(true);
                },
                gst::MessageView::Element(element_msg) => {
                    if let Some(s) = element_msg.structure() { // Check if structure exists
                        if s.name() == "ges-progress" {
                             if let (Ok(percent), Ok(duration), Ok(position)) = (
                                 s.get::<f64>("percent"),
                                 s.get::<u64>("duration"),
                                 s.get::<u64>("position")
                             ) {
                                let mut p_lock = progress_clone.lock().unwrap();
                                p_lock.percent = percent;
                                p_lock.duration = duration;
                                p_lock.position = position;
                                debug!("Render progress: {:.2}% (pos: {}ns / dur: {}ns)", percent, position, duration);
                             }
                        }
                    }
                    return glib::Continue(true);
                }
                _ => return glib::Continue(true),
            }
        }).context("Failed to add bus watch for rendering")?;
        self.bus_watch_id = Some(bus_watch_guard);
        
        self.is_rendering.store(true, Ordering::SeqCst);
        self.pipeline.set_state(gst::State::Playing) // ElementExt
            .context("Failed to start rendering pipeline")?;
        
        info!("Started rendering to file: {:?} with format {}", output_path, format);
        
        Ok(())
    }
    
    pub fn cancel_rendering(&mut self) -> Result<()> { // Takes &mut self now
        if self.is_rendering.load(Ordering::SeqCst) {
            info!("Attempting to cancel rendering...");
            self.pipeline.set_state(gst::State::Null) // ElementExt
                .context("Failed to set pipeline to Null state for cancellation")?;
            
            self.is_rendering.store(false, Ordering::SeqCst);
            if let Some(guard) = self.bus_watch_id.take() {
                guard.remove();
            }
            info!("Rendering canceled or stopped.");
        } else {
            info!("No rendering in progress to cancel.");
        }
        Ok(())
    }
    
    pub fn get_progress(&self) -> RenderProgress {
        self.progress.lock().unwrap().clone()
    }
}

impl Drop for Renderer {
    fn drop(&mut self) {
        if self.is_rendering.load(Ordering::SeqCst) {
            warn!("Renderer dropped while rendering was in progress. Attempting to stop.");
            // Release the bus watch first
            if let Some(guard) = self.bus_watch_id.take() {
                guard.remove();
            }
            if let Err(e) = self.pipeline.set_state(gst::State::Null) {
                error!("Failed to set pipeline to NULL in Renderer drop: {:?}", e);
            }
        } else {
             if let Some(guard) = self.bus_watch_id.take() {
                guard.remove();
            }
        }
        info!("Renderer dropped.");
    }
}