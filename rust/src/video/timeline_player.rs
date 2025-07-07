use anyhow::{anyhow, Result};
use gstreamer as gst;
use gstreamer_app as gst_app;
use gst::prelude::*;
use log::{debug, error, info, warn};
use std::sync::{Arc, Mutex};

use crate::common::types::{FrameData, TimelineData, TimelineClip};

pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) -> Result<()> + Send + Sync>;

/// A timeline player that uses a GStreamer pipeline with a compositor,
/// similar to the architectural approach of Pitivi. It renders the output
/// to a texture that can be displayed in Flutter via irondash.
pub struct TimelinePlayer {
    pipeline: Option<gst::Pipeline>,
    texture_id: Option<i64>,
    is_playing: Arc<Mutex<bool>>,
    current_position_ms: Arc<Mutex<u64>>,
    duration_ms: Arc<Mutex<Option<u64>>>,
    position_callback: Arc<Mutex<Option<PositionUpdateCallback>>>,
    position_timer_id: Arc<Mutex<Option<gst::glib::SourceId>>>,
}

impl TimelinePlayer {
    pub fn new() -> Result<Self> {
        gst::init().map_err(|e| anyhow!("Failed to initialize GStreamer: {}", e))?;
        info!("GStreamer initialized successfully.");
        Ok(Self {
            pipeline: None,
            texture_id: None,
            is_playing: Arc::new(Mutex::new(false)),
            current_position_ms: Arc::new(Mutex::new(0)),
            duration_ms: Arc::new(Mutex::new(None)),
            position_callback: Arc::new(Mutex::new(None)),
            position_timer_id: Arc::new(Mutex::new(None)),
        })
    }

    pub fn set_texture_ptr(&mut self, ptr: i64) {
        self.texture_id = Some(ptr);
        info!("Texture pointer set: {}", ptr);
    }

    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<()> {
        info!(
            "Loading timeline with {} tracks",
            timeline_data.tracks.len()
        );
        self.stop_pipeline()?;

        let duration_ms = timeline_data
            .tracks
            .iter()
            .flat_map(|t| &t.clips)
            .map(|c| c.end_time_on_track_ms as u64)
            .max()
            .unwrap_or(0)
            .max(30000);
        *self.duration_ms.lock().unwrap() = Some(duration_ms);

        let pipeline = self.create_pipeline(&timeline_data)?;
        self.pipeline = Some(pipeline);

        info!("Timeline loaded successfully, duration: {}ms", duration_ms);
        Ok(())
    }

    fn create_pipeline(&self, timeline_data: &TimelineData) -> Result<gst::Pipeline> {
        let pipeline = gst::Pipeline::new();

        let compositor = gst::ElementFactory::make("compositor")
            .name("video_compositor")
            .build()?;
        let audiomixer = gst::ElementFactory::make("audiomixer")
            .name("audio_mixer")
            .build()?;

        let video_sink = self.create_texture_video_sink()?;
        let audio_sink = gst::ElementFactory::make("autoaudiosink").build()?;

        pipeline.add_many(&[&compositor, &audiomixer, &video_sink, &audio_sink])?;

        let videoconvert = gst::ElementFactory::make("videoconvert").build()?;
        let audioconvert = gst::ElementFactory::make("audioconvert").build()?;
        let audioresample = gst::ElementFactory::make("audioresample").build()?;

        pipeline.add_many(&[&videoconvert, &audioconvert, &audioresample])?;

        gst::Element::link_many(&[&compositor, &videoconvert, &video_sink])?;
        gst::Element::link_many(&[&audiomixer, &audioconvert, &audioresample, &audio_sink])?;

        for (i, clip) in timeline_data
            .tracks
            .iter()
            .flat_map(|t| &t.clips)
            .enumerate()
        {
            self.add_clip_to_pipeline(&pipeline, &compositor, &audiomixer, clip, i)?;
        }

        self.setup_position_monitoring(&pipeline);
        Ok(pipeline)
    }

    fn add_clip_to_pipeline(
        &self,
        pipeline: &gst::Pipeline,
        compositor: &gst::Element,
        audiomixer: &gst::Element,
        clip: &TimelineClip,
        index: usize,
    ) -> Result<()> {
        let src = gst::ElementFactory::make("filesrc")
            .name(format!("src_{}", index))
            .property("location", &clip.source_path)
            .build()?;
        let decodebin = gst::ElementFactory::make("decodebin")
            .name(format!("decode_{}", index))
            .build()?;

        pipeline.add_many(&[&src, &decodebin])?;
        src.link(&decodebin)?;

        let compositor_clone = compositor.clone();
        let audiomixer_clone = audiomixer.clone();
        let pipeline_clone = pipeline.clone();
        let clip_start_ns = (clip.start_time_on_track_ms as u64) * 1_000_000;
        let clip_duration_ns =
            ((clip.end_time_on_track_ms - clip.start_time_on_track_ms) as u64) * 1_000_000;
        let inpoint_ns = (clip.start_time_in_source_ms as u64) * 1_000_000;

        decodebin.connect_pad_added(move |_, src_pad| {
            info!(
                "Pad added for clip {}: {:?}",
                index,
                src_pad.name()
            );
            let is_video = src_pad.name().starts_with("video");
            let is_audio = src_pad.name().starts_with("audio");

            if is_video {
                if let Some(compositor_sink_pad) = compositor_clone.request_pad_simple("sink_%u") {
                    let identity = gst::ElementFactory::make("identity").build().unwrap();
                    pipeline_clone.add(&identity).unwrap();
                    identity.link(&compositor_clone).unwrap();
                    let identity_sink = identity.static_pad("sink").unwrap();
                    src_pad.link(&identity_sink).unwrap();
                } else {
                    error!("Failed to get compositor sink pad");
                }
            }

            if is_audio {
                if let Some(audiomixer_sink_pad) = audiomixer_clone.request_pad_simple("sink_%u") {
                    if let Err(e) = src_pad.link(&audiomixer_sink_pad) {
                        error!("Failed to link audio pad to mixer: {}", e);
                    }
                } else {
                    error!("Failed to get audiomixer sink pad");
                }
            }
        });

        Ok(())
    }

    fn create_texture_video_sink(&self) -> Result<gst::Element> {
        let video_sink = gst::ElementFactory::make("appsink")
            .name("texture_video_sink")
            .build()?;

        video_sink.set_property("emit-signals", true);
        video_sink.set_property("sync", true);
        video_sink.set_property("drop", true);
        video_sink.set_property("max-buffers", 1u32);

        let caps = gst::Caps::builder("video/x-raw")
            .field("format", "RGBA")
            .field("width", 1920i32)
            .field("height", 1080i32)
            .build();
        video_sink.set_property("caps", &caps);

        if let Some(texture_id) = self.texture_id {
            let appsink = video_sink
                .clone()
                .dynamic_cast::<gst_app::AppSink>()
                .unwrap();
            appsink.set_callbacks(
                gst_app::AppSinkCallbacks::builder()
                    .new_sample(move |sink| {
                        match Self::handle_video_sample(sink, texture_id) {
                            Ok(_) => Ok(gst::FlowSuccess::Ok),
                            Err(_) => Err(gst::FlowError::Error),
                        }
                    })
                    .build(),
            );
        }

        Ok(video_sink)
    }

    fn handle_video_sample(
        appsink: &gst_app::AppSink,
        texture_id: i64,
    ) -> Result<(), gst::FlowError> {
        let sample = appsink.pull_sample().map_err(|_| gst::FlowError::Eos)?;
        let buffer = sample.buffer().ok_or(gst::FlowError::Error)?;
        let map = buffer.map_readable().map_err(|_| gst::FlowError::Error)?;

        let caps = sample.caps().ok_or(gst::FlowError::Error)?;
        let s = caps.structure(0).ok_or(gst::FlowError::Error)?;
        let width = s.get::<i32>("width").unwrap() as u32;
        let height = s.get::<i32>("height").unwrap() as u32;

        let frame_data = FrameData {
            data: map.as_slice().to_vec(),
            width,
            height,
            texture_id: Some(texture_id as u64),
        };

        if let Err(e) = crate::api::simple::update_video_frame(frame_data) {
            debug!("Failed to update video frame: {}", e);
        }

        Ok(())
    }

    fn setup_position_monitoring(&self, pipeline: &gst::Pipeline) {
        let position_callback = Arc::clone(&self.position_callback);
        let current_position_ms = Arc::clone(&self.current_position_ms);
        let is_playing = Arc::clone(&self.is_playing);
        let pipeline_weak = pipeline.downgrade();

        let timer_id = gst::glib::timeout_add(std::time::Duration::from_millis(33), move || {
            if let Some(pipeline) = pipeline_weak.upgrade() {
                if *is_playing.lock().unwrap() {
                    if let Some(pos) = pipeline.query_position::<gst::ClockTime>() {
                        let pos_ms = pos.mseconds();
                        *current_position_ms.lock().unwrap() = pos_ms;
                        if let Some(ref cb) = *position_callback.lock().unwrap() {
                            let _ = cb(pos_ms as f64 / 1000.0, (pos_ms / 33) as u64);
                        }
                    }
                }
                gst::glib::ControlFlow::Continue
            } else {
                gst::glib::ControlFlow::Break
            }
        });
        *self.position_timer_id.lock().unwrap() = Some(timer_id);
    }

    pub fn play(&self) -> Result<()> {
        info!("Setting pipeline to PLAYING");
        self.pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("Pipeline not loaded"))?
            .set_state(gst::State::Playing)?;
        *self.is_playing.lock().unwrap() = true;
        Ok(())
    }

    pub fn pause(&self) -> Result<()> {
        info!("Setting pipeline to PAUSED");
        self.pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("Pipeline not loaded"))?
            .set_state(gst::State::Paused)?;
        *self.is_playing.lock().unwrap() = false;
        Ok(())
    }

    fn stop_pipeline(&self) -> Result<()> {
        if let Some(pipeline) = &self.pipeline {
            info!("Setting pipeline to NULL");
            pipeline.set_state(gst::State::Null)?;
            *self.is_playing.lock().unwrap() = false;
            *self.current_position_ms.lock().unwrap() = 0;
        }
        if let Some(timer_id) = self.position_timer_id.lock().unwrap().take() {
            timer_id.remove();
        }
        Ok(())
    }

    pub fn seek(&self, position_ms: u64) -> Result<()> {
        info!("Seeking to {}ms", position_ms);
        let Some(pipeline) = self.pipeline.as_ref() else {
            return Err(anyhow!("Pipeline not loaded"));
        };
        pipeline.seek_simple(
            gst::SeekFlags::FLUSH | gst::SeekFlags::KEY_UNIT,
            gst::ClockTime::from_mseconds(position_ms),
        )?;
        *self.current_position_ms.lock().unwrap() = position_ms;
        Ok(())
    }
    
    pub fn set_position_update_callback(&mut self, callback: PositionUpdateCallback) -> Result<()> {
        let mut guard = self.position_callback.lock().unwrap();
        *guard = Some(callback);
        Ok(())
    }

    pub fn get_duration_ms(&self) -> Option<u64> {
        *self.duration_ms.lock().unwrap()
    }
    
    pub fn get_current_position_ms(&self) -> u64 {
        *self.current_position_ms.lock().unwrap()
    }

    pub fn is_playing(&self) -> bool {
        *self.is_playing.lock().unwrap()
    }
    
    pub fn dispose(&mut self) -> Result<()> {
        self.stop_pipeline()
    }
}

impl Default for TimelinePlayer {
    fn default() -> Self {
        Self::new().expect("Failed to create default TimelinePlayer")
    }
} 