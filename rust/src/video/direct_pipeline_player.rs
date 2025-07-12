use anyhow::{anyhow, Result};
use gstreamer as gst;
use gstreamer_app;
use gstreamer_editing_services as ges;
use gst::prelude::*;
use log::{info, warn};
use std::sync::{Arc, Mutex};

use crate::common::types::TimelineData;
use crate::video::wgpu_texture::{create_gpu_video_texture, mark_gpu_textures_available, WgpuTexture, get_texture_id_for_engine};
use crate::video::ges_timeline::GESTimelineManager;
use crate::video::ges_pipeline::GESPipelineManager;
use gstreamer_gl as gst_gl;
use gstreamer_gl::prelude::GLContextExt;

pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) -> Result<()> + Send + Sync>;
pub type SeekCompletionCallback = Box<dyn Fn(u64) -> Result<()> + Send + Sync>;

/// A GStreamer pipeline player using GES (GStreamer Editing Services) for timeline management.
pub struct DirectPipelinePlayer {
    // GES components
    ges_timeline_manager: GESTimelineManager,
    ges_pipeline_manager: GESPipelineManager,
    
    // GPU texture state
    texture_id: Option<i64>,
    wgpu_texture: Option<Arc<WgpuTexture>>,
    gl_context: Option<gst_gl::GLContext>,
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
            
            // GPU texture state
            texture_id: None,
            wgpu_texture: None,
            gl_context: None,
            is_playing: Arc::new(Mutex::new(false)),
            current_position_ms: Arc::new(Mutex::new(0)),
            duration_ms: Arc::new(Mutex::new(None)),
            position_callback: Arc::new(Mutex::new(None)),
            seek_completion_callback: Arc::new(Mutex::new(None)),
            flutter_engine_handle: None,
        })
    }


    pub fn load_timeline(&mut self, timeline_data: TimelineData, engine_handle: i64) -> Result<i64> {
        let total_clips: usize = timeline_data.tracks.iter().map(|t| t.clips.len()).sum();
        println!("🔥 LOAD_TIMELINE CALLED with {} tracks and {} clips", timeline_data.tracks.len(), total_clips);
        info!("Loading RED TEST PATTERN (5s) instead of timeline for GPU context testing");
        self.stop_pipeline()?;
        
        // Store engine handle
        self.flutter_engine_handle = Some(engine_handle);
        
        // Create test pipeline with red background instead of GES timeline
        let video_sink = self.create_gpu_video_sink(engine_handle)?;
        self.create_test_red_pipeline(&video_sink)?;
        
        // Set test duration to 5 seconds
        *self.duration_ms.lock().unwrap() = Some(5000);
        
        info!("GPU-only RED TEST pipeline loaded successfully");
        Ok(self.texture_id.unwrap_or(0))
    }
    
    
    fn create_gpu_video_sink(&mut self, engine_handle: i64) -> Result<gst::Element> {
        info!("Creating GPU-only video sink with OpenGL context sharing");
        
        // Create glsinkbin for GPU processing
        let glsinkbin = gst::ElementFactory::make("glsinkbin")
            .name("gpu_video_sink")
            .build()
            .map_err(|e| anyhow!("Failed to create glsinkbin: {}", e))?;
        
        // Create appsink as the sink element inside glsinkbin
        let appsink = gst::ElementFactory::make("appsink")
            .name("gpu_appsink")
            .property("emit-signals", true)
            .property("sync", true)
            .property("async", false)
            .property("max-buffers", 3u32)
            .property("drop", false)
            .build()
            .map_err(|e| anyhow!("Failed to create appsink: {}", e))?;
        
        // Set GL memory caps for zero-copy GPU processing
        let caps = gst::Caps::builder("video/x-raw")
            .field("format", "RGBA")
            .field("texture-target", "2D")
            .features(["memory:GLMemory"])
            .build();
        appsink.set_property("caps", &caps);
        
        // Set the appsink as the sink element for glsinkbin
        glsinkbin.set_property("sink", &appsink);
        
        // Set up appsink callback for GPU texture handling
        let appsink_element = appsink.dynamic_cast::<gstreamer_app::AppSink>()
            .map_err(|_| anyhow!("Failed to cast to AppSink"))?;
        
        appsink_element.set_callbacks(
            gstreamer_app::AppSinkCallbacks::builder()
                .new_sample(move |appsink| {
                    // GPU-only frame processing - no CPU copies!
                    if let Ok(sample) = appsink.pull_sample() {
                        if let Some(buffer) = sample.buffer() {
                            // Check if buffer has GL memory - simplified check for GPU mode
                            // In GPU-only mode, we assume all buffers are GL memory
                            // since we're using glsinkbin with GL memory caps
                            if buffer.n_memory() > 0 {
                                // This buffer is already on GPU - mark textures available
                                if let Err(e) = mark_gpu_textures_available() {
                                    warn!("Failed to mark GPU textures available: {}", e);
                                } else {
                                    // Log successful GPU frame processing (occasionally)
                                    use std::sync::atomic::{AtomicU32, Ordering};
                                    static FRAME_COUNT: AtomicU32 = AtomicU32::new(0);
                                    let count = FRAME_COUNT.fetch_add(1, Ordering::Relaxed);
                                    if count % 30 == 0 {
                                        info!("🚀 GPU-only frame {} processed (zero CPU copy)", count);
                                    }
                                }
                                return Ok(gst::FlowSuccess::Ok);
                            }
                            
                            warn!("Received non-GL memory buffer - this should not happen in GPU-only mode");
                        }
                    }
                    Ok(gst::FlowSuccess::Ok)
                })
                .build(),
        );
        
        // Extract GL context from the pipeline for texture creation
        // This happens after the pipeline is created and GL context is available
        
        // Create GL context and GPU texture immediately - simplified approach
        // We'll create our own GL context instead of trying to extract from pipeline
        match self.create_gl_context_and_texture(engine_handle) {
            Ok(texture_id) => {
                info!("🚀 Created GPU texture with ID: {}", texture_id);
                self.texture_id = Some(texture_id);
                crate::video::wgpu_texture::store_texture_id_for_engine(engine_handle, texture_id);
            }
            Err(e) => {
                warn!("Failed to create GPU texture: {}", e);
            }
        }
        
        info!("✅ Created GPU-only video sink with OpenGL context sharing");
        Ok(glsinkbin)
    }

    fn create_gl_context_and_texture(&mut self, engine_handle: i64) -> Result<i64> {
        info!("Creating GL context and GPU texture");
        
        // Create a GL display for our platform
        let gl_display = gst_gl::GLDisplay::new();
        
        // Create GL context
        let gl_context = gst_gl::GLContext::new(&gl_display);
        
        // Activate the context
        gl_context.activate(true)
            .map_err(|e| anyhow!("Failed to activate GL context: {}", e))?;
        
        // Store the context
        self.gl_context = Some(gl_context.clone());
        
        // Create GPU texture with the new context
        let (texture_id, wgpu_texture) = create_gpu_video_texture(gl_context, 1920, 1080, engine_handle)?;
        self.wgpu_texture = Some(wgpu_texture);
        
        Ok(texture_id)
    }

    fn create_test_red_pipeline(&mut self, video_sink: &gst::Element) -> Result<()> {
        info!("Creating test pipeline with 5-second red background");
        
        // Create pipeline
        let pipeline = gst::Pipeline::new();
        
        // Create videotestsrc with solid color - fallback to simple approach
        let test_src = gst::ElementFactory::make("videotestsrc")
            .name("red_test_source")
            .property("num-buffers", 150i32)  // 5 seconds at 30fps = 150 frames
            .property("foreground-color", 0xFF0000FFu32)  // Red color (RGBA)
            .build()
            .map_err(|e| anyhow!("Failed to create videotestsrc: {}", e))?;
        
        // Try to set pattern, but don't fail if it doesn't work
        let _ = test_src.set_property_from_str("pattern", "solid-color");
        
        // Create caps filter for consistent format
        let caps_filter = gst::ElementFactory::make("capsfilter")
            .name("test_caps_filter")
            .build()
            .map_err(|e| anyhow!("Failed to create capsfilter: {}", e))?;
        
        let caps = gst::Caps::builder("video/x-raw")
            .field("format", "RGBA")
            .field("width", 1920i32)
            .field("height", 1080i32)
            .field("framerate", gst::Fraction::new(30, 1))
            .build();
        caps_filter.set_property("caps", &caps);
        
        // Add elements to pipeline
        pipeline.add_many(&[&test_src, &caps_filter, video_sink])
            .map_err(|e| anyhow!("Failed to add elements to test pipeline: {}", e))?;
        
        // Link elements
        test_src.link(&caps_filter)
            .map_err(|e| anyhow!("Failed to link test_src to caps_filter: {}", e))?;
        caps_filter.link(video_sink)
            .map_err(|e| anyhow!("Failed to link caps_filter to video_sink: {}", e))?;
        
        // Store pipeline in GES pipeline manager for consistent interface
        self.ges_pipeline_manager.set_test_pipeline(pipeline);
        
        info!("✅ Test red background pipeline created successfully");
        Ok(())
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

    /// Get the GPU texture ID for this player
    pub fn get_gpu_texture_id(&self) -> Option<i64> {
        if let Some(engine_handle) = self.flutter_engine_handle {
            get_texture_id_for_engine(engine_handle)
        } else {
            None
        }
    }

    pub fn dispose(&mut self) -> Result<()> {
        if let Some(texture_id) = self.texture_id {
            crate::video::wgpu_texture::unregister_gpu_texture(texture_id);
            info!("Unregistered GPU texture {}", texture_id);
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