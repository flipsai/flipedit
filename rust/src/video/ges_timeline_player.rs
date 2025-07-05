use crate::common::types::{FrameData, TimelineData, TimelineClip, TimelineTrack, TextureFrame};
use crate::video::frame_handler::FrameHandler;
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_editing_services as ges;
use gstreamer_editing_services::prelude::*;
use gstreamer_editing_services::prelude::TrackElementExt;
use gstreamer_app as gst_app;
use gstreamer_video as gst_video;
use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use log::{info, debug};
use anyhow::Result;

pub type FrameCallback = Box<dyn Fn(FrameData) -> Result<()> + Send + Sync>;
pub type PositionUpdateCallback = Box<dyn Fn(f64, u64) -> Result<()> + Send + Sync>;

pub struct GESTimelinePlayer {
    // GES components - using Arc<Mutex<>> for thread safety
    pub timeline: Arc<Mutex<Option<ges::Timeline>>>,
    pub pipeline: Arc<Mutex<Option<ges::Pipeline>>>,
    pub layers: Arc<Mutex<Vec<ges::Layer>>>,
    pub assets: Arc<Mutex<HashMap<String, ges::UriClipAsset>>>,
    
    // Frame handling
    pub frame_handler: FrameHandler,
    
    // State tracking
    pub is_playing: Arc<Mutex<bool>>,
    pub current_position_ms: Arc<Mutex<i32>>,
    pub duration_ms: Arc<Mutex<Option<i32>>>,
    
    // Callbacks
    frame_callback: Arc<Mutex<Option<FrameCallback>>>,
    position_callback: Arc<Mutex<Option<PositionUpdateCallback>>>,
    
    // Timeline data
    timeline_data: Option<TimelineData>,
    
    // Playback state
    seekable: Arc<Mutex<bool>>,
}

impl GESTimelinePlayer {
    pub fn new() -> Self {
        // Initialize GES
        ges::init().expect("Failed to initialize GStreamer Editing Services");
        
        Self {
            timeline: Arc::new(Mutex::new(None)),
            pipeline: Arc::new(Mutex::new(None)),
            layers: Arc::new(Mutex::new(Vec::new())),
            assets: Arc::new(Mutex::new(HashMap::new())),
            frame_handler: FrameHandler::new(),
            is_playing: Arc::new(Mutex::new(false)),
            current_position_ms: Arc::new(Mutex::new(0)),
            duration_ms: Arc::new(Mutex::new(None)),
            frame_callback: Arc::new(Mutex::new(None)),
            position_callback: Arc::new(Mutex::new(None)),
            timeline_data: None,
            seekable: Arc::new(Mutex::new(false)),
        }
    }

    pub fn set_texture_ptr(&mut self, ptr: i64) {
        self.frame_handler.set_texture_ptr(ptr);
    }

    pub fn set_frame_callback(&mut self, callback: FrameCallback) -> Result<()> {
        let mut guard = self.frame_callback.lock().unwrap();
        *guard = Some(callback);
        Ok(())
    }

    pub fn set_position_update_callback(&mut self, callback: PositionUpdateCallback) -> Result<()> {
        let mut guard = self.position_callback.lock().unwrap();
        *guard = Some(callback);
        Ok(())
    }

    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<(), String> {
        info!("Loading timeline with {} tracks", timeline_data.tracks.len());
        
        // Store timeline data
        self.timeline_data = Some(timeline_data.clone());
        
        // Create new GES timeline
        let timeline = ges::Timeline::new();
        
        // Clear existing layers
        self.layers.lock().unwrap().clear();
        
        // Process each track
        for track in &timeline_data.tracks {
            self.create_track_layer(&timeline, track)?;
        }
        
        // Create GES pipeline
        let pipeline = ges::Pipeline::new();
        pipeline.set_timeline(&timeline)
            .map_err(|e| format!("Failed to set timeline on pipeline: {:?}", e))?;
        
        // Configure video mode for proper composition
        pipeline.set_mode(ges::PipelineFlags::FULL_PREVIEW)
            .map_err(|e| format!("Failed to set pipeline mode: {:?}", e))?;
        
        // Set up rendering output
        self.setup_video_output(&pipeline)?;
        
        // Store components
        *self.timeline.lock().unwrap() = Some(timeline);
        *self.pipeline.lock().unwrap() = Some(pipeline);
        
        // Apply composition configuration after all clips are loaded
        self.apply_final_composition_settings()?;
        
        // Query timeline properties
        self.query_timeline_properties();
        
        info!("Timeline loaded successfully");
        Ok(())
    }

    fn create_track_layer(&mut self, timeline: &ges::Timeline, track: &TimelineTrack) -> Result<(), String> {
        info!("Creating layer for track: {}", track.name);
        
        // Create a new layer for this track
        let layer = timeline.append_layer();
        layer.set_priority(track.id as u32);
        
        // Configure layer properties for video composition
        layer.set_auto_transition(true);
        
        // Process each clip in the track
        for clip in &track.clips {
            self.add_clip_to_layer(&layer, clip)?;
        }
        
        self.layers.lock().unwrap().push(layer);
        Ok(())
    }

    fn add_clip_to_layer(&mut self, layer: &ges::Layer, clip: &TimelineClip) -> Result<(), String> {
        debug!("Adding clip to layer: {}", clip.source_path);
        
        // Create URI for the clip
        let uri = if clip.source_path.starts_with("file://") {
            clip.source_path.clone()
        } else {
            format!("file://{}", clip.source_path)
        };
        
        // Load or get existing asset
        let asset = self.get_or_load_asset(&uri)?;
        
        // Create GES clip from asset (need to cast to Clip)
        let extractable = asset.extract()
            .map_err(|e| format!("Failed to extract clip from asset: {:?}", e))?;
        
        let ges_clip = extractable.downcast::<ges::Clip>()
            .map_err(|_| "Failed to downcast to Clip")?;
        
        // Set timing properties
        let start_time = gst::ClockTime::from_nseconds((clip.start_time_on_track_ms as u64) * 1_000_000);
        let in_point = gst::ClockTime::from_nseconds((clip.start_time_in_source_ms as u64) * 1_000_000);
        let duration = gst::ClockTime::from_nseconds(
            ((clip.end_time_in_source_ms - clip.start_time_in_source_ms) as u64) * 1_000_000
        );
        
        ges_clip.set_start(start_time);
        ges_clip.set_inpoint(in_point);
        ges_clip.set_duration(duration);
        
        // Add clip to layer first
        layer.add_clip(&ges_clip)
            .map_err(|e| format!("Failed to add clip to layer: {:?}", e))?;
        
        // Wait a moment for the clip to be fully added to the timeline
        // This ensures all track elements are created
        std::thread::sleep(std::time::Duration::from_millis(10));
        
        // Configure video positioning and scaling for the clip
        self.configure_clip_video_properties(&ges_clip, clip)?;
        
        debug!("Clip added successfully: start={:?}, duration={:?}", start_time, duration);
        Ok(())
    }

    fn get_or_load_asset(&mut self, uri: &str) -> Result<ges::UriClipAsset, String> {
        // Check if asset already exists
        {
            let assets = self.assets.lock().unwrap();
            if let Some(asset) = assets.get(uri) {
                return Ok(asset.clone());
            }
        }
        
        // Load new asset
        info!("Loading asset: {}", uri);
        let asset = ges::UriClipAsset::request_sync(uri)
            .map_err(|e| format!("Failed to load asset {}: {:?}", uri, e))?;
        
        // Store asset for reuse
        self.assets.lock().unwrap().insert(uri.to_string(), asset.clone());
        
        Ok(asset)
    }

    fn configure_clip_video_properties(&self, ges_clip: &ges::Clip, clip: &TimelineClip) -> Result<(), String> {
        info!("Configuring video properties for clip '{}': position=({}, {}), size=({}, {})", 
               clip.source_path, clip.preview_position_x, clip.preview_position_y, 
               clip.preview_width, clip.preview_height);
        
        // Get all track elements (children) from the clip
        let children = ges_clip.children(false);
        info!("Found {} child elements in clip", children.len());
        
        for child in children.iter() {
            // Try to cast to VideoSource for video-specific properties
            if let Some(video_source) = child.clone().downcast::<ges::VideoSource>().ok() {
                info!("Found VideoSource element, setting properties...");
                
                // Set position and size properties using explicit trait method and converting to GValue
                use gst::glib::Value;
                
                // Position properties (in pixels, relative to composition size)
                let posx_value = Value::from(clip.preview_position_x as i32);
                match TrackElementExt::set_child_property(&video_source, "posx", &posx_value) {
                    Ok(_) => info!("Set posx to {}", clip.preview_position_x),
                    Err(e) => info!("Failed to set posx: {:?} (this may be normal if compositor isn't ready)", e),
                }
                
                let posy_value = Value::from(clip.preview_position_y as i32);
                match TrackElementExt::set_child_property(&video_source, "posy", &posy_value) {
                    Ok(_) => info!("Set posy to {}", clip.preview_position_y),
                    Err(e) => info!("Failed to set posy: {:?} (this may be normal if compositor isn't ready)", e),
                }
                
                // Size properties (in pixels)
                let width_value = Value::from(clip.preview_width as i32);
                match TrackElementExt::set_child_property(&video_source, "width", &width_value) {
                    Ok(_) => info!("Set width to {}", clip.preview_width),
                    Err(e) => info!("Failed to set width: {:?} (this may be normal if compositor isn't ready)", e),
                }
                
                let height_value = Value::from(clip.preview_height as i32);
                match TrackElementExt::set_child_property(&video_source, "height", &height_value) {
                    Ok(_) => info!("Set height to {}", clip.preview_height),
                    Err(e) => info!("Failed to set height: {:?} (this may be normal if compositor isn't ready)", e),
                }
                
                // Additional composition properties
                let alpha_value = Value::from(1.0f64);
                match TrackElementExt::set_child_property(&video_source, "alpha", &alpha_value) {
                    Ok(_) => info!("Set alpha to 1.0"),
                    Err(e) => info!("Failed to set alpha: {:?}", e),
                }
                
                // Set zorder (layer priority) - higher numbers appear on top
                let zorder_value = Value::from(clip.track_id);
                match TrackElementExt::set_child_property(&video_source, "zorder", &zorder_value) {
                    Ok(_) => info!("Set zorder to {}", clip.track_id),
                    Err(e) => info!("Failed to set zorder: {:?}", e),
                }
                
                info!("Video properties configuration completed for clip");
                break;
            } else {
                debug!("Child element is not a VideoSource: {:?}", child.type_());
            }
        }
        
        if children.is_empty() {
            info!("No child elements found in clip - they may be created later during playback");
        }
        
        Ok(())
    }

    fn apply_final_composition_settings(&self) -> Result<(), String> {
        info!("Applying final composition settings to ensure video transformations work");
        
        // Re-configure all clip properties now that the timeline is fully set up
        let layers_guard = self.layers.lock().unwrap();
        for layer in layers_guard.iter() {
            let clips = layer.clips();
            for clip in clips.iter() {
                // Get the original clip data to reapply properties
                info!("Re-applying properties for clip: {:?}", clip.name());
                
                // Force the pipeline to use composition mode
                let children = clip.children(false);
                for child in children.iter() {
                    if let Some(video_source) = child.clone().downcast::<ges::VideoSource>().ok() {
                        use gst::glib::Value;
                        
                        // Force composition by setting mixing properties
                        let _ = TrackElementExt::set_child_property(&video_source, "operator", &Value::from(0i32));
                        let _ = TrackElementExt::set_child_property(&video_source, "sizing-policy", &Value::from(0i32));
                        
                        info!("Applied composition properties to video source");
                    }
                }
            }
        }
        
        Ok(())
    }

    fn setup_video_output(&mut self, pipeline: &ges::Pipeline) -> Result<(), String> {
        // Set composition size and properties for proper video mixing
        info!("Setting up video output with composition");
        
        // Create appsink for frame extraction
        let appsink = gst::ElementFactory::make("appsink")
            .property("emit-signals", false)
            .property("sync", true)
            .property("max-buffers", 2u32)
            .property("drop", true)
            .build()
            .map_err(|e| format!("Failed to create appsink: {}", e))?;
        
        // Set caps for RGBA format with specific dimensions for composition
        let appsink = appsink.dynamic_cast::<gst_app::AppSink>()
            .map_err(|_| "Failed to cast to AppSink")?;
        
        appsink.set_caps(Some(
            &gst::Caps::builder("video/x-raw")
                .field("format", "RGBA")
                .field("width", 1920i32)
                .field("height", 1080i32)
                .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
                .build()
        ));
        
        // Set up frame callback
        let frame_handler = self.frame_handler.clone();
        let frame_callback = self.frame_callback.clone();
        
        appsink.set_callbacks(
            gst_app::AppSinkCallbacks::builder()
                .new_sample(move |appsink| {
                    if let Some(sample) = appsink.pull_sample().ok() {
                        if let Some(buffer) = sample.buffer() {
                            if let Some(caps) = sample.caps() {
                                if let Ok(video_info) = gst_video::VideoInfo::from_caps(&caps) {
                                    let width = video_info.width();
                                    let height = video_info.height();
                                    
                                    if let Ok(map) = buffer.map_readable() {
                                        let data = map.as_slice();
                                        
                                        // Get buffer from pool
                                        let mut buffer = frame_handler.get_buffer_from_pool();
                                        let required_size = (width * height * 4) as usize;
                                        
                                        if buffer.len() != required_size {
                                            buffer.resize(required_size, 0);
                                        }
                                        
                                        // Copy data
                                        buffer[..data.len().min(required_size)].copy_from_slice(&data[..data.len().min(required_size)]);
                                        
                                        // Create frame data
                                        let frame_data = FrameData {
                                            data: buffer,
                                            width,
                                            height,
                                            texture_id: None,
                                        };
                                        
                                        // Store frame
                                        frame_handler.store_frame(frame_data.clone());
                                        
                                        // Call callback if available
                                        if let Ok(callback_guard) = frame_callback.lock() {
                                            if let Some(ref callback) = *callback_guard {
                                                let _ = callback(frame_data);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Ok(gst::FlowSuccess::Ok)
                })
                .build()
        );
        
        // Connect appsink to pipeline
        pipeline.set_video_sink(Some(&appsink));
        
        Ok(())
    }

    fn query_timeline_properties(&self) {
        let timeline_guard = self.timeline.lock().unwrap();
        if let Some(timeline) = &*timeline_guard {
            // Query duration
            let duration = timeline.duration();
            let duration_ms = (duration.nseconds() / 1_000_000) as i32;
            *self.duration_ms.lock().unwrap() = Some(duration_ms);
            info!("Timeline duration: {} ms", duration_ms);
            
            // Timeline is always seekable
            *self.seekable.lock().unwrap() = true;
        }
    }

    pub fn play(&mut self) -> Result<(), String> {
        info!("Starting GES timeline playback");
        
        let pipeline_guard = self.pipeline.lock().unwrap();
        if let Some(pipeline) = &*pipeline_guard {
            pipeline.set_state(gst::State::Playing)
                .map_err(|e| format!("Failed to start playback: {:?}", e))?;
            
            *self.is_playing.lock().unwrap() = true;
            info!("Timeline playback started");
        } else {
            return Err("No timeline loaded".to_string());
        }
        
        Ok(())
    }

    pub fn pause(&mut self) -> Result<(), String> {
        info!("Pausing GES timeline playback");
        
        let pipeline_guard = self.pipeline.lock().unwrap();
        if let Some(pipeline) = &*pipeline_guard {
            pipeline.set_state(gst::State::Paused)
                .map_err(|e| format!("Failed to pause playback: {:?}", e))?;
            
            *self.is_playing.lock().unwrap() = false;
            info!("Timeline playback paused");
        } else {
            return Err("No timeline loaded".to_string());
        }
        
        Ok(())
    }

    pub fn stop(&mut self) -> Result<(), String> {
        info!("Stopping GES timeline playback");
        
        let pipeline_guard = self.pipeline.lock().unwrap();
        if let Some(pipeline) = &*pipeline_guard {
            pipeline.set_state(gst::State::Null)
                .map_err(|e| format!("Failed to stop playback: {:?}", e))?;
            
            *self.is_playing.lock().unwrap() = false;
            *self.current_position_ms.lock().unwrap() = 0;
            info!("Timeline playback stopped");
        } else {
            return Err("No timeline loaded".to_string());
        }
        
        Ok(())
    }

    pub fn seek_to_position(&mut self, position_ms: i32) -> Result<(), String> {
        let pipeline_guard = self.pipeline.lock().unwrap();
        if let Some(pipeline) = &*pipeline_guard {
            let position_ns = (position_ms as u64) * 1_000_000;
            let seek_pos = gst::ClockTime::from_nseconds(position_ns);
            
            let seek_event = gst::event::Seek::new(
                1.0,
                gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
                gst::SeekType::Set,
                seek_pos,
                gst::SeekType::None,
                gst::ClockTime::NONE,
            );
            
            if pipeline.send_event(seek_event) {
                *self.current_position_ms.lock().unwrap() = position_ms;
                debug!("Seeked to position: {} ms", position_ms);
                Ok(())
            } else {
                Err("Failed to seek timeline".to_string())
            }
        } else {
            Err("No timeline loaded".to_string())
        }
    }

    pub fn get_position_ms(&self) -> i32 {
        let pipeline_guard = self.pipeline.lock().unwrap();
        if let Some(pipeline) = &*pipeline_guard {
            if let Some(position) = pipeline.query_position::<gst::ClockTime>() {
                return (position.nseconds() / 1_000_000) as i32;
            }
        }
        
        *self.current_position_ms.lock().unwrap()
    }

    pub fn get_duration_ms(&self) -> Option<i32> {
        *self.duration_ms.lock().unwrap()
    }

    pub fn is_playing(&self) -> bool {
        *self.is_playing.lock().unwrap()
    }

    pub fn is_seekable(&self) -> bool {
        *self.seekable.lock().unwrap()
    }

    pub fn get_latest_frame(&self) -> Option<FrameData> {
        self.frame_handler.get_latest_frame()
    }

    pub fn get_latest_texture_id(&self) -> u64 {
        self.frame_handler.get_latest_texture_id()
    }

    pub fn get_texture_frame(&self) -> Option<TextureFrame> {
        self.frame_handler.get_texture_frame()
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        info!("Disposing GES timeline player");
        
        // Stop playback
        {
            let pipeline_guard = self.pipeline.lock().unwrap();
            if let Some(pipeline) = &*pipeline_guard {
                let _ = pipeline.set_state(gst::State::Null);
            }
        }
        
        // Clear resources
        *self.timeline.lock().unwrap() = None;
        *self.pipeline.lock().unwrap() = None;
        self.layers.lock().unwrap().clear();
        self.assets.lock().unwrap().clear();
        self.timeline_data = None;
        
        *self.is_playing.lock().unwrap() = false;
        *self.current_position_ms.lock().unwrap() = 0;
        
        info!("GES timeline player disposed");
        Ok(())
    }
}

impl Drop for GESTimelinePlayer {
    fn drop(&mut self) {
        let _ = self.dispose();
    }
}

impl Default for GESTimelinePlayer {
    fn default() -> Self {
        Self::new()
    }
}