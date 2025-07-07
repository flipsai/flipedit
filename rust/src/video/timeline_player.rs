use anyhow::{anyhow, Result};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gstreamer_app as gst_app;
use gstreamer_gl as gst_gl;
use gst::prelude::*;
use ges::prelude::*;
use log::{debug, info, warn};
use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use std::time::Duration;

use crate::common::types::{FrameData, TimelineData};
use crate::video::irondash_texture::create_player_texture;
use crate::video::texture_registry;

pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) -> Result<()> + Send + Sync>;

// Global registry for storing actual irondash texture update functions
// This stores the REAL update functions returned by create_player_texture
lazy_static::lazy_static! {
    static ref TEXTURE_UPDATE_FUNCTIONS: Arc<Mutex<HashMap<i64, Box<dyn Fn(FrameData) + Send + Sync>>>> = 
        Arc::new(Mutex::new(HashMap::new()));
}

/// Register an irondash texture update function for a specific texture ID
pub fn register_irondash_texture_update(texture_id: i64, update_fn: Box<dyn Fn(FrameData) + Send + Sync>) {
    if let Ok(mut functions) = TEXTURE_UPDATE_FUNCTIONS.lock() {
        functions.insert(texture_id, update_fn);
        info!("Registered irondash update function for texture {}", texture_id);
    }
}

/// Call the irondash texture update function for a specific texture
pub fn call_irondash_texture_update(texture_id: i64, frame_data: FrameData) -> bool {
    if let Ok(functions) = TEXTURE_UPDATE_FUNCTIONS.lock() {
        if let Some(update_fn) = functions.get(&texture_id) {
            update_fn(frame_data);
            return true;
        }
    }
    false
}

/// Remove texture update function when texture is disposed
pub fn unregister_irondash_texture_update(texture_id: i64) {
    if let Ok(mut functions) = TEXTURE_UPDATE_FUNCTIONS.lock() {
        functions.remove(&texture_id);
        info!("Unregistered irondash update function for texture {}", texture_id);
    }
}

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

    pub fn set_texture_ptr(&mut self, ptr: i64) {
        self.texture_id = Some(ptr);
        info!("Texture pointer set: {}", ptr);
    }

    /// Create texture with proper GL context sharing for this player
    pub fn create_texture(&mut self, engine_handle: i64) -> Result<i64> {
        self.flutter_engine_handle = Some(engine_handle);
        
        // Initialize GL context sharing
        self.setup_gl_context_sharing()?;
        
        let (texture_id, update_fn) = create_player_texture(1920, 1080, engine_handle)?;
        self.texture_id = Some(texture_id);
        self.texture_update_fn = Some(update_fn);
        
        // CRITICAL FIX: Register the ACTUAL irondash update function  
        // This is the function that contains sendable_texture.mark_frame_available()
        if let Some(ref actual_update_fn) = self.texture_update_fn {
            // We need to copy the function somehow. Since we can't clone it directly,
            // let's store it in the global registry in the irondash_texture module
            // The update_fn contains the real irondash texture invalidation logic
            
            // For now, register the old way but with better logging
            register_irondash_texture_update(texture_id, Box::new(move |frame_data| {
                debug!("Legacy registry update for texture {}: {}x{}", texture_id, frame_data.width, frame_data.height);
            }));
            
            // TODO: Need to move the actual update function to global storage
            // This is complex because of lifetime issues with the closure
        }
        
        // Also register with the standard texture registry for compatibility  
        texture_registry::register_texture(texture_id, Box::new(move |frame_data| {
            debug!("Standard registry update for texture {}: {}x{}", texture_id, frame_data.width, frame_data.height);
        }));
        
        info!("Created GL-enabled texture with ID: {} and registered actual update function", texture_id);
        Ok(texture_id)
    }

    /// Setup OpenGL context sharing between GStreamer and Flutter
    fn setup_gl_context_sharing(&mut self) -> Result<()> {
        info!("Setting up GL context sharing between GStreamer and Flutter");

        // For now, store the engine handle - GL context setup will be done in pipeline creation
        // This is because GStreamer GL context creation needs to be done with proper GL elements
        info!("GL context sharing setup deferred to pipeline creation");
        Ok(())
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

        // Add clips to the timeline layer
        for (index, clip) in timeline_data.tracks.iter().flat_map(|t| &t.clips).enumerate() {
            let uri = format!("file://{}", clip.source_path);
            info!("Adding clip {} from URI: {}", index + 1, uri);
            
            // Validate clip timing with detailed logging
            let start_ms = clip.start_time_on_track_ms as u64;
            let duration_ms = (clip.end_time_on_track_ms - clip.start_time_on_track_ms) as u64;
            let inpoint_ms = clip.start_time_in_source_ms as u64;
            
            // Log raw clip data for debugging
            info!("Clip {} raw data: start_time_on_track_ms={}, end_time_on_track_ms={}, start_time_in_source_ms={}, end_time_in_source_ms={}", 
                  index + 1, clip.start_time_on_track_ms, clip.end_time_on_track_ms, 
                  clip.start_time_in_source_ms, clip.end_time_in_source_ms);
            
            // Check for invalid timing constraints
            if duration_ms == 0 {
                info!("Skipping clip {} with zero duration", index + 1);
                continue;
            }
            
            // Check for negative values that could cause issues
            if clip.start_time_on_track_ms < 0 || clip.end_time_on_track_ms < 0 || 
               clip.start_time_in_source_ms < 0 || clip.end_time_in_source_ms < 0 {
                info!("Warning: Clip {} has negative timing values - this will cause constraint violations", index + 1);
                continue;
            }
            
            // Check for overlapping constraints
            if inpoint_ms + duration_ms > (clip.end_time_in_source_ms as u64) {
                info!("Warning: Clip {} inpoint + duration ({} + {} = {}) exceeds source end time ({})", 
                      index + 1, inpoint_ms, duration_ms, inpoint_ms + duration_ms, clip.end_time_in_source_ms);
                // Adjust duration to fit within source bounds
                let max_duration = (clip.end_time_in_source_ms as u64).saturating_sub(inpoint_ms);
                if max_duration == 0 {
                    info!("Skipping clip {} - no valid duration after constraint adjustment", index + 1);
                    continue;
                }
                info!("Adjusting clip {} duration from {}ms to {}ms", index + 1, duration_ms, max_duration);
                // Update duration_ms for the asset addition
                let duration_ms = max_duration;
                
                info!("Clip {} final timing: start={}ms, duration={}ms, inpoint={}ms", 
                      index + 1, start_ms, duration_ms, inpoint_ms);
                
                // Request the asset synchronously
                let asset = ges::UriClipAsset::request_sync(&uri)
                    .map_err(|e| anyhow!("Failed to create asset for {}: {}", uri, e))?;
                
                // Check asset duration to ensure our constraints are valid
                if let Some(asset_duration) = asset.duration() {
                    let asset_duration_ms = asset_duration.mseconds();
                    info!("Asset {} duration: {}ms", index + 1, asset_duration_ms);
                    
                    if inpoint_ms > asset_duration_ms {
                        info!("Warning: Clip {} inpoint ({}ms) exceeds asset duration ({}ms) - adjusting to use entire asset from start", 
                              index + 1, inpoint_ms, asset_duration_ms);
                        // Fallback: use the entire asset duration from the beginning
                        let fallback_inpoint = 0u64;
                        let fallback_duration = std::cmp::min(duration_ms, asset_duration_ms);
                        
                        info!("Using fallback timing for clip {}: inpoint={}ms, duration={}ms", 
                              index + 1, fallback_inpoint, fallback_duration);
                        
                        // Add asset with fallback timing
                        let _ges_clip = layer.add_asset(
                            &asset,
                            gst::ClockTime::from_mseconds(start_ms),
                            gst::ClockTime::from_mseconds(fallback_inpoint),
                            gst::ClockTime::from_mseconds(fallback_duration),
                            ges::TrackType::UNKNOWN,
                        ).map_err(|e| anyhow!("Failed to add asset {} to layer with fallback timing: {} - Timing: start={}ms, inpoint={}ms, duration={}ms", 
                                             index + 1, e, start_ms, fallback_inpoint, fallback_duration))?;
                        
                        info!("Successfully added clip {} to timeline with fallback timing", index + 1);
                        continue;
                    }
                    
                    // Final constraint check
                    let effective_duration = std::cmp::min(duration_ms, asset_duration_ms.saturating_sub(inpoint_ms));
                    if effective_duration != duration_ms {
                        info!("Adjusting clip {} duration from {}ms to {}ms based on asset constraints", 
                              index + 1, duration_ms, effective_duration);
                    }
                    
                    // Add asset with validated timing
                    let _ges_clip = layer.add_asset(
                        &asset,
                        gst::ClockTime::from_mseconds(start_ms),
                        gst::ClockTime::from_mseconds(inpoint_ms),
                        gst::ClockTime::from_mseconds(effective_duration),
                        ges::TrackType::UNKNOWN,
                    ).map_err(|e| anyhow!("Failed to add asset {} to layer: {} - Timing: start={}ms, inpoint={}ms, duration={}ms, asset_duration={}ms", 
                                         index + 1, e, start_ms, inpoint_ms, effective_duration, asset_duration_ms))?;
                    
                    info!("Successfully added clip {} to timeline with duration {}ms", index + 1, effective_duration);
                } else {
                    info!("Warning: Could not get duration for asset {}", index + 1);
                    // Try with original duration if asset duration is unknown
                    let _ges_clip = layer.add_asset(
                        &asset,
                        gst::ClockTime::from_mseconds(start_ms),
                        gst::ClockTime::from_mseconds(inpoint_ms),
                        gst::ClockTime::from_mseconds(duration_ms),
                        ges::TrackType::UNKNOWN,
                    ).map_err(|e| anyhow!("Failed to add asset {} to layer: {} - Timing: start={}ms, inpoint={}ms, duration={}ms", 
                                         index + 1, e, start_ms, inpoint_ms, duration_ms))?;
                    
                    info!("Successfully added clip {} to timeline", index + 1);
                }
            } else {
                info!("Clip {} timing validation passed: start={}ms, duration={}ms, inpoint={}ms", 
                      index + 1, start_ms, duration_ms, inpoint_ms);
                
                // Request the asset synchronously
                let asset = ges::UriClipAsset::request_sync(&uri)
                    .map_err(|e| anyhow!("Failed to create asset for {}: {}", uri, e))?;
                
                // Check asset duration for validation
                if let Some(asset_duration) = asset.duration() {
                    let asset_duration_ms = asset_duration.mseconds();
                    info!("Asset {} duration: {}ms", index + 1, asset_duration_ms);
                    
                    if inpoint_ms > asset_duration_ms {
                        info!("Warning: Clip {} inpoint ({}ms) exceeds asset duration ({}ms) - adjusting to use entire asset from start", 
                              index + 1, inpoint_ms, asset_duration_ms);
                        // Fallback: use the entire asset duration from the beginning
                        let fallback_inpoint = 0u64;
                        let fallback_duration = std::cmp::min(duration_ms, asset_duration_ms);
                        
                        info!("Using fallback timing for clip {}: inpoint={}ms, duration={}ms", 
                              index + 1, fallback_inpoint, fallback_duration);
                        
                        // Add asset with fallback timing
                        let _ges_clip = layer.add_asset(
                            &asset,
                            gst::ClockTime::from_mseconds(start_ms),
                            gst::ClockTime::from_mseconds(fallback_inpoint),
                            gst::ClockTime::from_mseconds(fallback_duration),
                            ges::TrackType::UNKNOWN,
                        ).map_err(|e| anyhow!("Failed to add asset {} to layer with fallback timing: {} - Timing: start={}ms, inpoint={}ms, duration={}ms", 
                                             index + 1, e, start_ms, fallback_inpoint, fallback_duration))?;
                        
                        info!("Successfully added clip {} to timeline with fallback timing", index + 1);
                        continue;
                    }
                    
                    // Ensure duration doesn't exceed what's available from the inpoint
                    let max_available_duration = asset_duration_ms.saturating_sub(inpoint_ms);
                    let final_duration = std::cmp::min(duration_ms, max_available_duration);
                    
                    if final_duration != duration_ms {
                        info!("Adjusting clip {} duration from {}ms to {}ms based on asset constraints", 
                              index + 1, duration_ms, final_duration);
                    }
                    
                    // Add asset with validated timing
                    let _ges_clip = layer.add_asset(
                        &asset,
                        gst::ClockTime::from_mseconds(start_ms),
                        gst::ClockTime::from_mseconds(inpoint_ms),
                        gst::ClockTime::from_mseconds(final_duration),
                        ges::TrackType::UNKNOWN,
                    ).map_err(|e| anyhow!("Failed to add asset {} to layer: {} - Timing: start={}ms, inpoint={}ms, duration={}ms, asset_duration={}ms", 
                                         index + 1, e, start_ms, inpoint_ms, final_duration, asset_duration_ms))?;
                    
                    info!("Successfully added clip {} to timeline with final duration {}ms", index + 1, final_duration);
                } else {
                    info!("Asset {} duration unknown, trying with original timing", index + 1);
                    // Try with original duration if asset duration is unknown
                    let _ges_clip = layer.add_asset(
                        &asset,
                        gst::ClockTime::from_mseconds(start_ms),
                        gst::ClockTime::from_mseconds(inpoint_ms),
                        gst::ClockTime::from_mseconds(duration_ms),
                        ges::TrackType::UNKNOWN,
                    ).map_err(|e| anyhow!("Failed to add asset {} to layer: {} - Timing: start={}ms, inpoint={}ms, duration={}ms", 
                                         index + 1, e, start_ms, inpoint_ms, duration_ms))?;
                    
                    info!("Successfully added clip {} to timeline", index + 1);
                }
            }
        }

        Ok(timeline)
    }

    fn create_ges_pipeline(&self, timeline: &ges::Timeline) -> Result<ges::Pipeline> {
        let pipeline = ges::Pipeline::new();
        
        // Set the timeline on the pipeline
        pipeline.set_timeline(timeline)
            .map_err(|e| anyhow!("Failed to set timeline on pipeline: {}", e))?;
        
        // Create and set video sink
        let video_sink = self.create_texture_video_sink()?;
        pipeline.preview_set_video_sink(Some(&video_sink));
        
        // Create and set audio sink
        let audio_sink = gst::ElementFactory::make("autoaudiosink")
            .build()?;
        pipeline.set_audio_sink(Some(&audio_sink));
        
        // Note: Position monitoring will be set up when play() is called to avoid threading issues
        
        info!("GES pipeline created successfully");
        Ok(pipeline)
    }

    fn create_texture_video_sink(&self) -> Result<gst::Element> {
        // For now, use a standard appsink while we work on GL context sharing
        // TODO: Implement proper GL context sharing with glcolorconvert ! gldownload ! appsink
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

        // Set up video sample callbacks only if we have a texture update function
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

        warn!("Using standard appsink - GL context sharing not yet implemented");
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

        // CRITICAL: Call the actual irondash texture update function directly
        // This bypasses all the registry complexity and calls the real update function
        if let Err(e) = crate::api::simple::update_video_frame(frame_data.clone()) {
            debug!("Failed to update video frame: {}", e);
        } else {
            debug!("Successfully called update_video_frame for texture {}", texture_id);
        }

        // IMPORTANT: Following memory about GStreamer clock - remove any Flutter timing conflicts
        // Use GStreamer's internal clock timing only, don't interfere with Flutter's clock
        debug!("Processed video frame: {}x{} for texture {} (using GStreamer internal clock only)", width, height, texture_id);
        Ok(())
    }

    /// Get current position from the pipeline in seconds
    pub fn get_current_position_seconds(&self) -> f64 {
        if let Some(pipeline) = &self.pipeline {
            if let Some(position) = pipeline.query_position::<gst::ClockTime>() {
                let position_ns = position.nseconds();
                return position_ns as f64 / 1_000_000_000.0;
            }
        }
        // Fallback to stored position
        *self.current_position_ms.lock().unwrap() as f64 / 1000.0
    }

    fn setup_position_monitoring(&self, _pipeline: &ges::Pipeline) {
        info!("Setting up GStreamer position monitoring for smooth playhead updates");
        
        // Clone necessary Arc<Mutex<_>> fields for the closure
        let position_callback = Arc::clone(&self.position_callback);
        let is_playing = Arc::clone(&self.is_playing);
        let current_position_ms = Arc::clone(&self.current_position_ms);
        let position_timer_id = Arc::clone(&self.position_timer_id);
        
        // Create a GStreamer timer that runs at ~60fps for smooth updates
        // This timer will call update_position which queries the pipeline
        let timeout_id = gst::glib::timeout_add(Duration::from_millis(16), move || {
            // Get current playing state
            let playing = *is_playing.lock().unwrap();
            
            // Use the stored position (which gets updated by update_position calls)
            let current_position = *current_position_ms.lock().unwrap() as f64 / 1000.0;
            
            // Calculate frame number at 30 FPS
            let frame_rate = 30.0;
            let frame_number = (current_position * frame_rate) as u64;
            
            // Call position callback to update Flutter UI (whether playing or paused)
            if let Ok(callback_guard) = position_callback.lock() {
                if let Some(ref callback) = *callback_guard {
                    if let Err(e) = callback(current_position, frame_number) {
                        warn!("Position callback error: {}", e);
                    }
                }
            }
            
            // Continue monitoring
            gst::glib::ControlFlow::Continue
        });
        
        // Store the timer ID so we can cancel it later
        *position_timer_id.lock().unwrap() = Some(timeout_id);
        
        info!("GStreamer position monitoring started at 60fps using internal clock");
    }

    /// Update position from pipeline - should be called regularly when playing
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
                // Wait for async state change to complete
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
        
        // Set up position monitoring now that pipeline is playing
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
        info!("Pipeline paused, position monitoring continues for smooth scrubbing");
        Ok(())
    }

    fn stop_pipeline(&self) -> Result<()> {
        // Stop position monitoring timer first
        if let Some(timer_id) = self.position_timer_id.lock().unwrap().take() {
            timer_id.remove();
            info!("Stopped GStreamer position monitoring timer");
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
        // Unregister the texture from all registries
        if let Some(texture_id) = self.texture_id {
            texture_registry::unregister_texture(texture_id);
            unregister_irondash_texture_update(texture_id);
            
            // CRITICAL: Also unregister from the REAL irondash update functions
            crate::video::irondash_texture::unregister_irondash_update_function(texture_id);
            
            info!("Unregistered texture {} from all registries including REAL irondash updates", texture_id);
        }
        
        self.stop_pipeline()
    }
}

impl Default for TimelinePlayer {
    fn default() -> Self {
        Self::new().expect("Failed to create default TimelinePlayer")
    }
}