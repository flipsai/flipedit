use anyhow::{anyhow, Result};
use gstreamer as gst;
use gstreamer_app;
use gstreamer_video;
use gstreamer_editing_services as ges;
use gst::prelude::*;
use log::{info, warn};
use std::sync::{Arc, Mutex};

use crate::common::types::{FrameData, TimelineData};
use crate::video::irondash_texture::create_player_texture;
use crate::video::ges_timeline::GESTimelineManager;
use crate::video::ges_pipeline::GESPipelineManager;

pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) -> Result<()> + Send + Sync>;
pub type SeekCompletionCallback = Box<dyn Fn(u64) -> Result<()> + Send + Sync>;

/// A GStreamer pipeline player using GES (GStreamer Editing Services) for timeline management.
pub struct DirectPipelinePlayer {
    // GES components
    ges_timeline_manager: GESTimelineManager,
    ges_pipeline_manager: GESPipelineManager,
    
    // Texture and playback state
    texture_id: Option<i64>,
    texture_update_fn: Option<Box<dyn Fn(FrameData) + Send + Sync>>,
    is_playing: Arc<Mutex<bool>>,
    current_position_ms: Arc<Mutex<u64>>,
    duration_ms: Arc<Mutex<Option<u64>>>,
    position_callback: Arc<Mutex<Option<PositionUpdateCallback>>>,
    seek_completion_callback: Arc<Mutex<Option<SeekCompletionCallback>>>,
    flutter_engine_handle: Option<i64>,
}

// SAFETY: We manually implement Send and Sync for DirectPipelinePlayer
// This is necessary because GStreamer objects are not Send/Sync by default,
// but we ensure that all GStreamer operations happen on the main thread.
unsafe impl Send for DirectPipelinePlayer {}
unsafe impl Sync for DirectPipelinePlayer {}

impl DirectPipelinePlayer {
    pub fn new() -> Result<Self> {
        gst::init().map_err(|e| anyhow!("Failed to initialize GStreamer: {}", e))?;
        
        // Initialize GES
        ges::init()
            .map_err(|e| anyhow!("Failed to initialize GStreamer Editing Services: {}", e))?;
        
        // Set GStreamer debug environment to suppress the discoverer warning
        // This warning is non-critical and occurs when GES initializes its discoverer
        std::env::set_var("GST_DEBUG_NO_COLOR", "1");
        if std::env::var("GST_DEBUG").is_err() {
            std::env::set_var("GST_DEBUG", "discoverer:1,ges:2"); // Reduce discoverer verbosity
        }
        
        // Configure plugin rankings for better compatibility and error handling
        {
            use gst::prelude::*;
            let registry = gst::Registry::get();
            
            #[cfg(target_os = "macos")]
            {
                // Lower the rank of both vtdec variants to force software decoding
                if let Some(vtdec_factory) = registry.find_feature("vtdec", gst::PluginFeature::static_type()) {
                    vtdec_factory.set_rank(gst::Rank::NONE);
                    info!("Disabled vtdec decoder on macOS during initialization");
                }
                if let Some(vtdec_hw_factory) = registry.find_feature("vtdec_hw", gst::PluginFeature::static_type()) {
                    vtdec_hw_factory.set_rank(gst::Rank::NONE);
                    info!("Disabled vtdec_hw decoder on macOS during initialization");
                }
            }
            
            // For all platforms: prioritize software decoders to avoid libav reference frame issues
            if let Some(avdec_factory) = registry.find_feature("avdec_h264", gst::PluginFeature::static_type()) {
                avdec_factory.set_rank(gst::Rank::PRIMARY + 1);
                info!("Prioritized avdec_h264 software decoder for better error handling");
            }
            
            // Lower hardware decoder rankings to reduce reference frame errors
            #[cfg(target_os = "linux")]
            {
                // Lower VAAPI decoder rank as it can cause reference frame issues
                if let Some(vaapi_factory) = registry.find_feature("vaapih264dec", gst::PluginFeature::static_type()) {
                    vaapi_factory.set_rank(gst::Rank::SECONDARY);
                    info!("Lowered VAAPI H.264 decoder rank to reduce reference frame errors");
                }
                
                // Lower V4L2 decoder rank
                if let Some(v4l2_factory) = registry.find_feature("v4l2h264dec", gst::PluginFeature::static_type()) {
                    v4l2_factory.set_rank(gst::Rank::SECONDARY);
                    info!("Lowered V4L2 H.264 decoder rank to reduce reference frame errors");
                }
            }
        }
        
        info!("GStreamer initialized successfully for GES pipeline approach.");
        Ok(Self {
            // GES components
            ges_timeline_manager: GESTimelineManager::new(),
            ges_pipeline_manager: GESPipelineManager::new(),
            
            // Texture and playback state
            texture_id: None,
            texture_update_fn: None,
            is_playing: Arc::new(Mutex::new(false)),
            current_position_ms: Arc::new(Mutex::new(0)),
            duration_ms: Arc::new(Mutex::new(None)),
            position_callback: Arc::new(Mutex::new(None)),
            seek_completion_callback: Arc::new(Mutex::new(None)),
            flutter_engine_handle: None,
        })
    }

    /// Create texture with proper GL context sharing for this player
    pub fn create_texture(&mut self, engine_handle: i64) -> Result<i64> {
        let (texture_id, update_fn) = create_player_texture(1920, 1080, engine_handle)?;
        self.texture_id = Some(texture_id);
        self.texture_update_fn = Some(update_fn);
        self.flutter_engine_handle = Some(engine_handle);
        
        info!("Created GL-enabled texture with ID: {}", texture_id);
        Ok(texture_id)
    }

    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<()> {
        let total_clips: usize = timeline_data.tracks.iter().map(|t| t.clips.len()).sum();
        println!("🔥 LOAD_TIMELINE CALLED with {} tracks and {} clips", timeline_data.tracks.len(), total_clips);
        info!("Loading timeline with {} tracks and {} total clips using GES pipeline", timeline_data.tracks.len(), total_clips);
        self.stop_pipeline()?;
        
        // Create GES timeline using the timeline manager
        let timeline = self.ges_timeline_manager.create_timeline_from_data(timeline_data)?;
        
        // Create video sink for the GES pipeline (use autovideosink for proper GES integration)
        let video_sink = self.create_ges_video_sink()?;
        
        // Create GES pipeline using the pipeline manager
        self.ges_pipeline_manager.create_pipeline(&timeline, &video_sink)?;
        
        // Get duration from timeline manager
        if let Some(duration_ms) = self.ges_timeline_manager.get_duration_ms() {
            *self.duration_ms.lock().unwrap() = Some(duration_ms);
        }
        
        info!("GES pipeline loaded successfully with proper bus message handling");
        Ok(())
    }
    
    
    fn create_ges_video_sink(&self) -> Result<gst::Element> {
        // Create a simple appsink for GES pipeline - this is the recommended approach
        // GES pipelines work best with direct sinks, not complex tee setups
        
        info!("Creating direct appsink for GES pipeline video output");
        
        // Create appsink for texture updates
        let appsink = gst::ElementFactory::make("appsink")
            .name("ges_video_appsink")
            .property("emit-signals", true)
            .property("sync", true)  // Sync for proper timing in GES
            .property("async", false)
            .property("max-buffers", 3u32)  // Allow small buffer for smoother playback
            .property("drop", false)  // Don't drop frames for better quality
            .build()
            .map_err(|e| anyhow!("Failed to create appsink: {}", e))?;
        
        // Set appsink caps - use a more flexible format
        let caps = gst::Caps::builder("video/x-raw")
            .field("format", "RGBA")
            .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
            .build();
        appsink.set_property("caps", &caps);
        
        // Set up appsink callback
        let appsink_element = appsink.clone().dynamic_cast::<gstreamer_app::AppSink>()
            .map_err(|_| anyhow!("Failed to cast to AppSink"))?;
        
        appsink_element.set_callbacks(
            gstreamer_app::AppSinkCallbacks::builder()
                .new_sample(move |appsink| {
                    // Handle the video sample for texture updates
                    if let Ok(sample) = appsink.pull_sample() {
                        if let Some(buffer) = sample.buffer() {
                            if let Some(caps) = sample.caps() {
                                if let Ok(video_info) = gstreamer_video::VideoInfo::from_caps(&caps) {
                                    let width = video_info.width();
                                    let height = video_info.height();
                                    
                                    if let Ok(map) = buffer.map_readable() {
                                        let data = map.as_slice();
                                        
                                        // Create frame data and update texture
                                        let frame_data = FrameData {
                                            data: data.to_vec(),
                                            width,
                                            height,
                                            texture_id: None,
                                        };
                                        
                                        // Update the texture using the IronDash system
                                        if let Err(e) = crate::video::irondash_texture::update_video_frame(frame_data) {
                                            warn!("Failed to update texture: {}", e);
                                        } else {
                                            // Log successful frame processing (occasionally)
                                            static mut FRAME_COUNT: u32 = 0;
                                            unsafe {
                                                FRAME_COUNT += 1;
                                                if FRAME_COUNT % 30 == 0 {  // Log every 30 frames
                                                    info!("📺 Successfully processed frame {} ({}x{})", 
                                                          FRAME_COUNT, width, height);
                                                }
                                            }
                                        }
                                        
                                        return Ok(gst::FlowSuccess::Ok);
                                    }
                                }
                            }
                        }
                    }
                    Ok(gst::FlowSuccess::Ok)
                })
                .build(),
        );
        
        info!("✅ Created direct appsink for GES pipeline video output");
        Ok(appsink)
    }

    pub fn play(&mut self) -> Result<()> {
        println!("🔥 PLAY CALLED - GES pipeline approach");
        info!("Starting GES pipeline playback");
        
        // Use the GES pipeline manager to play
        self.ges_pipeline_manager.play()?;
        
        // Update shared state
        *self.is_playing.lock().unwrap() = true;
        
        println!("✅ GES pipeline play command sent successfully");
        info!("GES pipeline play command sent successfully");
        Ok(())
    }

    pub fn pause(&mut self) -> Result<()> {
        println!("🔥 PAUSE CALLED - GES pipeline approach");
        info!("Pausing GES pipeline playback");
        
        // Use the GES pipeline manager to pause
        self.ges_pipeline_manager.pause()?;
        
        // Update shared state
        *self.is_playing.lock().unwrap() = false;
        
        println!("✅ GES pipeline pause command sent successfully");
        info!("GES pipeline pause command sent successfully");
        Ok(())
    }

    fn stop_pipeline(&mut self) -> Result<()> {
        info!("Stopping GES pipeline");
        
        // Use GES pipeline manager to stop
        self.ges_pipeline_manager.stop()?;
        
        *self.is_playing.lock().unwrap() = false;
        
        // Reset position
        *self.current_position_ms.lock().unwrap() = 0;
        
        info!("GES pipeline stopped and cleared");
        Ok(())
    }

    pub fn seek(&mut self, position_ms: u64) -> Result<()> {
        info!("Seeking GES pipeline to {}ms", position_ms);
        
        // Use the GES pipeline manager to seek
        self.ges_pipeline_manager.seek(position_ms)?;
        
        // Update shared state
        *self.current_position_ms.lock().unwrap() = position_ms;
        
        info!("✅ GES pipeline seek completed to {}ms", position_ms);
        Ok(())
    }

    /// Check pipeline state and attempt recovery
    pub fn check_pipeline_state(&mut self) -> Result<()> {
        self.ges_pipeline_manager.check_and_recover_state()
    }

    pub fn get_position_secs(&self) -> f64 {
        *self.current_position_ms.lock().unwrap() as f64 / 1000.0
    }

    pub fn update_position(&self) {
        // Query position from GES pipeline manager
        if let Some(position_ms) = self.ges_pipeline_manager.query_position() {
            let old_position = *self.current_position_ms.lock().unwrap();
            *self.current_position_ms.lock().unwrap() = position_ms;
            
            // Update the GES pipeline manager's position tracking
            self.ges_pipeline_manager.update_position(position_ms);
            
            // Call position update callback if available
            if let Some(callback) = self.position_callback.lock().unwrap().as_ref() {
                let duration_ms = self.get_duration_ms().unwrap_or(0);
                if let Err(e) = callback(position_ms as f64 / 1000.0, duration_ms) {
                    warn!("Position update callback failed: {}", e);
                }
            }
            
            // Log position updates occasionally for debugging
            if position_ms > 0 && (position_ms - old_position) > 500 {
                println!("📍 Position updated: {}ms / {}ms", position_ms, self.get_duration_ms().unwrap_or(0));
            }
        }
    }

    pub fn get_duration_ms(&self) -> Option<u64> {
        *self.duration_ms.lock().unwrap()
    }
    
    pub fn get_current_position_ms(&self) -> u64 {
        // Query the latest position from the pipeline before returning
        if let Some(position_ms) = self.ges_pipeline_manager.query_position() {
            *self.current_position_ms.lock().unwrap() = position_ms;
            position_ms
        } else {
            *self.current_position_ms.lock().unwrap()
        }
    }

    pub fn get_current_frame_number(&self) -> u64 {
        let position_seconds = self.get_position_secs();
        // TODO: Get actual frame rate from video metadata instead of hardcoded 30fps
        let frame_rate = 30.0;
        (position_seconds * frame_rate) as u64
    }

    pub fn is_playing(&self) -> bool {
        // Check both our internal state and the actual pipeline state
        let internal_playing = *self.is_playing.lock().unwrap();
        let pipeline_playing = self.ges_pipeline_manager.is_playing();
        
        // If there's a mismatch, update our internal state
        if internal_playing != pipeline_playing {
            *self.is_playing.lock().unwrap() = pipeline_playing;
        }
        
        pipeline_playing
    }

    pub fn set_position_update_callback(&mut self, callback: PositionUpdateCallback) -> Result<()> {
        let mut guard = self.position_callback.lock().unwrap();
        *guard = Some(callback);
        info!("Position update callback registered");
        Ok(())
    }

    pub fn set_seek_completion_callback(&mut self, callback: SeekCompletionCallback) -> Result<()> {
        let mut guard = self.seek_completion_callback.lock().unwrap();
        *guard = Some(callback);
        info!("Seek completion callback registered");
        Ok(())
    }

    pub fn set_texture_update_function(&mut self, update_fn: Box<dyn Fn(FrameData) + Send + Sync>) -> Result<()> {
        self.texture_update_fn = Some(update_fn);
        info!("Texture update function registered for GES pipeline player");
        Ok(())
    }

    /// Update timeline position - handled automatically by GES
    pub fn update_timeline_position(&self, _timeline_position_ms: u64) -> Result<()> {
        // GES automatically handles clip visibility based on timeline position
        // No manual intervention needed
        Ok(())
    }

    /// Update clip transform - not implemented for GES (handled automatically)
    pub fn update_clip_transform(
        &mut self,
        _clip_id: i32,
        _position_x: f64,
        _position_y: f64,
        _scale_x: f64,
        _scale_y: f64,
    ) -> Result<()> {
        // GES handles clip transforms automatically
        // This method is kept for API compatibility but does nothing
        info!("Clip transform update requested - handled automatically by GES");
        Ok(())
    }

    /// Set the timeline duration explicitly (called from Flutter)
    pub fn set_timeline_duration(&mut self, duration_ms: u64) -> Result<()> {
        *self.duration_ms.lock().unwrap() = Some(duration_ms);
        info!("Timeline duration updated to {}ms", duration_ms);
        Ok(())
    }

    pub fn dispose(&mut self) -> Result<()> {
        if let Some(texture_id) = self.texture_id {
            crate::video::irondash_texture::unregister_irondash_update_function(texture_id);
            info!("Unregistered texture {}", texture_id);
        }
        
        // Dispose GES components
        self.ges_pipeline_manager.dispose()?;
        self.ges_timeline_manager.dispose();
        
        self.stop_pipeline()
    }
}

impl Default for DirectPipelinePlayer {
    fn default() -> Self {
        Self::new().expect("Failed to create default DirectPipelinePlayer")
    }
}