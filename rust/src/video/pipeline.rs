use gstreamer::prelude::*;
use gstreamer_app::AppSink;
use anyhow::{Result, Error};
use log::{info, debug, error};
use std::sync::{Arc, Mutex};
use crate::video::irondash_texture;
use crate::common::types::FrameData;

pub struct VideoPipeline {
    pipeline: gstreamer::Pipeline,
}

impl VideoPipeline {
    pub fn new(file_path: &str, frame_handler: Arc<Mutex<super::frame_handler::FrameHandler>>) -> Result<Self> {
        info!("Creating simplified GStreamer pipeline for: {}", file_path);
        gstreamer::init()?;

        let pipeline = gstreamer::Pipeline::new();
        let source = gstreamer::ElementFactory::make("filesrc")
            .property("location", file_path)
            .build()?;
        let decodebin = gstreamer::ElementFactory::make("decodebin").build()?;
        let videoconvert = gstreamer::ElementFactory::make("videoconvert").build()?;
        
        let appsink = gstreamer::ElementFactory::make("appsink")
            .build()?
            .downcast::<AppSink>()
            .map_err(|_| Error::msg("Failed to downcast appsink"))?;
        appsink.set_caps(Some(
             &gstreamer::Caps::builder("video/x-raw")
                .field("format", "RGBA")
                .build()
        ));
        
        pipeline.add_many(&[&source, &decodebin, &videoconvert, appsink.upcast_ref()])?;
        source.link(&decodebin)?;
        
        // Link videoconvert and appsink dynamically
        let videoconvert_weak = videoconvert.downgrade();
        let appsink_weak = appsink.downgrade();
        decodebin.connect_pad_added(move |_, src_pad| {
            if let (Some(videoconvert), Some(appsink)) = (videoconvert_weak.upgrade(), appsink_weak.upgrade()) {
                let sink_pad = videoconvert.static_pad("sink").expect("Failed to get sink pad from videoconvert");
                if sink_pad.is_linked() {
                    return;
                }
                if src_pad.link(&sink_pad).is_ok() {
                     if videoconvert.link(&appsink).is_err() {
                        error!("Failed to link videoconvert to appsink");
                     }
                } else {
                    error!("Failed to link decodebin to videoconvert");
                }
            }
        });

        appsink.set_callbacks(
            gstreamer_app::AppSinkCallbacks::builder()
                .new_sample(move |sink| {
                    match Self::on_new_sample(sink, &frame_handler) {
                        Ok(_) => (),
                        Err(e) => error!("Error processing new sample: {}", e),
                    }
                    Ok(gstreamer::FlowSuccess::Ok)
                })
                .build(),
        );

        Ok(Self { pipeline })
    }

    fn on_new_sample(
        sink: &AppSink,
        frame_handler: &Arc<Mutex<super::frame_handler::FrameHandler>>,
    ) -> Result<()> {
        let sample = sink.pull_sample().map_err(|_| Error::msg("Failed to pull sample"))?;
        let buffer = sample.buffer().ok_or_else(|| Error::msg("Failed to get buffer"))?;
        let caps = sample.caps().ok_or_else(|| Error::msg("Failed to get caps"))?;
        let info = gstreamer_video::VideoInfo::from_caps(caps)?;

        let map = buffer.map_readable().map_err(|_| Error::msg("Failed to map buffer"))?;
        
        let frame_data = FrameData {
            data: map.as_slice().to_vec(),
            width: info.width(),
            height: info.height(),
            texture_id: None, // Not used in this simplified path
        };

        // Directly update the irondash texture
        if let Err(e) = irondash_texture::update_video_frame(frame_data) {
             error!("Failed to update irondash video frame: {}", e);
        }

        // Also update the frame handler's dimensions so the UI can get the correct aspect ratio
        let mut handler = frame_handler.lock().unwrap();
        handler.update_dimensions(info.width(), info.height());
        
        debug!("Processed and sent frame to irondash texture. Dimensions: {}x{}", info.width(), info.height());

        Ok(())
    }

    pub fn play(&self) -> Result<()> {
        info!("Setting pipeline to PLAYING");
        self.pipeline.set_state(gstreamer::State::Playing)?;
        Ok(())
    }

    pub fn pause(&self) -> Result<()> {
        info!("Setting pipeline to PAUSED");
        self.pipeline.set_state(gstreamer::State::Paused)?;
                            Ok(())
    }

    pub fn stop(&self) -> Result<()> {
        info!("Setting pipeline to NULL");
        self.pipeline.set_state(gstreamer::State::Null)?;
        Ok(())
    }
} 

// =================== Compatibility wrapper ===================

pub struct PipelineManager {
    pub pipeline: Option<gstreamer::Pipeline>,
    inner: Option<VideoPipeline>,
    // Keep original fields that caller passes but we no longer use
    _frame_handler: Arc<Mutex<super::frame_handler::FrameHandler>>,
}

impl PipelineManager {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        frame_handler: super::frame_handler::FrameHandler,
        _audio_sender: Option<crate::audio_handler::MediaSender>,
        _has_audio: Arc<Mutex<bool>>,
        _frame_callback: Arc<Mutex<Option<crate::video::player::FrameCallback>>>,
        _gl_context: Option<gstreamer_gl::GLContext>,
    ) -> Result<Self, String> {
        Ok(Self {
            pipeline: None,
            inner: None,
            _frame_handler: Arc::new(Mutex::new(frame_handler)),
        })
    }

    pub fn create_pipeline(&mut self, file_path: &str) -> Result<(), String> {
        // Build VideoPipeline lazily
        let vp = VideoPipeline::new(file_path, self._frame_handler.clone())
            .map_err(|e| format!("Failed to create video pipeline: {}", e))?;
        self.pipeline = Some(vp.pipeline.clone());
        self.inner = Some(vp);
        Ok(())
    }

    pub fn play(&self) -> Result<(), String> {
        if let Some(inner) = &self.inner {
            inner.play().map_err(|e| e.to_string())
        } else {
            Err("Pipeline not built".into())
        }
    }

    pub fn pause(&self) -> Result<(), String> {
        if let Some(inner) = &self.inner {
            inner.pause().map_err(|e| e.to_string())
        } else {
            Err("Pipeline not built".into())
        }
    }

    pub fn stop(&self) -> Result<(), String> {
        if let Some(inner) = &self.inner {
            inner.stop().map_err(|e| e.to_string())
        } else {
            Err("Pipeline not built".into())
        }
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        if let Some(inner) = &self.inner {
            inner.stop().map_err(|e| e.to_string())?;
        }
        self.pipeline = None;
        self.inner = None;
        Ok(())
    }
} 