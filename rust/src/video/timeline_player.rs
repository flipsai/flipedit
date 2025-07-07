use anyhow::{anyhow, Result};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gstreamer_app as gst_app;
use gstreamer_gl as gst_gl;
use gst::prelude::*;
use ges::prelude::*;
use log::{debug, info, warn};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::common::types::{FrameData, TimelineData};
use crate::video::irondash_texture::create_player_texture;

pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) -> Result<()> + Send + Sync>;

/// A timeline player that uses GES (GStreamer Editing Services) Timeline,
/// following the proper architecture for video editing applications.
/// It renders the output to a texture that can be displayed in Flutter via irondash
/// using proper OpenGL context sharing through gstreamer_gl.
/// 
/// Note: This struct contains GStreamer objects that are not Send/Sync,
/// so it must be used carefully in multi-threaded environments.
pub struct TimelinePlayer {
    pipeline: Option<ges::Pipeline>,
    timeline: Option<ges::Timeline>,
    texture_id: Option<i64>,
    texture_update_fn: Option<Box<dyn Fn(FrameData) + Send + Sync>>,
    is_playing: Arc<Mutex<bool>>,
    current_position_ms: Arc<Mutex<u64>>,
    duration_ms: Arc<Mutex<Option<u64>>>,
    position_callback: Arc<Mutex<Option<PositionUpdateCallback>>>,
    position_timer_id: Arc<Mutex<Option<gst::glib::SourceId>>>,
    // Remove bus_watch_guard as it's not Send and causes hot restart issues
    // GL context sharing fields
    gl_display: Option<gst_gl::GLDisplay>,
    gl_context: Option<gst_gl::GLContext>,
    flutter_engine_handle: Option<i64>,
}

// SAFETY: We manually implement Send and Sync for TimelinePlayer
// This is necessary because GStreamer objects are not Send/Sync by default,
// but we ensure that all GStreamer operations happen on the main thread.
// The Arc<Mutex<_>> fields are already Send+Sync.
unsafe impl Send for TimelinePlayer {}
unsafe impl Sync for TimelinePlayer {}

impl TimelinePlayer {
    pub fn new() -> Result<Self> {
        gst::init().map_err(|e| anyhow!("Failed to initialize GStreamer: {}", e))?;
        ges::init().map_err(|e| anyhow!("Failed to initialize GES: {}", e))?;
        info!("GStreamer and GES initialized successfully.");
        Ok(Self {
            pipeline: None,
            timeline: None,
            texture_id: None,
            texture_update_fn: None,
            is_playing: Arc::new(Mutex::new(false)),
            current_position_ms: Arc::new(Mutex::new(0)),
            duration_ms: Arc::new(Mutex::new(None)),
            position_callback: Arc::new(Mutex::new(None)),
            position_timer_id: Arc::new(Mutex::new(None)),
            gl_display: None,
            gl_context: None,
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
        info!(
            "Loading timeline with {} tracks",
            timeline_data.tracks.len()
        );
        self.stop_pipeline()?;

        // Calculate timeline duration more carefully
        let all_clips: Vec<_> = timeline_data.tracks.iter().flat_map(|t| &t.clips).collect();
        let max_clip_end = all_clips
            .iter()
            .map(|c| c.end_time_on_track_ms as u64)
            .max()
            .unwrap_or(0);
        let duration_ms = max_clip_end.max(30000);
        
        info!("Timeline duration calculation:");
        info!("  Total clips: {}", all_clips.len());
        for (i, clip) in all_clips.iter().enumerate() {
            info!("  Clip {}: {}ms -> {}ms (duration: {}ms)", 
                  i + 1, 
                  clip.start_time_on_track_ms, 
                  clip.end_time_on_track_ms,
                  clip.end_time_on_track_ms - clip.start_time_on_track_ms);
        }
        info!("  Max clip end: {}ms, Final duration: {}ms", max_clip_end, duration_ms);
        *self.duration_ms.lock().unwrap() = Some(duration_ms);

        // Create GES timeline
        let timeline = self.create_ges_timeline(&timeline_data)?;
        self.timeline = Some(timeline.clone());

        // Create GES pipeline
        let pipeline = self.create_ges_pipeline(&timeline)?;
        self.pipeline = Some(pipeline);

        info!("Timeline loaded successfully, duration: {}ms", duration_ms);
        Ok(())
    }

    fn create_ges_timeline(&self, timeline_data: &TimelineData) -> Result<ges::Timeline> {
        let timeline = ges::Timeline::new_audio_video();
        let layer = timeline.append_layer();

        info!("Creating GES timeline with {} clips", 
              timeline_data.tracks.iter().flat_map(|t| &t.clips).count());

        // Collect all clips and sort them by start time for proper sequencing
        let mut all_clips: Vec<_> = timeline_data.tracks.iter().flat_map(|t| &t.clips).collect();
        all_clips.sort_by_key(|clip| clip.start_time_on_track_ms);
        
        // Add clips to the timeline layer in chronological order
        for (index, clip) in all_clips.iter().enumerate() {
            let uri = format!("file://{}", clip.source_path);
            info!("Adding clip {} from URI: {}", index + 1, uri);
            
            let start_ms = clip.start_time_on_track_ms as u64;
            let duration_ms = (clip.end_time_on_track_ms - clip.start_time_on_track_ms) as u64;
            let inpoint_ms = clip.start_time_in_source_ms as u64;
            
            if duration_ms == 0 {
                info!("Skipping clip {} with zero duration", index + 1);
                continue;
            }
            
            if clip.start_time_on_track_ms < 0 || clip.end_time_on_track_ms < 0 || 
               clip.start_time_in_source_ms < 0 || clip.end_time_in_source_ms < 0 {
                info!("Warning: Clip {} has negative timing values", index + 1);
                continue;
            }
            
            let asset = ges::UriClipAsset::request_sync(&uri)
                .map_err(|e| anyhow!("Failed to create asset for {}: {}", uri, e))?;
            
            if let Some(asset_duration) = asset.duration() {
                let asset_duration_ms = asset_duration.mseconds();
                info!("Asset {} duration: {}ms", index + 1, asset_duration_ms);
                
                let final_inpoint = if inpoint_ms > asset_duration_ms { 0 } else { inpoint_ms };
                let max_duration = asset_duration_ms.saturating_sub(final_inpoint);
                let final_duration = std::cmp::min(duration_ms, max_duration);
                
                let ges_clip = layer.add_asset(
                    &asset,
                    gst::ClockTime::from_mseconds(start_ms),
                    gst::ClockTime::from_mseconds(final_inpoint),
                    gst::ClockTime::from_mseconds(final_duration),
                    ges::TrackType::VIDEO | ges::TrackType::AUDIO,
                ).map_err(|e| anyhow!("Failed to add asset {} to layer: {}", index + 1, e))?;
                
                info!("Added clip {} to timeline: start={}ms, duration={}ms, inpoint={}ms", 
                      index + 1, start_ms, final_duration, final_inpoint);
                
                info!("Successfully added clip {} to timeline", index + 1);
            } else {
                let ges_clip = layer.add_asset(
                    &asset,
                    gst::ClockTime::from_mseconds(start_ms),
                    gst::ClockTime::from_mseconds(inpoint_ms),
                    gst::ClockTime::from_mseconds(duration_ms),
                    ges::TrackType::VIDEO | ges::TrackType::AUDIO,
                ).map_err(|e| anyhow!("Failed to add asset {} to layer: {}", index + 1, e))?;
                
                info!("Added clip {} to timeline: start={}ms, duration={}ms, inpoint={}ms", 
                      index + 1, start_ms, duration_ms, inpoint_ms);
                info!("Successfully added clip {} to timeline", index + 1);
            }
        }

        // Commit the timeline after all clips are added
        if !timeline.commit() {
            return Err(anyhow!("Failed to commit GES timeline"));
        }
        
        info!("GES timeline committed successfully with {} clips", all_clips.len());
        Ok(timeline)
    }

    fn create_ges_pipeline(&mut self, timeline: &ges::Timeline) -> Result<ges::Pipeline> {
        let pipeline = ges::Pipeline::new();
        
        pipeline.set_timeline(timeline)
            .map_err(|e| anyhow!("Failed to set timeline on pipeline: {}", e))?;
        
        let video_sink = self.create_texture_video_sink()?;
        pipeline.preview_set_video_sink(Some(&video_sink));
        
        let audio_sink = gst::ElementFactory::make("autoaudiosink")
            .build()?;
        pipeline.set_audio_sink(Some(&audio_sink));
        
        // Set up message bus handling for EOS and other pipeline events
        self.setup_message_bus_handling(&pipeline)?;
        
        info!("GES pipeline created successfully with message bus handling");
        Ok(pipeline)
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

        let appsink = video_sink
            .clone()
            .dynamic_cast::<gst_app::AppSink>()
            .unwrap();
        
        if let Some(texture_id) = self.texture_id {
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

        if !crate::api::simple::update_video_frame(frame_data.clone()) {
            debug!("Failed to update video frame");
        }

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

    fn setup_position_monitoring(&self, _pipeline: &ges::Pipeline) {
        info!("Setting up GStreamer position monitoring for smooth playhead updates");
        
        let position_callback = Arc::clone(&self.position_callback);
        let is_playing = Arc::clone(&self.is_playing);
        let current_position_ms = Arc::clone(&self.current_position_ms);
        let position_timer_id = Arc::clone(&self.position_timer_id);
        
        let timeout_id = gst::glib::timeout_add(Duration::from_millis(16), move || {
            let _playing = *is_playing.lock().unwrap();
            let current_position = *current_position_ms.lock().unwrap() as f64 / 1000.0;
            let frame_rate = 30.0;
            let frame_number = (current_position * frame_rate) as u64;
            
            if let Ok(callback_guard) = position_callback.lock() {
                if let Some(ref callback) = *callback_guard {
                    if let Err(e) = callback(current_position, frame_number) {
                        warn!("Position callback error: {}", e);
                    }
                }
            }
            
            gst::glib::ControlFlow::Continue
        });
        
        *position_timer_id.lock().unwrap() = Some(timeout_id);
        info!("GStreamer position monitoring started at 60fps");
    }

    fn setup_message_bus_handling(&mut self, pipeline: &ges::Pipeline) -> Result<()> {
        info!("Setting up message bus handling for EOS and pipeline events");
        
        let bus = pipeline.bus().ok_or_else(|| anyhow!("Failed to get pipeline bus"))?;
        
        // Clone Arc references for the message handler
        let is_playing = Arc::clone(&self.is_playing);
        let duration_ms = Arc::clone(&self.duration_ms);
        
        // Set up async message handling without storing the guard
        // This prevents Send/Sync issues during hot restart
        let _watch_guard = bus.add_watch(move |_bus, message| {
            match message.type_() {
                gst::MessageType::Eos => {
                    info!("=== RECEIVED EOS (End of Stream) ===");
                    info!("Timeline playback completed normally");
                    
                    // Reset position to beginning for potential replay
                    // Note: We don't automatically restart - let the UI handle this
                    *is_playing.lock().unwrap() = false;
                    info!("Timeline playback finished, set playing state to false");
                },
                gst::MessageType::Error => {
                    let error_msg = message.view();
                    if let gst::MessageView::Error(err) = error_msg {
                        warn!("Pipeline error: {} - {}", err.error(), err.debug().unwrap_or_default());
                    }
                    *is_playing.lock().unwrap() = false;
                },
                gst::MessageType::StateChanged => {
                    if let Some(src) = message.src() {
                        if src.name() == "pipeline0" { // GES pipeline name
                            let state_msg = message.view();
                            if let gst::MessageView::StateChanged(state_change) = state_msg {
                                let old_state = state_change.old();
                                let new_state = state_change.current();
                                debug!("Pipeline state changed: {:?} -> {:?}", old_state, new_state);
                                
                                // Update playing state based on pipeline state
                                match new_state {
                                    gst::State::Playing => {
                                        *is_playing.lock().unwrap() = true;
                                        info!("Pipeline confirmed PLAYING state");
                                    },
                                    gst::State::Paused | gst::State::Null | gst::State::Ready => {
                                        *is_playing.lock().unwrap() = false;
                                        debug!("Pipeline confirmed non-playing state: {:?}", new_state);
                                    },
                                    _ => {}
                                }
                            }
                        }
                    }
                },
                gst::MessageType::DurationChanged => {
                    debug!("Pipeline duration changed");
                    // Duration is already calculated from timeline data, so we don't need to update it
                },
                _ => {
                    // Log other message types for debugging
                    debug!("Received message type: {:?}", message.type_());
                }
            }
            
            gst::glib::ControlFlow::Continue
        }).map_err(|e| anyhow!("Failed to add bus watch: {}", e))?;
        
        // Let the watch guard be automatically cleaned up when pipeline is destroyed
        
        info!("Message bus handling setup completed");
        Ok(())
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

    pub fn play(&self) -> Result<()> {
        info!("Setting pipeline to PLAYING");
        let pipeline = self.pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("Pipeline not loaded"))?;
            
        match pipeline.set_state(gst::State::Playing) {
            Ok(gst::StateChangeSuccess::Success) => {
                info!("Pipeline state change to PLAYING completed successfully");
            },
            Ok(gst::StateChangeSuccess::Async) => {
                info!("Pipeline state change to PLAYING is async, waiting...");
                let (result, current_state, _pending_state) = pipeline.state(gst::ClockTime::from_seconds(5));
                match result {
                    Ok(_) => {
                        if current_state == gst::State::Playing {
                            info!("Async state change to PLAYING completed successfully");
                        } else {
                            return Err(anyhow!("Pipeline reached state {:?} instead of PLAYING", current_state));
                        }
                    },
                    Err(e) => {
                        return Err(anyhow!("Failed to wait for PLAYING state: {}", e));
                    }
                }
            },
            Ok(gst::StateChangeSuccess::NoPreroll) => {
                info!("Pipeline state change to PLAYING completed (no preroll)");
            },
            Err(e) => return Err(anyhow!("Failed to set pipeline to PLAYING state: {}", e)),
        }
        
        self.setup_position_monitoring(pipeline);
        *self.is_playing.lock().unwrap() = true;
        info!("Pipeline is now PLAYING with position monitoring active");
        Ok(())
    }

    pub fn pause(&self) -> Result<()> {
        info!("Setting pipeline to PAUSED");
        let pipeline = self.pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("Pipeline not loaded"))?;
            
        match pipeline.set_state(gst::State::Paused) {
            Ok(gst::StateChangeSuccess::Success) => {},
            Ok(gst::StateChangeSuccess::Async) => {},
            Ok(gst::StateChangeSuccess::NoPreroll) => {},
            Err(e) => return Err(anyhow!("Failed to set pipeline to PAUSED state: {}", e)),
        }
        
        *self.is_playing.lock().unwrap() = false;
        info!("Pipeline paused, position monitoring continues");
        Ok(())
    }

    fn stop_pipeline(&self) -> Result<()> {
        if let Some(timer_id) = self.position_timer_id.lock().unwrap().take() {
            timer_id.remove();
            info!("Stopped position monitoring timer");
        }
        
        if let Some(pipeline) = &self.pipeline {
            info!("Setting pipeline to NULL");
            pipeline.set_state(gst::State::Null)?;
            *self.is_playing.lock().unwrap() = false;
            *self.current_position_ms.lock().unwrap() = 0;
        }
        Ok(())
    }

    pub fn seek(&self, position_ms: u64) -> Result<()> {
        info!("Seeking to {}ms", position_ms);
        let Some(pipeline) = self.pipeline.as_ref() else {
            return Err(anyhow!("Pipeline not loaded"));
        };
        
        let seek_result = pipeline.seek_simple(
            gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
            gst::ClockTime::from_mseconds(position_ms),
        );
        
        if seek_result.is_err() {
            return Err(anyhow!("Failed to seek to position {}ms", position_ms));
        }
        
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
        if let Some(texture_id) = self.texture_id {
            crate::video::irondash_texture::unregister_irondash_update_function(texture_id);
            info!("Unregistered texture {}", texture_id);
        }
        
        self.stop_pipeline()
    }
}

impl Default for TimelinePlayer {
    fn default() -> Self {
        Self::new().expect("Failed to create default TimelinePlayer")
    }
}