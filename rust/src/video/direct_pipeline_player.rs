use anyhow::{anyhow, Result};
use gstreamer as gst;
use gstreamer_app as gst_app;
use gst::prelude::*;
use log::{debug, info, warn};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::common::types::{FrameData, TimelineData, TimelineClip};
use crate::video::irondash_texture::create_player_texture;

pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) -> Result<()> + Send + Sync>;
pub type SeekCompletionCallback = Box<dyn Fn(u64) -> Result<()> + Send + Sync>;

/// A direct GStreamer pipeline player that replaces GES with a custom compositor-based approach.
/// This gives us full control over video mixing, positioning, and scaling without GES format negotiation issues.
pub struct DirectPipelinePlayer {
    pipeline: Option<gst::Pipeline>,
    compositor: Option<gst::Element>,
    audiomixer: Option<gst::Element>,
    clip_sources: HashMap<String, ClipSource>,
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

#[derive(Debug, Clone)]
struct ClipSource {
    uridecodebin: gst::Element,
    videoconvert: gst::Element,
    videoscale: gst::Element,
    caps_filter: gst::Element,
    compositor_pad: Option<gst::Pad>,
    audiomixer_pad: Option<gst::Pad>,
    clip_data: TimelineClip,
}

// SAFETY: We manually implement Send and Sync for DirectPipelinePlayer
// This is necessary because GStreamer objects are not Send/Sync by default,
// but we ensure that all GStreamer operations happen on the main thread.
unsafe impl Send for DirectPipelinePlayer {}
unsafe impl Sync for DirectPipelinePlayer {}

impl DirectPipelinePlayer {
    pub fn new() -> Result<Self> {
        gst::init().map_err(|e| anyhow!("Failed to initialize GStreamer: {}", e))?;
        
        // Configure plugin rankings for macOS compatibility
        #[cfg(target_os = "macos")]
        {
            use gst::prelude::*;
            let registry = gst::Registry::get();
            // Lower the rank of both vtdec variants to force software decoding
            if let Some(vtdec_factory) = registry.find_feature("vtdec", gst::PluginFeature::static_type()) {
                vtdec_factory.set_rank(gst::Rank::NONE);
                info!("Disabled vtdec decoder on macOS during initialization");
            }
            if let Some(vtdec_hw_factory) = registry.find_feature("vtdec_hw", gst::PluginFeature::static_type()) {
                vtdec_hw_factory.set_rank(gst::Rank::NONE);
                info!("Disabled vtdec_hw decoder on macOS during initialization");
            }
            // Ensure avdec_h264 (software decoder) has higher priority
            if let Some(avdec_factory) = registry.find_feature("avdec_h264", gst::PluginFeature::static_type()) {
                avdec_factory.set_rank(gst::Rank::PRIMARY + 1);
                info!("Prioritized avdec_h264 software decoder on macOS during initialization");
            }
        }
        
        info!("GStreamer initialized successfully for direct pipeline approach.");
        Ok(Self {
            pipeline: None,
            compositor: None,
            audiomixer: None,
            clip_sources: HashMap::new(),
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
        println!("🔥 LOAD_TIMELINE CALLED with {} tracks", timeline_data.tracks.len());
        info!("Loading timeline with {} tracks using direct GStreamer pipeline", timeline_data.tracks.len());
        self.stop_pipeline()?;

        // Calculate timeline duration
        let all_clips: Vec<_> = timeline_data.tracks.iter().flat_map(|t| &t.clips).collect();
        let max_clip_end = all_clips
            .iter()
            .map(|c| c.end_time_on_track_ms as u64)
            .max()
            .unwrap_or(0);
        let duration_ms = max_clip_end.max(30000);
        
        info!("Timeline duration: {}ms with {} clips", duration_ms, all_clips.len());
        *self.duration_ms.lock().unwrap() = Some(duration_ms);

        // Create the main pipeline
        let pipeline = self.create_direct_pipeline(&timeline_data)?;
        self.pipeline = Some(pipeline);

        info!("Direct pipeline loaded successfully, duration: {}ms", duration_ms);
        Ok(())
    }

    fn create_direct_pipeline(&mut self, timeline_data: &TimelineData) -> Result<gst::Pipeline> {
        println!("🔥 CREATING COMPOSITOR-BASED PIPELINE...");
        let pipeline = gst::Pipeline::new();
        println!("✅ Created new pipeline instance");
        
        // Get all clips from timeline
        let all_clips: Vec<_> = timeline_data.tracks.iter().flat_map(|t| &t.clips).collect();
        if all_clips.is_empty() {
            return Err(anyhow!("No clips to play"));
        }
        
        info!("Creating compositor pipeline with {} clips", all_clips.len());
        
        // Create compositor and audiomixer for combining multiple clips
        let compositor = gst::ElementFactory::make("compositor")
            .name("compositor")
            .build()
            .map_err(|e| anyhow!("Failed to create compositor: {}", e))?;
        
        let audiomixer = gst::ElementFactory::make("audiomixer")
            .name("audiomixer")
            .build()
            .map_err(|e| anyhow!("Failed to create audiomixer: {}", e))?;
        
        // Create video sink
        let video_sink = self.create_texture_video_sink()?;
        
        // Add elements to pipeline
        pipeline.add(&compositor)?;
        pipeline.add(&audiomixer)?;
        pipeline.add(&video_sink)?;
        
        // Link compositor to video sink
        compositor.link(&video_sink)?;
        
        // Store references for later use
        self.compositor = Some(compositor.clone());
        self.audiomixer = Some(audiomixer.clone());
        
        // Add each clip to the pipeline
        for (index, clip) in all_clips.iter().enumerate() {
            info!("Adding clip {} to pipeline: {}", index + 1, clip.source_path);
            
            // Check if file exists
            if !std::path::Path::new(&clip.source_path).exists() {
                warn!("Video file does not exist, skipping: {}", clip.source_path);
                continue;
            }
            
            self.add_clip_source(&pipeline, &compositor, &audiomixer, clip, index)?;
        }
        
        // Set up message bus handling
        println!("🔥 SETTING UP MESSAGE BUS...");
        self.setup_message_bus_handling(&pipeline)?;
        
        println!("✅ Compositor-based pipeline created successfully");
        info!("✅ Compositor-based pipeline created successfully with {} clips", all_clips.len());
        Ok(pipeline)
    }

    fn add_clip_source(
        &mut self,
        pipeline: &gst::Pipeline,
        compositor: &gst::Element,
        audiomixer: &gst::Element,
        clip_data: &TimelineClip,
        index: usize,
    ) -> Result<()> {
        let uri = format!("file://{}", clip_data.source_path);
        info!("Adding clip {} from URI: {}", index + 1, uri);
        
        // Create uridecodebin for this clip
        let uridecodebin = gst::ElementFactory::make("uridecodebin")
            .property("uri", &uri)
            .build()
            .map_err(|e| anyhow!("Failed to create uridecodebin for clip {}: {}", index + 1, e))?;
        
        // Create video processing elements
        let videoconvert = gst::ElementFactory::make("videoconvert")
            .build()
            .map_err(|e| anyhow!("Failed to create videoconvert for clip {}: {}", index + 1, e))?;
        
        let videoscale = gst::ElementFactory::make("videoscale")
            .property("add-borders", false)
            .build()
            .map_err(|e| anyhow!("Failed to create videoscale for clip {}: {}", index + 1, e))?;
        
        // Set scaling method to nearest neighbor for performance
        videoscale.set_property_from_str("method", "nearest-neighbour");
        
        // Create caps filter for explicit width/height sizing without aspect ratio preservation
        let caps_filter = gst::ElementFactory::make("capsfilter")
            .build()
            .map_err(|e| anyhow!("Failed to create capsfilter for clip {}: {}", index + 1, e))?;
        
        // Set explicit caps to force exact dimensions from inspector values
        let caps = gst::Caps::builder("video/x-raw")
            .field("width", clip_data.preview_width as i32)
            .field("height", clip_data.preview_height as i32)
            .field("pixel-aspect-ratio", gst::Fraction::new(1, 1)) // Force square pixels
            .build();
        caps_filter.set_property("caps", &caps);
        
        // Add elements to pipeline
        pipeline.add(&uridecodebin)?;
        pipeline.add(&videoconvert)?;
        pipeline.add(&videoscale)?;
        pipeline.add(&caps_filter)?;
        
        // Link video processing chain: videoconvert -> videoscale -> capsfilter
        videoconvert.link(&videoscale)?;
        videoscale.link(&caps_filter)?;
        
        // Request pads from compositor and audiomixer
        let compositor_pad = compositor.request_pad_simple("sink_%u")
            .ok_or_else(|| anyhow!("Failed to request compositor pad for clip {}", index + 1))?;
        
        let audiomixer_pad = audiomixer.request_pad_simple("sink_%u")
            .ok_or_else(|| anyhow!("Failed to request audiomixer pad for clip {}", index + 1))?;
        
        // Link caps_filter directly to compositor
        let caps_filter_src_pad = caps_filter.static_pad("src")
            .ok_or_else(|| anyhow!("Failed to get src pad from caps_filter for clip {}", index + 1))?;
        caps_filter_src_pad.link(&compositor_pad)?;
        
        // Set compositor pad properties for positioning and sizing
        compositor_pad.set_property("zorder", index as u32);
        compositor_pad.set_property("xpos", clip_data.preview_position_x as i32);
        compositor_pad.set_property("ypos", clip_data.preview_position_y as i32);
        compositor_pad.set_property("width", clip_data.preview_width as i32);
        compositor_pad.set_property("height", clip_data.preview_height as i32);
        
        info!("Set compositor pad properties for clip {}: pos=({}, {}), size=({}, {})", 
            index + 1, clip_data.preview_position_x, clip_data.preview_position_y, 
            clip_data.preview_width, clip_data.preview_height);
        
        // Set up pad-added callback for uridecodebin first (before moving audiomixer_pad)
        let pipeline_weak = pipeline.downgrade();
        let videoconvert_weak = videoconvert.downgrade();
        let audiomixer_weak = audiomixer.downgrade();
        let audiomixer_pad_weak = audiomixer_pad.downgrade();
        
        // Store the clip source
        let clip_source = ClipSource {
            uridecodebin: uridecodebin.clone(),
            videoconvert: videoconvert.clone(),
            videoscale,
            caps_filter,
            compositor_pad: Some(compositor_pad),
            audiomixer_pad: Some(audiomixer_pad),
            clip_data: clip_data.clone(),
        };
        
        let clip_id = format!("clip_{}", index);
        self.clip_sources.insert(clip_id.clone(), clip_source);
        
        uridecodebin.connect_pad_added(move |_src, src_pad| {
            let Some(pipeline) = pipeline_weak.upgrade() else { 
                warn!("Pipeline weak reference is gone");
                return; 
            };
            let Some(videoconvert) = videoconvert_weak.upgrade() else { 
                warn!("Videoconvert weak reference is gone");
                return; 
            };
            let Some(_audiomixer) = audiomixer_weak.upgrade() else { 
                warn!("Audiomixer weak reference is gone");
                return; 
            };
            let Some(audiomixer_pad) = audiomixer_pad_weak.upgrade() else { 
                warn!("Audiomixer pad weak reference is gone");
                return; 
            };
            
            let caps = src_pad.current_caps().or_else(|| Some(src_pad.query_caps(None)));
            if let Some(caps) = caps {
                let structure = caps.structure(0).unwrap();
                let media_type = structure.name();
                
                info!("Connecting pad with caps: {}", caps);
                
                if media_type.starts_with("video/") {
                    // Link video pad
                    let sink_pad = videoconvert.static_pad("sink").unwrap();
                    if sink_pad.is_linked() {
                        warn!("Video sink pad is already linked");
                        return;
                    }
                    
                    match src_pad.link(&sink_pad) {
                        Ok(_) => {
                            info!("Successfully linked video pad");
                        },
                        Err(e) => {
                            warn!("Failed to link video pad: {:?}", e);
                        }
                    }
                } else if media_type.starts_with("audio/") {
                    info!("Linking audio pad");
                    
                    // Create audio processing chain
                    let audioconvert = gst::ElementFactory::make("audioconvert")
                        .build().unwrap();
                    let audioresample = gst::ElementFactory::make("audioresample")
                        .build().unwrap();
                    
                    pipeline.add(&audioconvert).unwrap();
                    pipeline.add(&audioresample).unwrap();
                    
                    audioconvert.link(&audioresample).unwrap();
                    
                    // Link audio chain to mixer
                    let audioresample_src_pad = audioresample.static_pad("src").unwrap();
                    if let Err(e) = audioresample_src_pad.link(&audiomixer_pad) {
                        warn!("Failed to link audioresample to mixer: {:?}", e);
                    }
                    
                    // Link source to audio chain
                    let audioconvert_sink_pad = audioconvert.static_pad("sink").unwrap();
                    if src_pad.link(&audioconvert_sink_pad).is_err() {
                        warn!("Failed to link audio pad for clip");
                    }
                    
                    // Sync state with pipeline
                    audioconvert.sync_state_with_parent().unwrap();
                    audioresample.sync_state_with_parent().unwrap();
                    
                    info!("Successfully set up audio chain");
                }
            } else {
                warn!("No caps available for pad");
            }
        });
        
        info!("Added clip {} with transforms: position=({},{}), size=({},{}), pipeline: videoscale->capsfilter->videobox",
              index + 1,
              clip_data.preview_position_x, clip_data.preview_position_y,
              clip_data.preview_width, clip_data.preview_height);
        
        Ok(())
    }

    fn create_texture_video_sink(&self) -> Result<gst::Element> {
        let video_sink = gst::ElementFactory::make("appsink")
            .name("texture_video_sink0")
            .property("emit-signals", true)
            .property("sync", true)
            .property("drop", true)
            .property("max-buffers", 1u32)
            .build()
            .map_err(|e| anyhow!("Failed to create appsink: {}", e))?;

        // Set caps for RGBA output to texture
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

    fn setup_message_bus_handling(&mut self, pipeline: &gst::Pipeline) -> Result<()> {
        println!("🔥 Setting up message bus handling for direct pipeline");
        info!("Setting up message bus handling for direct pipeline");
        
        let bus = pipeline.bus().ok_or_else(|| anyhow!("Failed to get pipeline bus"))?;
        println!("✅ Got pipeline bus successfully");
        
        // Clone Arc references for the message handler
        let is_playing = Arc::clone(&self.is_playing);
        let seek_completion_callback = Arc::clone(&self.seek_completion_callback);
        let current_position_ms = Arc::clone(&self.current_position_ms);
        
        let _watch_guard = bus.add_watch(move |_bus, message| {
            println!("🔥 BUS MESSAGE: {:?} from {:?}", message.type_(), message.src().map(|s| s.name()));
            match message.type_() {
                gst::MessageType::Eos => {
                    println!("=== RECEIVED EOS (End of Stream) ===");
                    info!("=== RECEIVED EOS (End of Stream) ===");
                    *is_playing.lock().unwrap() = false;
                },
                gst::MessageType::Error => {
                    let error_msg = message.view();
                    if let gst::MessageView::Error(err) = error_msg {
                        println!("❌ Pipeline error: {} - {}", err.error(), err.debug().unwrap_or_default());
                        warn!("Pipeline error: {} - {}", err.error(), err.debug().unwrap_or_default());
                    }
                    *is_playing.lock().unwrap() = false;
                },
                gst::MessageType::Warning => {
                    let warning_msg = message.view();
                    if let gst::MessageView::Warning(warn) = warning_msg {
                        warn!("Pipeline warning: {} - {}", warn.error(), warn.debug().unwrap_or_default());
                    }
                },
                gst::MessageType::StateChanged => {
                    if let Some(src) = message.src() {
                        let state_msg = message.view();
                        if let gst::MessageView::StateChanged(state_change) = state_msg {
                            let old_state = state_change.old();
                            let new_state = state_change.current();
                            let pending_state = state_change.pending();
                            
                            // Only log pipeline state changes
                            if src.name().starts_with("pipeline") {
                                info!("Pipeline state changed: {:?} -> {:?} (pending: {:?})", 
                                      old_state, new_state, pending_state);
                                
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
                gst::MessageType::ClockLost => {
                    warn!("Clock lost - pipeline needs to be reset to PAUSED and back to PLAYING");
                },
                gst::MessageType::NewClock => {
                    let clock_msg = message.view();
                    if let gst::MessageView::NewClock(new_clock) = clock_msg {
                        info!("New clock selected: {:?}", new_clock.clock().map(|c| c.name()));
                    }
                },
                gst::MessageType::AsyncDone => {
                    debug!("Received ASYNC_DONE – seek operation completed");
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
                    info!("Stream started");
                },
                gst::MessageType::DurationChanged => {
                    debug!("Duration changed");
                },
                _ => {
                    debug!("Received message type: {:?}", message.type_());
                }
            }
            
            gst::glib::ControlFlow::Continue
        }).map_err(|e| anyhow!("Failed to add bus watch: {}", e))?;
        
        println!("✅ Message bus handling setup completed for direct pipeline");
        info!("Message bus handling setup completed for direct pipeline");
        Ok(())
    }

    pub fn play(&self) -> Result<()> {
        println!("🔥 PLAY CALLED - Simple playbin approach");
        info!("Setting playbin pipeline to PLAYING");
        let pipeline = self.pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("Pipeline not loaded"))?;
        
        println!("🔥 SETTING PLAYBIN TO PLAYING...");
        
        // Set playbin to PLAYING state - it handles everything internally
        match pipeline.set_state(gst::State::Playing) {
            Ok(gst::StateChangeSuccess::Success) => {
                println!("✅ Playbin immediately transitioned to PLAYING");
                *self.is_playing.lock().unwrap() = true;
            },
            Ok(gst::StateChangeSuccess::Async) => {
                println!("⏳ Playbin transitioning to PLAYING asynchronously");
                // Let the state change happen in the background
                *self.is_playing.lock().unwrap() = true;
            },
            Ok(gst::StateChangeSuccess::NoPreroll) => {
                println!("✅ Playbin transitioned to PLAYING (no preroll)");
                *self.is_playing.lock().unwrap() = true;
            },
            Err(e) => {
                println!("❌ Failed to set playbin to PLAYING state: {}", e);
                return Err(anyhow!("Failed to set playbin to PLAYING state: {}", e));
            }
        }
        
        println!("✅ Playbin play command sent successfully");
        info!("Playbin play command sent successfully");
        Ok(())
    }

    pub fn pause(&self) -> Result<()> {
        info!("Setting direct pipeline to PAUSED");
        let pipeline = self.pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("Pipeline not loaded"))?;
            
        pipeline.set_state(gst::State::Paused)?;
        *self.is_playing.lock().unwrap() = false;
        info!("Direct pipeline paused");
        Ok(())
    }

    fn stop_pipeline(&mut self) -> Result<()> {
        if let Some(timer_id) = self.position_timer_id.lock().unwrap().take() {
            timer_id.remove();
            info!("Stopped position monitoring timer");
        }
        
        if let Some(pipeline) = &self.pipeline {
            info!("Setting direct pipeline to NULL");
            pipeline.set_state(gst::State::Null)?;
            *self.is_playing.lock().unwrap() = false;
            *self.current_position_ms.lock().unwrap() = 0;
        }
        
        // Clear pipeline reference to prevent element name collisions
        self.pipeline = None;
        self.compositor = None;
        self.audiomixer = None;
        self.clip_sources.clear();
        
        info!("Direct pipeline stopped and cleared");
        Ok(())
    }

    pub fn seek(&self, position_ms: u64) -> Result<()> {
        info!("Seeking direct pipeline to {}ms", position_ms);
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
        
        // If pipeline is not playing, pull preroll to show the seeked frame
        let current_state = pipeline.current_state();
        if current_state != gst::State::Playing {
            // Ensure pipeline is in PAUSED state
            if current_state != gst::State::Paused {
                if let Err(e) = pipeline.set_state(gst::State::Paused) {
                    warn!("Failed to set pipeline to PAUSED after seek: {}", e);
                    return Ok(());
                }
                // Wait for state change to complete
                let timeout = gst::ClockTime::from_seconds(1);
                if let Err(e) = pipeline.state(Some(timeout)).0 {
                    warn!("Failed to complete state change to PAUSED after seek: {}", e);
                    return Ok(());
                }
            }
            
            // Pull preroll sample to show the frame at the new position
            if let Err(e) = self.pull_preroll_and_render() {
                warn!("Failed to pull preroll sample after seek to {}ms: {}", position_ms, e);
            } else {
                info!("Successfully showed frame at position {}ms after seek", position_ms);
            }
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
    
    /// Update a specific clip's transform properties without reloading the entire timeline
    pub fn update_clip_transform(
        &mut self,
        clip_id: i32,
        preview_position_x: f64,
        preview_position_y: f64,
        preview_width: f64,
        preview_height: f64,
    ) -> Result<()> {
        info!("Updating clip transform for clip_id {} to pos=({}, {}), size=({}, {})",
              clip_id, preview_position_x, preview_position_y, preview_width, preview_height);
        
        // Find the clip source by matching the clip ID
        let mut found_clip = None;
        for (key, clip_source) in self.clip_sources.iter_mut() {
            if clip_source.clip_data.id == Some(clip_id) {
                found_clip = Some(key.clone());
                break;
            }
        }
        
        let clip_key = found_clip.ok_or_else(|| anyhow!("Clip with ID {} not found", clip_id))?;
        
        // Get the clip source
        let clip_source = self.clip_sources.get_mut(&clip_key)
            .ok_or_else(|| anyhow!("Clip source not found for key {}", clip_key))?;
        
        // Update the clip data
        clip_source.clip_data.preview_position_x = preview_position_x;
        clip_source.clip_data.preview_position_y = preview_position_y;
        clip_source.clip_data.preview_width = preview_width;
        clip_source.clip_data.preview_height = preview_height;
        
        // Update the compositor pad properties
        if let Some(ref compositor_pad) = clip_source.compositor_pad {
            compositor_pad.set_property("xpos", preview_position_x as i32);
            compositor_pad.set_property("ypos", preview_position_y as i32);
            compositor_pad.set_property("width", preview_width as i32);
            compositor_pad.set_property("height", preview_height as i32);
            
            info!("Updated compositor pad properties for clip {}", clip_id);
        }
        
        // Update the caps filter to match the new dimensions
        let caps = gst::Caps::builder("video/x-raw")
            .field("width", preview_width as i32)
            .field("height", preview_height as i32)
            .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
            .build();
        clip_source.caps_filter.set_property("caps", &caps);
        
        // Trigger a frame update by forcing a seek and pulling preroll sample
        // This forces the pipeline to re-render with the new transform properties
        if let Some(pipeline) = &self.pipeline {
            let current_position = *self.current_position_ms.lock().unwrap();
            let current_state = pipeline.current_state();
            
            if current_state == gst::State::Playing {
                // Already playing, the frame will update naturally
                info!("Pipeline is playing, transform will be visible in next frame");
            } else {
                // Pipeline is paused/stopped, need to manually trigger frame update
                info!("Pipeline is paused, manually triggering frame update for transform");
                
                // Ensure pipeline is in PAUSED state
                if current_state != gst::State::Paused {
                    if let Err(e) = pipeline.set_state(gst::State::Paused) {
                        warn!("Failed to set pipeline to PAUSED: {}", e);
                        return Ok(());
                    }
                    // Wait for state change to complete
                    let timeout = gst::ClockTime::from_seconds(1);
                    if let Err(e) = pipeline.state(Some(timeout)).0 {
                        warn!("Failed to complete state change to PAUSED: {}", e);
                        return Ok(());
                    }
                }
                
                // Force seek to current position to trigger frame render with new transform
                let seek_result = pipeline.seek_simple(
                    gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
                    gst::ClockTime::from_mseconds(current_position),
                );
                
                if seek_result.is_ok() {
                    info!("Forced seek to {}ms to update frame with new transform", current_position);
                    
                    // Now pull the preroll sample to force the frame render
                    if let Err(e) = self.pull_preroll_and_render() {
                        warn!("Failed to pull preroll sample after transform update: {}", e);
                    }
                } else {
                    warn!("Failed to seek for frame update after transform change");
                }
                
                // Note: We DON'T restore to playing state here because the pipeline
                // was already paused when we started, so it should stay paused
            }
        }
        
        info!("Successfully updated clip {} transform properties", clip_id);
        Ok(())
    }
    
    /// Pull preroll sample from appsink when pipeline is paused and update texture
    /// This is the correct way to get a frame when the pipeline is in PAUSED state
    fn pull_preroll_and_render(&self) -> Result<()> {
        // Find the appsink element in the pipeline
        if let Some(pipeline) = &self.pipeline {
            let appsink = pipeline
                .by_name("texture_video_sink0")
                .ok_or_else(|| anyhow!("Could not find appsink element"))?;
            
            let appsink = appsink
                .dynamic_cast::<gst_app::AppSink>()
                .map_err(|_| anyhow!("Element is not an AppSink"))?;
            
            // Pull the preroll sample from the appsink (for paused pipelines)
            match appsink.try_pull_preroll(gst::ClockTime::from_seconds(1)) {
                Some(sample) => {
                    if let Some(texture_id) = self.texture_id {
                        // Process the sample and update texture using the same method as normal playback
                        match Self::handle_video_sample_from_buffer(&sample, texture_id) {
                            Ok(_) => {
                                info!("Successfully pulled preroll sample and updated texture {}", texture_id);
                                return Ok(());
                            }
                            Err(e) => {
                                warn!("Failed to process preroll sample: {}", e);
                                return Err(anyhow!("Failed to process preroll sample: {}", e));
                            }
                        }
                    }
                }
                None => {
                    debug!("No preroll sample available from appsink");
                    return Err(anyhow!("No preroll sample available from appsink"));
                }
            }
        }
        
        Err(anyhow!("No pipeline available for preroll rendering"))
    }
    
    /// Process a GStreamer sample and update the texture (extracted from handle_video_sample)
    fn handle_video_sample_from_buffer(
        sample: &gst::Sample,
        texture_id: i64,
    ) -> Result<()> {
        let buffer = sample.buffer().ok_or_else(|| anyhow!("No buffer in sample"))?;
        let map = buffer.map_readable().map_err(|_| anyhow!("Failed to map buffer"))?;

        let caps = sample.caps().ok_or_else(|| anyhow!("No caps in sample"))?;
        let s = caps.structure(0).ok_or_else(|| anyhow!("No structure in caps"))?;
        let width = s.get::<i32>("width").unwrap_or(1920) as u32;
        let height = s.get::<i32>("height").unwrap_or(1080) as u32;

        let frame_data = FrameData {
            data: map.as_slice().to_vec(),
            width,
            height,
            texture_id: Some(texture_id as u64),
        };

        // Update the texture with the new frame data
        if crate::api::simple::update_video_frame(frame_data) {
            info!("Successfully updated texture {} with preroll frame", texture_id);
            Ok(())
        } else {
            Err(anyhow!("Failed to update texture with preroll frame data"))
        }
    }

    pub fn dispose(&mut self) -> Result<()> {
        if let Some(texture_id) = self.texture_id {
            crate::video::irondash_texture::unregister_irondash_update_function(texture_id);
            info!("Unregistered texture {}", texture_id);
        }
        
        self.stop_pipeline()
    }
}

impl Default for DirectPipelinePlayer {
    fn default() -> Self {
        Self::new().expect("Failed to create default DirectPipelinePlayer")
    }
}