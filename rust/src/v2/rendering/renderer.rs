//! Main rendering engine

use anyhow::{Result, Context};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use log::{info, debug, warn, error};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};

use crate::v2::core::Timeline;

pub struct RenderProgress {
    pub position: u64,
    pub duration: u64,
    pub percent: f64,
}

pub struct Renderer {
    pipeline: gst::Pipeline,
    is_rendering: Arc<AtomicBool>,
    progress: Arc<Mutex<RenderProgress>>,
}

impl Renderer {
    pub fn new(timeline: &Timeline) -> Result<Self> {
        let pipeline = ges::Pipeline::new();
        
        // Set the timeline on the pipeline
        pipeline.set_timeline(timeline.get_timeline())
            .context("Failed to set timeline on pipeline")?;

        // Convert to gst::Pipeline for easier handling
        let gst_pipeline = pipeline.upcast::<gst::Pipeline>();
        
        let progress = RenderProgress {
            position: 0,
            duration: timeline.get_duration(),
            percent: 0.0,
        };

        info!("Created renderer");

        Ok(Renderer {
            pipeline: gst_pipeline,
            is_rendering: Arc::new(AtomicBool::new(false)),
            progress: Arc::new(Mutex::new(progress)),
        })
    }

    pub fn render_to_file(&self, output_path: &Path, format: &str) -> Result<()> {
        // Set up the pipeline for rendering to file
        let sink = gst::ElementFactory::make("filesink")
            .name("file_sink")
            .property("location", output_path.to_str().unwrap())
            .build()
            .context("Failed to create file sink")?;
        
        // Create encoder based on format
        let encoder = match format.to_lowercase().as_str() {
            "mp4" => gst::ElementFactory::make("x264enc")
                .build()
                .context("Failed to create H.264 encoder")?,
            "webm" => gst::ElementFactory::make("vp8enc")
                .build()
                .context("Failed to create VP8 encoder")?,
            _ => return Err(anyhow::anyhow!("Unsupported format: {}", format)),
        };
        
        // Create muxer based on format
        let muxer = match format.to_lowercase().as_str() {
            "mp4" => gst::ElementFactory::make("mp4mux")
                .build()
                .context("Failed to create MP4 muxer")?,
            "webm" => gst::ElementFactory::make("webmmux")
                .build()
                .context("Failed to create WebM muxer")?,
            _ => return Err(anyhow::anyhow!("Unsupported format: {}", format)),
        };
        
        // Add elements to pipeline
        self.pipeline.add_many(&[&encoder, &muxer, &sink])
            .context("Failed to add elements to pipeline")?;
        
        // Link elements
        gst::Element::link_many(&[&encoder, &muxer, &sink])
            .context("Failed to link elements")?;
        
        // Set up progress tracking
        let progress = self.progress.clone();
        let duration = self.progress.lock().unwrap().duration;
        
        let bus = self.pipeline.bus().unwrap();
        let _bus_watch = bus.add_watch(move |_, msg| {
            match msg.view() {
                gst::MessageView::Eos(_) => {
                    info!("End of stream reached");
                    let mut p = progress.lock().unwrap();
                    p.position = duration;
                    p.percent = 100.0;
                    return glib::Continue(false);
                },
                gst::MessageView::Error(err) => {
                    error!("Error: {:?}", err.error());
                    return glib::Continue(false);
                },
                gst::MessageView::StateChanged(state) => {
                    if state.src().map(|s| s == &self.pipeline).unwrap_or(false) {
                        debug!("Pipeline state changed to: {:?}", state.current());
                    }
                    return glib::Continue(true);
                },
                _ => return glib::Continue(true),
            }
        }).context("Failed to add bus watch")?;
        
        // Start rendering
        self.is_rendering.store(true, Ordering::SeqCst);
        self.pipeline.set_state(gst::State::Playing)
            .context("Failed to start rendering")?;
        
        info!("Started rendering to file: {:?}", output_path);
        
        Ok(())
    }
    
    pub fn cancel_rendering(&self) -> Result<()> {
        if self.is_rendering.load(Ordering::SeqCst) {
            self.pipeline.set_state(gst::State::Null)
                .context("Failed to stop rendering")?;
            
            self.is_rendering.store(false, Ordering::SeqCst);
            info!("Rendering canceled");
        }
        
        Ok(())
    }
    
    pub fn get_progress(&self) -> RenderProgress {
        self.progress.lock().unwrap().clone()
    }
}

impl Drop for Renderer {
    fn drop(&mut self) {
        let _ = self.pipeline.set_state(gst::State::Null);
    }
}