use crate::audio_handler::{MediaSender, MediaData, AudioFormat, start_audio_thread};
use crate::common::types::FrameData;
use crate::video::frame_handler::FrameHandler;
use crate::video::pipeline::PipelineManager;
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_video as gst_video;
use gstreamer_app as gst_app;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use log::{info, warn, debug};
use anyhow::Result;

pub type FrameCallback = Box<dyn Fn(FrameData) -> Result<()> + Send + Sync>;

pub struct VideoPlayer {
    pub pipeline_manager: Option<PipelineManager>,
    pub frame_handler: FrameHandler,
    pub is_playing: Arc<Mutex<bool>>,
    // Audio-related fields
    pub audio_sender: Option<MediaSender>,
    // Seeking-related fields
    pub duration: Arc<Mutex<Option<u64>>>, // Duration in nanoseconds
    pub seekable: Arc<Mutex<bool>>,
    // File path for frame extraction
    pub file_path: Option<String>,
    // Frame extraction mutex to prevent concurrent operations
    pub frame_extraction_mutex: Arc<Mutex<()>>,
    frame_callback: Arc<Mutex<Option<FrameCallback>>>,
}

impl VideoPlayer {
    pub fn new() -> Self {
        // Initialize audio system
        let audio_sender = start_audio_thread();
        
        Self {
            pipeline_manager: None,
            frame_handler: FrameHandler::new(),
            is_playing: Arc::new(Mutex::new(false)),
            audio_sender: Some(audio_sender),
            duration: Arc::new(Mutex::new(None)),
            seekable: Arc::new(Mutex::new(false)),
            file_path: None,
            frame_extraction_mutex: Arc::new(Mutex::new(())),
            frame_callback: Arc::new(Mutex::new(None)),
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

    pub fn load_video(&mut self, file_path: String) -> Result<(), String> {
        // Check if file exists
        if !std::path::Path::new(&file_path).exists() {
            return Err(format!("Video file not found: {}", file_path));
        }

        info!("Loading video file: {}", file_path);

        // Store the file path for frame extraction
        self.file_path = Some(file_path.clone());

        // Create pipeline manager with shared GL context
        let mut pipeline_manager = PipelineManager::new(
            self.frame_handler.clone(),
            self.frame_callback.clone(),
        )?;

        // Load the video through pipeline manager
        pipeline_manager.create_pipeline(&file_path)?;
        
        self.pipeline_manager = Some(pipeline_manager);
        
        info!("Pipeline created successfully, waiting for pipeline to be ready...");
        
        // Wait for pipeline to be ready for playback commands
        self.wait_for_pipeline_ready()?;
        
        // Query duration and seekability after pipeline is ready
        self.query_duration_and_seekability();
        
        // Extract and display the first frame so video content is visible immediately
        info!("Extracting first frame for immediate display...");
        if let Err(e) = self.extract_frame_at_position(0.0) {
            warn!("Failed to extract first frame: {}", e);
            // Continue anyway - video loading was successful even if first frame extraction failed
        } else {
            info!("First frame extracted successfully and ready for display");
        }
        
        info!("Video loading completed - pipeline ready for playback commands");
        Ok(())
    }

    /// Wait for the pipeline to be ready for playback commands
    /// This ensures isSeekable() returns true before load_video() completes
    fn wait_for_pipeline_ready(&self) -> Result<(), String> {
        if let Some(pipeline_manager) = &self.pipeline_manager {
            if let Some(pipeline) = &pipeline_manager.pipeline {
                info!("Waiting for pipeline to reach PAUSED state for readiness...");
                
                // Set pipeline to PAUSED state to make it ready for commands
                if let Err(e) = pipeline.set_state(gst::State::Paused) {
                    return Err(format!("Failed to set pipeline to PAUSED: {:?}", e));
                }
                
                // Wait for PAUSED state with timeout
                let timeout = Duration::from_secs(5); // 5 second timeout
                let start_time = std::time::Instant::now();
                
                while start_time.elapsed() < timeout {
                    let (_, current_state, pending_state) = pipeline.state(Some(gst::ClockTime::from_nseconds(100_000_000))); // 100ms query timeout
                    
                    if current_state == gst::State::Paused && pending_state == gst::State::VoidPending {
                        info!("Pipeline successfully reached PAUSED state and is ready");
                        return Ok(());
                    }
                    
                    // If there's an error state, fail immediately
                    if current_state == gst::State::Null {
                        return Err("Pipeline entered NULL state during initialization".to_string());
                    }
                    
                    // Small delay before next check
                    std::thread::sleep(Duration::from_millis(50));
                }
                
                return Err(format!("Timeout waiting for pipeline to be ready (current state: {:?})", 
                          pipeline.state(Some(gst::ClockTime::from_nseconds(0))).1));
            }
        }
        
        Err("No pipeline available to wait for".to_string())
    }

    pub fn play(&mut self) -> Result<(), String> {
        if let Some(pipeline_manager) = &mut self.pipeline_manager {
            let result = pipeline_manager.play()?;
            
            // Instead of blocking wait, just try a quick state check
            if let Some(pipeline) = &pipeline_manager.pipeline {
                // Quick non-blocking state check
                let (_, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
                
                // If already playing, update state immediately
                if current_state == gst::State::Playing {
                    *self.is_playing.lock().unwrap() = true;
                    info!("Play command completed immediately - pipeline state: {:?}", current_state);
                } else {
                    // For async state changes, set playing optimistically
                    // The actual state will be synced later via sync_playing_state()
                    *self.is_playing.lock().unwrap() = true;
                    info!("Play command initiated - pipeline transitioning to playing state");
                }
            }
            
            // Duration and seekability already queried during load_video()
            // No need to query again here
            
            // Initialize audio system only if we're actually playing
            if self.is_playing() {
                if let Some(ref audio_sender) = self.audio_sender {
                    let audio_format = AudioFormat {
                        sample_rate: 44100,
                        channels: 2,
                        bytes_per_sample: 2,
                    };
                    
                    if let Err(e) = audio_sender.send(MediaData::AudioFormat(audio_format)) {
                        warn!("Failed to send audio format: {}", e);
                    }
                    
                    if let Err(e) = audio_sender.send(MediaData::Resume) {
                        warn!("Failed to send resume command: {}", e);
                    }
                }
            }
            
            Ok(result)
        } else {
            Err("No video loaded".to_string())
        }
    }

    pub fn pause(&mut self) -> Result<(), String> {
        if let Some(pipeline_manager) = &mut self.pipeline_manager {
            // Send pause command to audio system first
            if let Some(ref audio_sender) = self.audio_sender {
                if let Err(e) = audio_sender.send(MediaData::Pause) {
                    warn!("Failed to send pause command to audio system: {}", e);
                }
            }
            
            let result = pipeline_manager.pause()?;
            
            // Instead of blocking wait, just try a quick state check
            if let Some(pipeline) = &pipeline_manager.pipeline {
                // Quick non-blocking state check
                let (_, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
                
                // Update state based on current pipeline state
                *self.is_playing.lock().unwrap() = current_state == gst::State::Playing;
                
                info!("Pause command completed - pipeline state: {:?}, internal state: {}", 
                      current_state, self.is_playing());
            }
            
            Ok(result)
        } else {
            Err("No video loaded".to_string())
        }
    }

    pub fn stop(&mut self) -> Result<(), String> {
        if let Some(pipeline_manager) = &mut self.pipeline_manager {
            // Stop audio playback
            if let Some(ref audio_sender) = self.audio_sender {
                if let Err(e) = audio_sender.send(MediaData::Stop) {
                    warn!("Failed to send stop signal to audio system: {}", e);
                }
            }
            
            let result = pipeline_manager.stop()?;
            *self.is_playing.lock().unwrap() = false;
            Ok(result)
        } else {
            Err("No video loaded".to_string())
        }
    }

    pub fn get_video_dimensions(&self) -> (i32, i32) {
        self.frame_handler.get_video_dimensions()
    }

    pub fn is_playing(&self) -> bool {
        // Primarily use internal state to avoid blocking calls
        let internal_state = *self.is_playing.lock().unwrap();
        
        // Only do expensive pipeline checks occasionally or when there's a reason to doubt the state
        // Most UI calls should just use the cached internal state for performance
        internal_state
    }

    pub fn get_latest_frame(&self) -> Option<crate::common::types::FrameData> {
        self.frame_handler.get_latest_frame()
    }
    
    /// Get the latest texture ID for GPU-based rendering
    pub fn get_latest_texture_id(&self) -> u64 {
        self.frame_handler.get_latest_texture_id()
    }
    
    /// Get texture frame data for GPU-based rendering
    pub fn get_texture_frame(&self) -> Option<crate::common::types::TextureFrame> {
        self.frame_handler.get_texture_frame()
    }

    pub fn has_audio(&self) -> bool {
        false
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        info!("Disposing VideoPlayer");
        
        // Stop audio playback
        if let Some(ref audio_sender) = self.audio_sender {
            if let Err(e) = audio_sender.send(MediaData::Stop) {
                warn!("Failed to send stop signal during dispose: {}", e);
            }
        }
        
        if let Some(pipeline_manager) = &mut self.pipeline_manager {
            pipeline_manager.dispose()?;
        }
        
        self.pipeline_manager = None;
        *self.is_playing.lock().unwrap() = false;
        
        info!("VideoPlayer disposed successfully");
        Ok(())
    }

    // SEEKING FUNCTIONALITY
    
    fn query_duration_and_seekability(&self) {
        if let Some(pipeline_manager) = &self.pipeline_manager {
            if let Some(pipeline) = &pipeline_manager.pipeline {
                // Query duration
                if let Some(duration) = pipeline.query_duration::<gst::ClockTime>() {
                    let duration_ns = duration.nseconds();
                    info!("Video duration: {} seconds", duration_ns as f64 / 1_000_000_000.0);
                    *self.duration.lock().unwrap() = Some(duration_ns);
                } else {
                    warn!("Could not query video duration");
                }
                
                // Query seekability
                let mut query = gst::query::Seeking::new(gst::Format::Time);
                if pipeline.query(&mut query) {
                    let (seekable, _, _) = query.result();
                    info!("Video is seekable: {}", seekable);
                    *self.seekable.lock().unwrap() = seekable;
                } else {
                    warn!("Could not query video seekability");
                }
            }
        }
    }

    pub fn get_duration_seconds(&self) -> f64 {
        if let Ok(duration_guard) = self.duration.lock() {
            if let Some(duration_ns) = *duration_guard {
                return duration_ns as f64 / 1_000_000_000.0;
            }
        }
        0.0
    }

    pub fn get_position_seconds(&self) -> f64 {
        if let Some(pipeline_manager) = &self.pipeline_manager {
            if let Some(pipeline) = &pipeline_manager.pipeline {
                if let Some(position) = pipeline.query_position::<gst::ClockTime>() {
                    let position_ns = position.nseconds();
                    return position_ns as f64 / 1_000_000_000.0;
                }
            }
        }
        0.0
    }

    pub fn is_seekable(&self) -> bool {
        *self.seekable.lock().unwrap()
    }

    /// Seek to position and manage pause/resume state
    /// Used when releasing drag - handles pause before seek and resume after
    pub fn seek_and_pause_control(&mut self, seconds: f64, was_playing_before: bool) -> Result<f64, String> {
        if !self.is_seekable() {
            return Err("Video is not seekable".to_string());
        }

        let mut final_position = seconds;

        // Scope the pipeline operations to release the borrow before frame extraction
        {
            if let Some(pipeline_manager) = &self.pipeline_manager {
                if let Some(pipeline) = &pipeline_manager.pipeline {
                    let position_ns = (seconds * 1_000_000_000.0) as u64;
                    let seek_pos = gst::ClockTime::from_nseconds(position_ns);
                    
                    info!("Seeking to final position: {} seconds (was_playing: {})", seconds, was_playing_before);
                    
                    // Check current pipeline state
                    let (_, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
                    info!("Current pipeline state before seek: {:?}", current_state);
                    
                    // STEP 1: Only force pause if not already paused
                    // This avoids unnecessary state changes that might cause frame advancement
                    if current_state != gst::State::Paused {
                        info!("Pipeline not paused, forcing pause before seek");
                        let _ = pipeline.set_state(gst::State::Paused);
                        
                        // Wait for pause to actually take effect
                        let mut attempts = 0;
                        while attempts < 10 {
                            std::thread::sleep(Duration::from_millis(50));
                            let (_, state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
                            if state == gst::State::Paused {
                                break;
                            }
                            attempts += 1;
                        }
                    } else {
                        info!("Pipeline already paused, skipping pause operation");
                    }
                    
                    // Update internal state and ensure audio is paused
                    *self.is_playing.lock().unwrap() = false;
                    if let Some(ref audio_sender) = self.audio_sender {
                        let _ = audio_sender.send(MediaData::Pause);
                    }
                    
                    info!("Pipeline prepared for seek");
                    
                    // STEP 2: Perform the seek with minimal pipeline disruption
                    let seek_event = gst::event::Seek::new(
                        1.0,
                        // Always use FLUSH to avoid potential deadlocks with paused pipelines
                        gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
                        gst::SeekType::Set,
                        seek_pos,
                        gst::SeekType::None,
                        gst::ClockTime::NONE,
                    );
                    
                    if pipeline.send_event(seek_event) {
                        info!("Final seek event sent successfully");
                        
                        // STEP 3: Wait for seek to complete
                        let mut attempts = 0;
                        
                        while attempts < 15 {
                            std::thread::sleep(Duration::from_millis(20));
                            if let Some(current_pos) = pipeline.query_position::<gst::ClockTime>() {
                                let current_seconds = current_pos.nseconds() as f64 / 1_000_000_000.0;
                                let diff = (current_seconds - seconds).abs();
                                
                                final_position = current_seconds;
                                
                                // Accept if we're within 100ms
                                if diff < 0.1 {
                                    info!("Final seek completed: {} seconds (diff: {}ms)", current_seconds, diff * 1000.0);
                                    break;
                                }
                            }
                            attempts += 1;
                        }
                        
                        // Check if seek timed out
                        if attempts >= 15 {
                            warn!("Seek operation timed out, proceeding with fallback position");
                            final_position = seconds; // Use target position as fallback
                        }
                        
                        // STEP 4: Handle final state based on what was requested
                        if was_playing_before {
                            info!("Resuming playback after seek");
                            if let Err(e) = pipeline.set_state(gst::State::Playing) {
                                warn!("Failed to resume playback: {}", e);
                            } else {
                                // Wait for playing state to be established
                                let mut attempts = 0;
                                while attempts < 10 {
                                    std::thread::sleep(Duration::from_millis(50));
                                    let (_, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
                                    if current_state == gst::State::Playing {
                                        break;
                                    }
                                    attempts += 1;
                                }
                                
                                // Update internal state only after pipeline confirms playing
                                let (_, final_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
                                *self.is_playing.lock().unwrap() = final_state == gst::State::Playing;
                                
                                info!("Resume completed - pipeline state: {:?}, internal state: {}", 
                                      final_state, self.is_playing());
                                
                                // Resume audio if we're actually playing
                                if self.is_playing() {
                                    if let Some(ref audio_sender) = self.audio_sender {
                                        if let Err(e) = audio_sender.send(MediaData::Resume) {
                                            warn!("Failed to resume audio: {}", e);
                                        }
                                    }
                                }
                            }
                        } else {
                            info!("Staying paused after seek - minimal operations to avoid freeze");
                            
                            // For paused state, do minimal operations to avoid deadlock
                            *self.is_playing.lock().unwrap() = false;
                            
                            // Just ensure we're paused without additional operations that might hang
                            let (_, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
                            if current_state != gst::State::Paused {
                                warn!("Pipeline not paused after seek (state: {:?}), will NOT force pause to avoid hang", current_state);
                                // Don't force pause here as it might cause deadlock
                            }
                            
                            info!("Staying paused - final pipeline state: {:?}, internal state: {}", 
                                  current_state, self.is_playing());
                        }
                    } else {
                        return Err("Failed to send final seek event".to_string());
                    }
                } else {
                    return Err("No pipeline available".to_string());
                }
            } else {
                return Err("No video loaded".to_string());
            }
        }

        // STEP 3.5: Extract frame at the seek position to update texture
        // This is done after the pipeline operations to avoid borrowing conflicts
        info!("Extracting frame after seek to update texture");
        if let Err(e) = self.extract_frame_after_seek(final_position) {
            warn!("Failed to extract frame after seek: {}", e);
            // Continue anyway - seek was successful even if frame extraction failed
        }

        Ok(final_position)
    }

    /// Extract frame after seek to update texture without disrupting main pipeline
    /// This is a lighter version of extract_frame_at_position optimized for post-seek frame updates
    fn extract_frame_after_seek(&mut self, seconds: f64) -> Result<(), String> {
        // Try to acquire the frame extraction lock with timeout to prevent deadlocks
        let _lock = match self.frame_extraction_mutex.try_lock() {
            Ok(lock) => lock,
            Err(_) => {
                warn!("Frame extraction already in progress during post-seek, skipping");
                return Ok(()); // Return success to avoid blocking the UI
            }
        };

        // Get the file path from stored value
        let file_path = match &self.file_path {
            Some(path) => path.clone(),
            None => return Err("No video file path available".to_string()),
        };

        debug!("Extracting frame after seek at {} seconds from {}", seconds, file_path);

        // Create a temporary pipeline just for frame extraction
        let temp_pipeline = gst::Pipeline::new();
        
        // Create elements for temporary pipeline
        let source = gst::ElementFactory::make("filesrc")
            .property("location", &file_path)
            .build()
            .map_err(|e| format!("Failed to create temp filesrc: {}", e))?;

        let decodebin = gst::ElementFactory::make("decodebin")
            .build()
            .map_err(|e| format!("Failed to create temp decodebin: {}", e))?;

        let videoconvert = gst::ElementFactory::make("videoconvert")
            .build()
            .map_err(|e| format!("Failed to create temp videoconvert: {}", e))?;

        let videoscale = gst::ElementFactory::make("videoscale")
            .build()
            .map_err(|e| format!("Failed to create temp videoscale: {}", e))?;

        let appsink = gst::ElementFactory::make("appsink")
            .property("emit-signals", false) // Don't use callbacks for temp pipeline
            .property("sync", false)
            .property("max-buffers", 1u32)
            .property("drop", true) // Drop old frames to avoid buildup
            .build()
            .map_err(|e| format!("Failed to create temp appsink: {}", e))?;

        // Add elements to temp pipeline
        temp_pipeline.add_many(&[&source, &decodebin, &videoconvert, &videoscale, &appsink])
            .map_err(|e| format!("Failed to add elements to temp pipeline: {}", e))?;

        // Link static elements
        source.link(&decodebin)
            .map_err(|e| format!("Failed to link source to decodebin in temp pipeline: {}", e))?;

        videoconvert.link(&videoscale)
            .map_err(|e| format!("Failed to link videoconvert to videoscale in temp pipeline: {}", e))?;

        videoscale.link(&appsink)
            .map_err(|e| format!("Failed to link videoscale to appsink in temp pipeline: {}", e))?;

        // Configure appsink caps to match main pipeline
        let appsink = appsink.dynamic_cast::<gst_app::AppSink>().unwrap();
        appsink.set_caps(Some(
            &gst::Caps::builder("video/x-raw")
                .field("format", "RGBA")
                .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
                .build()
        ));

        // Set up decodebin pad-added callback for temp pipeline
        let videoconvert_clone = videoconvert.clone();
        decodebin.connect_pad_added(move |_src, src_pad| {
            let src_pad_caps = src_pad.current_caps().unwrap();
            let src_pad_struct = src_pad_caps.structure(0).unwrap();
            let media_type = src_pad_struct.name();
            
            if media_type.starts_with("video/") {
                if let Some(sink_pad) = videoconvert_clone.static_pad("sink") {
                    if !sink_pad.is_linked() {
                        let _ = src_pad.link(&sink_pad);
                    }
                }
            }
        });

        // Set timeout for the entire operation (shorter for post-seek)
        let start_time = std::time::Instant::now();
        let max_duration = Duration::from_millis(800); // 800ms timeout for post-seek

        // Start temp pipeline with timeout check
        if let Err(e) = temp_pipeline.set_state(gst::State::Playing) {
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err(format!("Failed to start temp pipeline: {:?}", e));
        }

        // Wait for pipeline to be ready with timeout (shorter for post-seek)
        let mut ready_attempts = 0;
        while ready_attempts < 8 && start_time.elapsed() < max_duration {
            std::thread::sleep(Duration::from_millis(10));
            let (_, current_state, _) = temp_pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
            if current_state == gst::State::Playing {
                break;
            }
            ready_attempts += 1;
        }

        if start_time.elapsed() >= max_duration {
            warn!("Post-seek temp pipeline setup timeout, cleaning up");
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("Post-seek pipeline setup timeout".to_string());
        }

        // Seek to target position
        let position_ns = (seconds * 1_000_000_000.0) as u64;
        let seek_pos = gst::ClockTime::from_nseconds(position_ns);
        
        let seek_event = gst::event::Seek::new(
            1.0,
            gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
            gst::SeekType::Set,
            seek_pos,
            gst::SeekType::None,
            gst::ClockTime::NONE,
        );

        if !temp_pipeline.send_event(seek_event) {
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("Failed to seek temp pipeline".to_string());
        }

        // Wait for seek to complete with timeout (shorter for post-seek)
        let mut seek_attempts = 0;
        while seek_attempts < 10 && start_time.elapsed() < max_duration {
            std::thread::sleep(Duration::from_millis(8));
            seek_attempts += 1;
        }

        if start_time.elapsed() >= max_duration {
            warn!("Post-seek temp pipeline seek timeout, cleaning up");
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("Post-seek pipeline seek timeout".to_string());
        }

        // Pause pipeline to get exact frame
        if let Err(e) = temp_pipeline.set_state(gst::State::Paused) {
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err(format!("Failed to pause temp pipeline: {:?}", e));
        }

        // Wait for pipeline to pause with timeout (shorter for post-seek)
        let mut pause_attempts = 0;
        while pause_attempts < 10 && start_time.elapsed() < max_duration {
            std::thread::sleep(Duration::from_millis(8));
            let (_, current_state, _) = temp_pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
            if current_state == gst::State::Paused {
                break;
            }
            pause_attempts += 1;
        }

        if start_time.elapsed() >= max_duration {
            warn!("Post-seek temp pipeline pause timeout, cleaning up");
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("Post-seek pipeline pause timeout".to_string());
        }

        // Extract the frame with timeout using try_pull_sample
        let sample = match appsink.try_pull_sample(gst::ClockTime::from_nseconds(200_000_000)) { // 200ms in nanoseconds
            Some(sample) => sample,
            None => {
                temp_pipeline.set_state(gst::State::Null).ok();
                return Err("No sample available from post-seek temp pipeline".to_string());
            }
        };

        if let Some(buffer) = sample.buffer() {
            if let Some(caps) = sample.caps() {
                if let Ok(video_info) = gst_video::VideoInfo::from_caps(&caps) {
                    let width = video_info.width();
                    let height = video_info.height();
                    
                    if let Ok(map) = buffer.map_readable() {
                        let data = map.as_slice();
                        
                        // Get buffer from pool instead of allocating new Vec
                        let mut buffer = self.frame_handler.get_buffer_from_pool();
                        let required_size = (width * height * 4) as usize;
                        
                        // Resize buffer if needed
                        if buffer.len() != required_size {
                            buffer.resize(required_size, 0);
                        }
                        
                        // Copy data to reused buffer
                        buffer[..data.len().min(required_size)].copy_from_slice(&data[..data.len().min(required_size)]);
                        
                        // Create frame data and store it in the main frame handler
                        let frame_data = crate::common::types::FrameData {
                            data: buffer,
                            width,
                            height,
                            texture_id: None,
                        };
                        
                        // Store the extracted frame in the main frame handler
                        // This will be picked up by Flutter on the next getLatestFrame() call
                        self.frame_handler.store_frame(frame_data);
                        
                        debug!("Successfully extracted and stored post-seek frame at {} seconds ({}x{}) in {}ms", 
                               seconds, width, height, start_time.elapsed().as_millis());
                    } else {
                        temp_pipeline.set_state(gst::State::Null).ok();
                        return Err("Failed to map buffer from post-seek temp pipeline".to_string());
                    }
                } else {
                    temp_pipeline.set_state(gst::State::Null).ok();
                    return Err("Failed to get video info from post-seek temp pipeline".to_string());
                }
            } else {
                temp_pipeline.set_state(gst::State::Null).ok();
                return Err("No caps available from post-seek temp pipeline".to_string());
            }
        } else {
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("No buffer available from post-seek temp pipeline".to_string());
        }

        // Clean up temp pipeline
        temp_pipeline.set_state(gst::State::Null).ok();
        
        Ok(())
    }

    pub fn get_frame_rate(&self) -> f64 {
        self.frame_handler.get_frame_rate()
    }

    pub fn seek_to_frame(&mut self, frame_number: u64) -> Result<f64, String> {
        let frame_rate = self.get_frame_rate();
        let seconds = frame_number as f64 / frame_rate;
        self.seek_and_pause_control(seconds, self.is_playing())
    }

    pub fn get_current_frame_number(&self) -> u64 {
        let position_seconds = self.get_position_seconds();
        self.frame_handler.get_current_frame_number(position_seconds)
    }

    pub fn get_total_frames(&self) -> u64 {
        let duration_seconds = self.get_duration_seconds();
        self.frame_handler.get_total_frames(duration_seconds)
    }

    /// Synchronize and return the actual playing state
    /// This checks both internal state and pipeline state and resolves discrepancies
    pub fn sync_playing_state(&mut self) -> bool {
        let internal_state = *self.is_playing.lock().unwrap();
        
        if let Some(pipeline_manager) = &self.pipeline_manager {
            if let Some(pipeline) = &pipeline_manager.pipeline {
                let (_, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
                let pipeline_playing = current_state == gst::State::Playing;
                
                if internal_state != pipeline_playing {
                    warn!("State synchronization - Internal: {}, Pipeline: {:?} - using pipeline state", 
                          internal_state, current_state);
                    *self.is_playing.lock().unwrap() = pipeline_playing;
                    return pipeline_playing;
                }
                
                return pipeline_playing;
            }
        }
        
        // Fallback to internal state if pipeline not available
        internal_state
    }

    /// Extract and set frame at specific position for preview without seeking main pipeline
    /// This creates a temporary pipeline to extract the frame and updates the texture display
    pub fn extract_frame_at_position(&mut self, seconds: f64) -> Result<(), String> {
        if !self.is_seekable() {
            return Err("Video is not seekable".to_string());
        }

        // Try to acquire the frame extraction lock with timeout to prevent deadlocks
        let _lock = match self.frame_extraction_mutex.try_lock() {
            Ok(lock) => lock,
            Err(_) => {
                warn!("Frame extraction already in progress, skipping");
                return Ok(()); // Return success to avoid blocking the UI
            }
        };

        // Get the file path from stored value
        let file_path = match &self.file_path {
            Some(path) => path.clone(),
            None => return Err("No video file path available".to_string()),
        };

        debug!("Extracting frame at {} seconds from {}", seconds, file_path);

        // Create a temporary pipeline just for frame extraction
        let temp_pipeline = gst::Pipeline::new();
        
        // Create elements for temporary pipeline
        let source = gst::ElementFactory::make("filesrc")
            .property("location", &file_path)
            .build()
            .map_err(|e| format!("Failed to create temp filesrc: {}", e))?;

        let decodebin = gst::ElementFactory::make("decodebin")
            .build()
            .map_err(|e| format!("Failed to create temp decodebin: {}", e))?;

        let videoconvert = gst::ElementFactory::make("videoconvert")
            .build()
            .map_err(|e| format!("Failed to create temp videoconvert: {}", e))?;

        let videoscale = gst::ElementFactory::make("videoscale")
            .build()
            .map_err(|e| format!("Failed to create temp videoscale: {}", e))?;

        let appsink = gst::ElementFactory::make("appsink")
            .property("emit-signals", false) // Don't use callbacks for temp pipeline
            .property("sync", false)
            .property("max-buffers", 1u32)
            .property("drop", true) // Drop old frames to avoid buildup
            .build()
            .map_err(|e| format!("Failed to create temp appsink: {}", e))?;

        // Add elements to temp pipeline
        temp_pipeline.add_many(&[&source, &decodebin, &videoconvert, &videoscale, &appsink])
            .map_err(|e| format!("Failed to add elements to temp pipeline: {}", e))?;

        // Link static elements
        source.link(&decodebin)
            .map_err(|e| format!("Failed to link source to decodebin in temp pipeline: {}", e))?;

        videoconvert.link(&videoscale)
            .map_err(|e| format!("Failed to link videoconvert to videoscale in temp pipeline: {}", e))?;

        videoscale.link(&appsink)
            .map_err(|e| format!("Failed to link videoscale to appsink in temp pipeline: {}", e))?;

        // Configure appsink caps to match main pipeline
        let appsink = appsink.dynamic_cast::<gst_app::AppSink>().unwrap();
        appsink.set_caps(Some(
            &gst::Caps::builder("video/x-raw")
                .field("format", "RGBA")
                .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
                .build()
        ));

        // Set up decodebin pad-added callback for temp pipeline
        let videoconvert_clone = videoconvert.clone();
        decodebin.connect_pad_added(move |_src, src_pad| {
            let src_pad_caps = src_pad.current_caps().unwrap();
            let src_pad_struct = src_pad_caps.structure(0).unwrap();
            let media_type = src_pad_struct.name();
            
            if media_type.starts_with("video/") {
                if let Some(sink_pad) = videoconvert_clone.static_pad("sink") {
                    if !sink_pad.is_linked() {
                        let _ = src_pad.link(&sink_pad);
                    }
                }
            }
        });

        // Set timeout for the entire operation
        let start_time = std::time::Instant::now();
        let max_duration = Duration::from_millis(1000); // 1 second timeout

        // Start temp pipeline with timeout check
        if let Err(e) = temp_pipeline.set_state(gst::State::Playing) {
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err(format!("Failed to start temp pipeline: {:?}", e));
        }

        // Wait for pipeline to be ready with timeout
        let mut ready_attempts = 0;
        while ready_attempts < 10 && start_time.elapsed() < max_duration {
            std::thread::sleep(Duration::from_millis(10));
            let (_, current_state, _) = temp_pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
            if current_state == gst::State::Playing {
                break;
            }
            ready_attempts += 1;
        }

        if start_time.elapsed() >= max_duration {
            warn!("Temp pipeline setup timeout, cleaning up");
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("Pipeline setup timeout".to_string());
        }

        // Seek to target position
        let position_ns = (seconds * 1_000_000_000.0) as u64;
        let seek_pos = gst::ClockTime::from_nseconds(position_ns);
        
        let seek_event = gst::event::Seek::new(
            1.0,
            gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
            gst::SeekType::Set,
            seek_pos,
            gst::SeekType::None,
            gst::ClockTime::NONE,
        );

        if !temp_pipeline.send_event(seek_event) {
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("Failed to seek temp pipeline".to_string());
        }

        // Wait for seek to complete with timeout
        let mut seek_attempts = 0;
        while seek_attempts < 15 && start_time.elapsed() < max_duration {
            std::thread::sleep(Duration::from_millis(10));
            seek_attempts += 1;
        }

        if start_time.elapsed() >= max_duration {
            warn!("Temp pipeline seek timeout, cleaning up");
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("Pipeline seek timeout".to_string());
        }

        // Pause pipeline to get exact frame
        if let Err(e) = temp_pipeline.set_state(gst::State::Paused) {
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err(format!("Failed to pause temp pipeline: {:?}", e));
        }

        // Wait for pipeline to pause with timeout
        let mut pause_attempts = 0;
        while pause_attempts < 15 && start_time.elapsed() < max_duration {
            std::thread::sleep(Duration::from_millis(10));
            let (_, current_state, _) = temp_pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
            if current_state == gst::State::Paused {
                break;
            }
            pause_attempts += 1;
        }

        if start_time.elapsed() >= max_duration {
            warn!("Temp pipeline pause timeout, cleaning up");
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("Pipeline pause timeout".to_string());
        }

        // Extract the frame with timeout using try_pull_sample
        let sample = match appsink.try_pull_sample(gst::ClockTime::from_nseconds(200_000_000)) { // 200ms in nanoseconds
            Some(sample) => sample,
            None => {
                temp_pipeline.set_state(gst::State::Null).ok();
                return Err("No sample available from temp pipeline".to_string());
            }
        };

        if let Some(buffer) = sample.buffer() {
            if let Some(caps) = sample.caps() {
                if let Ok(video_info) = gst_video::VideoInfo::from_caps(&caps) {
                    let width = video_info.width();
                    let height = video_info.height();
                    
                    if let Ok(map) = buffer.map_readable() {
                        let data = map.as_slice();
                        
                        // Get buffer from pool instead of allocating new Vec
                        let mut buffer = self.frame_handler.get_buffer_from_pool();
                        let required_size = (width * height * 4) as usize;
                        
                        // Resize buffer if needed
                        if buffer.len() != required_size {
                            buffer.resize(required_size, 0);
                        }
                        
                        // Copy data to reused buffer
                        buffer[..data.len().min(required_size)].copy_from_slice(&data[..data.len().min(required_size)]);
                        
                        // Create frame data and store it in the main frame handler
                        let frame_data = crate::common::types::FrameData {
                            data: buffer,
                            width,
                            height,
                            texture_id: None,
                        };
                        
                        // Store the extracted frame in the main frame handler
                        // This will be picked up by Flutter on the next getLatestFrame() call
                        self.frame_handler.store_frame(frame_data);
                        
                        debug!("Successfully extracted and stored frame at {} seconds ({}x{}) in {}ms", 
                               seconds, width, height, start_time.elapsed().as_millis());
                    } else {
                        temp_pipeline.set_state(gst::State::Null).ok();
                        return Err("Failed to map buffer from temp pipeline".to_string());
                    }
                } else {
                    temp_pipeline.set_state(gst::State::Null).ok();
                    return Err("Failed to get video info from temp pipeline".to_string());
                }
            } else {
                temp_pipeline.set_state(gst::State::Null).ok();
                return Err("No caps available from temp pipeline".to_string());
            }
        } else {
            temp_pipeline.set_state(gst::State::Null).ok();
            return Err("No buffer available from temp pipeline".to_string());
        }

        // Clean up temp pipeline
        temp_pipeline.set_state(gst::State::Null).ok();
        
        Ok(())
    }
}

impl Drop for VideoPlayer {
    fn drop(&mut self) {
        info!("Cleaning up VideoPlayer");
        let _ = self.dispose();
        std::thread::sleep(Duration::from_millis(50));
    }
}

impl Default for VideoPlayer {
    fn default() -> Self {
        Self::new()
    }
} 