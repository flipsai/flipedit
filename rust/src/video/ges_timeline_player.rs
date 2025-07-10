use anyhow::{anyhow, Result};
use gstreamer as gst;
use gstreamer_app as gst_app;
use gstreamer_video as gst_video;
use gstreamer_editing_services as ges;
use gst::prelude::*;
use ges::prelude::*;
use log::{debug, info, warn};
use std::sync::{Arc, Mutex};

use crate::common::types::{FrameData, TimelineData, TimelineClip};
use crate::video::irondash_texture::create_player_texture;
use crate::ges::{create_timeline, with_timeline, destroy_timeline, TimelineHandle};

pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) -> Result<()> + Send + Sync>;
pub type SeekCompletionCallback = Box<dyn Fn(u64) -> Result<()> + Send + Sync>;

/// A proper GES Timeline Player that uses GESPipeline for gap handling
pub struct GESTimelinePlayer {
    pipeline: Option<ges::Pipeline>,
    timeline_handle: Option<TimelineHandle>,
    texture_id: Option<i64>,
    texture_update_fn: Option<Box<dyn Fn(FrameData) + Send + Sync>>,
    is_playing: Arc<Mutex<bool>>,
    current_position_ms: Arc<Mutex<u64>>,
    duration_ms: Arc<Mutex<Option<u64>>>,
    position_callback: Arc<Mutex<Option<PositionUpdateCallback>>>,
    seek_completion_callback: Arc<Mutex<Option<SeekCompletionCallback>>>,
    position_timer_id: Arc<Mutex<Option<gst::glib::SourceId>>>,
    flutter_engine_handle: Option<i64>,
}

// SAFETY: We manually implement Send and Sync for GESTimelinePlayer
// This is necessary because GStreamer objects are not Send/Sync by default,
// but we ensure that all GStreamer operations happen on the main thread.
unsafe impl Send for GESTimelinePlayer {}
unsafe impl Sync for GESTimelinePlayer {}

impl GESTimelinePlayer {
    /// Handle video sample from appsink and update texture (similar to DirectPipelinePlayer)
    fn handle_video_sample(appsink: &gst_app::AppSink, texture_id: i64) -> Result<()> {
        use crate::video::irondash_texture::update_video_frame;
        
        let sample = appsink.pull_sample()
            .map_err(|_| anyhow!("Failed to pull sample from appsink"))?;
        
        let buffer = sample.buffer()
            .ok_or_else(|| anyhow!("No buffer in sample"))?;
        
        let caps = sample.caps()
            .ok_or_else(|| anyhow!("No caps in sample"))?;
        
        let video_info = gst_video::VideoInfo::from_caps(&caps)
            .map_err(|_| anyhow!("Failed to parse video info from caps"))?;
        
        let width = video_info.width();
        let height = video_info.height();
        
        let map = buffer.map_readable()
            .map_err(|_| anyhow!("Failed to map buffer"))?;
        
        let data = map.as_slice().to_vec();
        
        // Create frame data and update through irondash texture system
        let frame_data = FrameData {
            data,
            width,
            height,
            texture_id: Some(texture_id as u64),
        };
        
        // Update texture through irondash global registry
        update_video_frame(frame_data)
            .map_err(|e| anyhow!("Failed to update video frame: {}", e))?;
        
        Ok(())
    }

    pub fn new() -> Result<Self> {
        // Initialize GStreamer and GES
        gst::init().map_err(|e| anyhow!("Failed to initialize GStreamer: {}", e))?;
        ges::init().map_err(|e| anyhow!("Failed to initialize GES: {}", e))?;
        
        info!("GStreamer and GES initialized successfully for timeline player.");
        Ok(Self {
            pipeline: None,
            timeline_handle: None,
            texture_id: None,
            texture_update_fn: None,
            is_playing: Arc::new(Mutex::new(false)),
            current_position_ms: Arc::new(Mutex::new(0)),
            duration_ms: Arc::new(Mutex::new(None)),
            position_callback: Arc::new(Mutex::new(None)),
            seek_completion_callback: Arc::new(Mutex::new(None)),
            position_timer_id: Arc::new(Mutex::new(None)),
            flutter_engine_handle: None,
        })
    }

    /// Create texture with proper GL context sharing for this player
    pub fn create_texture(&mut self, engine_handle: i64) -> Result<i64> {
        self.flutter_engine_handle = Some(engine_handle);
        
        let (texture_id, update_fn) = create_player_texture(1920, 1080, engine_handle)?;
        self.texture_id = Some(texture_id);
        self.texture_update_fn = Some(update_fn);
        
        info!("Created GL-enabled texture with ID: {}", texture_id);
        Ok(texture_id)
    }

    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<()> {
        info!("Loading timeline with {} tracks using GES Pipeline", timeline_data.tracks.len());
        self.stop_pipeline()?;

        // Create GES timeline
        let timeline_handle = create_timeline()?;
        
        // Add clips to timeline using GES
        with_timeline(timeline_handle, |timeline_wrapper| {
            for track in &timeline_data.tracks {
                for clip_data in &track.clips {
                    let timeline_clip = TimelineClip {
                        id: clip_data.id,
                        track_id: clip_data.track_id,
                        source_path: clip_data.source_path.clone(),
                        start_time_on_track_ms: clip_data.start_time_on_track_ms,
                        end_time_on_track_ms: clip_data.end_time_on_track_ms,
                        start_time_in_source_ms: clip_data.start_time_in_source_ms,
                        end_time_in_source_ms: clip_data.end_time_in_source_ms,
                        preview_position_x: clip_data.preview_position_x,
                        preview_position_y: clip_data.preview_position_y,
                        preview_width: clip_data.preview_width,
                        preview_height: clip_data.preview_height,
                    };
                    
                    if let Err(e) = timeline_wrapper.add_clip(&timeline_clip) {
                        warn!("Failed to add clip to GES timeline: {}", e);
                    } else {
                        info!("Successfully added clip: {}", timeline_clip.source_path);
                    }
                }
            }
            Ok(())
        })?;

        // Get timeline duration from GES
        let duration_ms = with_timeline(timeline_handle, |timeline_wrapper| {
            Ok(timeline_wrapper.get_duration_ms())
        })?;
        
        info!("GES Timeline duration: {}ms", duration_ms);
        *self.duration_ms.lock().unwrap() = Some(duration_ms);

        // Create GES Pipeline and set the timeline
        let ges_pipeline = ges::Pipeline::new();
        
        // Get the GES timeline from our wrapper
        let ges_timeline = with_timeline(timeline_handle, |timeline_wrapper| {
            Ok(timeline_wrapper.timeline.clone())
        })?;
        
        // Set timeline on pipeline - this is critical for video flow
        info!("Setting GES timeline on pipeline");
        if let Err(e) = ges_pipeline.set_timeline(&ges_timeline) {
            return Err(anyhow!("Failed to set timeline on GES pipeline: {}", e));
        }
        info!("✅ GES timeline set on pipeline successfully");

        // Set pipeline to preview mode for gap handling - this must be done BEFORE setting video sink
        info!("Setting GES pipeline to preview mode");
        if let Err(e) = ges_pipeline.set_mode(ges::PipelineFlags::AUDIO_PREVIEW | ges::PipelineFlags::VIDEO_PREVIEW) {
            return Err(anyhow!("Failed to set GES pipeline to preview mode: {}", e));
        }
        info!("✅ GES pipeline set to preview mode successfully");

        // Set up video sink to render to our texture - this must be done AFTER setting preview mode
        info!("Setting up video sink for texture rendering");
        self.setup_video_sink(&ges_pipeline)?;
        info!("✅ Video sink setup completed");

        // Setup message handling for GES pipeline
        self.setup_ges_message_handling(&ges_pipeline)?;
        
        // Wait for asset discovery by setting to PAUSED and waiting for ASYNC_DONE
        info!("Setting GES pipeline to PAUSED state for asset discovery");
        match ges_pipeline.set_state(gst::State::Paused) {
            Ok(gst::StateChangeSuccess::Success) => {
                info!("✅ GES pipeline immediately transitioned to PAUSED - assets ready");
            },
            Ok(gst::StateChangeSuccess::Async) => {
                info!("⏳ GES pipeline transitioning to PAUSED asynchronously - waiting for asset discovery");
                
                // Wait for ASYNC_DONE message indicating asset discovery completion
                let timeout = gst::ClockTime::from_seconds(10); // 10 second timeout for asset discovery
                match ges_pipeline.state(Some(timeout)) {
                    (Ok(gst::State::Paused), _, _) => {
                        info!("✅ GES pipeline asset discovery completed successfully");
                    },
                    (state, _, _) => {
                        warn!("GES pipeline asset discovery timeout or failed. State: {:?}", state);
                        // Continue anyway - might still work
                    }
                }
            },
            Ok(gst::StateChangeSuccess::NoPreroll) => {
                info!("✅ GES pipeline transitioned to PAUSED (no preroll)");
            },
            Err(e) => {
                warn!("Failed to set GES pipeline to PAUSED: {}", e);
                // Continue anyway - might still work
            }
        }
        
        self.pipeline = Some(ges_pipeline);
        self.timeline_handle = Some(timeline_handle);

        info!("🎬 GES Pipeline loaded successfully with proper gap handling, duration: {}ms", duration_ms);
        Ok(())
    }

    fn setup_ges_message_handling(&self, pipeline: &ges::Pipeline) -> Result<()> {
        let bus = pipeline
            .bus()
            .ok_or_else(|| anyhow!("Failed to get pipeline bus"))?;

        let is_playing = Arc::clone(&self.is_playing);
        let current_position_ms = Arc::clone(&self.current_position_ms);
        let seek_completion_callback = Arc::clone(&self.seek_completion_callback);

        let _bus_watch = bus.add_watch(move |_bus, message| {
            match message.type_() {
                gst::MessageType::Eos => {
                    info!("GES Pipeline reached End of Stream");
                    *is_playing.lock().unwrap() = false;
                },
                gst::MessageType::Error => {
                    let error_msg = message.view();
                    if let gst::MessageView::Error(error) = error_msg {
                        let err = error.error();
                        let debug = error.debug();
                        warn!("GES Pipeline error: {} (debug: {:?})", err, debug);
                    }
                    *is_playing.lock().unwrap() = false;
                },
                gst::MessageType::Warning => {
                    let warning_msg = message.view();
                    if let gst::MessageView::Warning(warning) = warning_msg {
                        let err = warning.error();
                        let debug = warning.debug();
                        warn!("GES Pipeline warning: {} (debug: {:?})", err, debug);
                    }
                },
                gst::MessageType::StateChanged => {
                    let state_msg = message.view();
                    if let gst::MessageView::StateChanged(state_changed) = state_msg {
                        let old = state_changed.old();
                        let new = state_changed.current();
                        let pending = state_changed.pending();
                        let src = message.src();
                        
                        // Only log pipeline-level state changes, not every element
                        if let Some(src_name) = src.and_then(|s| Some(s.name().to_string())) {
                            if src_name.contains("pipeline") {
                                info!("GES Pipeline state changed: {:?} -> {:?} (pending: {:?})", old, new, pending);
                                // Update playing state based on pipeline state
                                *is_playing.lock().unwrap() = new == gst::State::Playing;
                            } else {
                                debug!("Element {} state changed: {:?} -> {:?}", src_name, old, new);
                            }
                        }
                    }
                },
                gst::MessageType::AsyncDone => {
                    info!("GES Pipeline ASYNC_DONE – state change completed");
                    let pos = *current_position_ms.lock().unwrap();
                    if let Ok(callback_guard) = seek_completion_callback.lock() {
                        if let Some(ref callback) = *callback_guard {
                            if let Err(e) = callback(pos) {
                                warn!("Seek completion callback error: {}", e);
                            }
                        }
                    }
                },
                gst::MessageType::StreamStart => {
                    info!("GES Pipeline stream started");
                },
                gst::MessageType::DurationChanged => {
                    info!("GES Pipeline duration changed");
                },
                gst::MessageType::Latency => {
                    debug!("GES Pipeline latency message");
                },
                gst::MessageType::NewClock => {
                    info!("GES Pipeline selected new clock");
                },
                _ => {
                    debug!("GES Pipeline received message type: {:?}", message.type_());
                }
            }
            
            gst::glib::ControlFlow::Continue
        }).map_err(|e| anyhow!("Failed to add bus watch: {}", e))?;
        
        info!("GES Pipeline message bus handling setup completed");
        Ok(())
    }

    fn setup_video_sink(&mut self, pipeline: &ges::Pipeline) -> Result<()> {
        // Create an appsink to capture video frames from GES pipeline
        let appsink = gst::ElementFactory::make("appsink")
            .name("texture_sink")
            .property("emit-signals", true)  // CRITICAL: Enable callbacks for video frames
            .property("sync", true)
            .property("max-buffers", 1u32)   // Reduce latency
            .property("drop", true)
            .build()
            .map_err(|e| anyhow!("Failed to create appsink: {}", e))?;

        // Set video format for the appsink
        let caps = gst::Caps::builder("video/x-raw")
            .field("format", "RGBA")
            .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
            .build();

        let appsink = appsink.dynamic_cast::<gst_app::AppSink>().unwrap();
        appsink.set_caps(Some(&caps));

        // Set video sink on the GES pipeline
        pipeline.preview_set_video_sink(Some(&appsink.clone().upcast::<gst::Element>()));

        // Set up frame callback to update texture using texture_id approach (like DirectPipelinePlayer)
        if let Some(texture_id) = self.texture_id {
            info!("Setting up appsink callbacks for texture rendering with texture ID: {}", texture_id);
            appsink.set_callbacks(
                gst_app::AppSinkCallbacks::builder()
                    .new_sample(move |sink| {
                        debug!("Received new video sample from GES pipeline");
                        match Self::handle_video_sample(sink, texture_id) {
                            Ok(_) => {
                                debug!("Successfully processed video frame for texture {}", texture_id);
                                Ok(gst::FlowSuccess::Ok)
                            },
                            Err(e) => {
                                warn!("Failed to handle video sample: {}", e);
                                Err(gst::FlowError::Error)
                            }
                        }
                    })
                    .build(),
            );
        } else {
            warn!("No texture ID available for video rendering");
        }

        info!("GES Pipeline video sink configured for texture rendering");
        Ok(())
    }

    pub fn play(&self) -> Result<()> {
        info!("Setting GES pipeline to PLAYING");
        let pipeline = self.pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("GES Pipeline not loaded"))?;
        
        // GES Pipeline handles gap creation automatically
        match pipeline.set_state(gst::State::Playing) {
            Ok(gst::StateChangeSuccess::Success) => {
                info!("GES Pipeline immediately transitioned to PLAYING");
                *self.is_playing.lock().unwrap() = true;
            },
            Ok(gst::StateChangeSuccess::Async) => {
                info!("GES Pipeline transitioning to PLAYING asynchronously");
                *self.is_playing.lock().unwrap() = true;
            },
            Ok(gst::StateChangeSuccess::NoPreroll) => {
                info!("GES Pipeline transitioned to PLAYING (no preroll)");
                *self.is_playing.lock().unwrap() = true;
            },
            Err(e) => {
                return Err(anyhow!("Failed to set GES pipeline to PLAYING state: {}", e));
            }
        }
        
        info!("GES Pipeline play command sent successfully - gaps will be filled with silence/black");
        Ok(())
    }

    pub fn pause(&self) -> Result<()> {
        info!("Setting GES pipeline to PAUSED");
        let pipeline = self.pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("GES Pipeline not loaded"))?;
            
        pipeline.set_state(gst::State::Paused)?;
        *self.is_playing.lock().unwrap() = false;
        info!("GES Pipeline paused");
        Ok(())
    }

    fn stop_pipeline(&mut self) -> Result<()> {
        if let Some(timer_id) = self.position_timer_id.lock().unwrap().take() {
            timer_id.remove();
            info!("Stopped position monitoring timer");
        }
        
        if let Some(pipeline) = &self.pipeline {
            info!("Setting GES pipeline to NULL");
            pipeline.set_state(gst::State::Null)?;
            *self.is_playing.lock().unwrap() = false;
            *self.current_position_ms.lock().unwrap() = 0;
        }
        
        // Clean up GES timeline
        if let Some(timeline_handle) = self.timeline_handle.take() {
            if let Err(e) = destroy_timeline(timeline_handle) {
                warn!("Failed to destroy GES timeline: {}", e);
            }
        }
        
        // Clear pipeline reference
        self.pipeline = None;
        
        info!("GES Pipeline stopped and cleared");
        Ok(())
    }

    pub fn seek(&self, position_ms: u64) -> Result<()> {
        info!("Seeking GES pipeline to {}ms", position_ms);
        let Some(pipeline) = self.pipeline.as_ref() else {
            return Err(anyhow!("GES Pipeline not loaded"));
        };
        
        let seek_result = pipeline.seek_simple(
            gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
            gst::ClockTime::from_mseconds(position_ms),
        );
        
        if seek_result.is_err() {
            return Err(anyhow!("Failed to seek GES pipeline to position {}ms", position_ms));
        }
        
        *self.current_position_ms.lock().unwrap() = position_ms;
        
        info!("GES Pipeline seek to {}ms completed - gap handling preserved", position_ms);
        Ok(())
    }

    pub fn get_current_position_seconds(&self) -> f64 {
        if let Some(pipeline) = &self.pipeline {
            if let Some(position) = pipeline.query_position::<gst::ClockTime>() {
                let position_ns = position.nseconds();
                return position_ns as f64 / 1_000_000_000.0;
            }
        }
        *self.current_position_ms.lock().unwrap() as f64 / 1000.0
    }

    pub fn update_position(&self) {
        if let Some(pipeline) = &self.pipeline {
            if let Some(position) = pipeline.query_position::<gst::ClockTime>() {
                let position_ns = position.nseconds();
                let position_ms = (position_ns as f64 / 1_000_000.0) as u64;
                *self.current_position_ms.lock().unwrap() = position_ms;
            }
        }
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

    pub fn set_position_update_callback(&mut self, callback: PositionUpdateCallback) -> Result<()> {
        let mut guard = self.position_callback.lock().unwrap();
        *guard = Some(callback);
        Ok(())
    }
    
    pub fn set_seek_completion_callback(&mut self, callback: SeekCompletionCallback) -> Result<()> {
        let mut guard = self.seek_completion_callback.lock().unwrap();
        *guard = Some(callback);
        Ok(())
    }
    
    /// Update a specific clip's transform properties
    pub fn update_clip_transform(
        &mut self,
        clip_id: i32,
        preview_position_x: f64,
        preview_position_y: f64,
        preview_width: f64,
        preview_height: f64,
    ) -> Result<()> {
        if let Some(timeline_handle) = self.timeline_handle {
            with_timeline(timeline_handle, |timeline_wrapper| {
                // Update clip properties in GES timeline
                if let Some(_clip) = timeline_wrapper.clips.get(&clip_id) {
                    // GES clips can have their properties updated directly
                    // For now, just log the update - full implementation would update clip properties
                    info!("Updating clip {} transform: pos({}, {}), size({}, {})", 
                          clip_id, preview_position_x, preview_position_y, preview_width, preview_height);
                }
                Ok(())
            })?;
        }
        Ok(())
    }

    pub fn dispose(&mut self) -> Result<()> {
        info!("Disposing GES Timeline Player");
        self.stop_pipeline()?;
        info!("GES Timeline Player disposed successfully");
        Ok(())
    }
}

impl Drop for GESTimelinePlayer {
    fn drop(&mut self) {
        info!("Cleaning up GES Timeline Player");
        let _ = self.dispose();
    }
}

impl Default for GESTimelinePlayer {
    fn default() -> Self {
        Self::new().expect("Failed to create GES Timeline Player")
    }
}