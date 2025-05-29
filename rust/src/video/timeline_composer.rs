use gstreamer as gst;
use gstreamer_editing_services as ges;
use gstreamer_editing_services::prelude::*;
use gstreamer_video as gst_video;
use gstreamer_app as gst_app;
use log::{info, debug};
use std::sync::mpsc;
use std::collections::HashMap;
use std::thread::{self, JoinHandle};
use crate::video::frame_handler::FrameHandler;
use crate::common::types::FrameData;

#[derive(Debug, Clone, PartialEq)]
pub struct TimelineClipData {
    pub id: i32,
    pub track_id: i32,
    pub source_path: String,
    pub start_time_on_track_ms: i64,
    pub end_time_on_track_ms: i64,
    pub start_time_in_source_ms: i64,
    pub end_time_in_source_ms: i64,
    pub source_duration_ms: i64,
}

enum TimelineCommand {
    UpdateTimeline {
        clips: Vec<TimelineClipData>,
        response: mpsc::Sender<Result<(), String>>,
    },
    Play {
        response: mpsc::Sender<Result<(), String>>,
    },
    Pause {
        response: mpsc::Sender<Result<(), String>>,
    },
    Seek {
        position_ms: i64,
        response: mpsc::Sender<Result<(), String>>,
    },
    GetPosition {
        response: mpsc::Sender<i64>,
    },
    GetDuration {
        response: mpsc::Sender<i64>,
    },
    IsPlaying {
        response: mpsc::Sender<bool>,
    },
    SetTexturePtr {
        ptr: i64,
    },
    Dispose,
}

struct TimelineWorker {
    timeline: Option<ges::Timeline>,
    pipeline: Option<gst::Pipeline>,
    frame_handler: FrameHandler,
    clips: Vec<TimelineClipData>,
    is_playing: bool,
}

impl TimelineWorker {
    fn new(frame_handler: FrameHandler) -> Self {
        info!("Creating TimelineWorker with frame handler");
        
        // Initialize GES - this must happen on the worker thread
        info!("Initializing GStreamer Editing Services...");
        if let Err(e) = ges::init() {
            panic!("Failed to initialize GStreamer Editing Services: {:?}", e);
        }
        
        info!("GStreamer Editing Services initialized successfully on worker thread");
        
        // Test basic GES functionality to verify it works on this thread
        info!("Testing basic GES functionality...");
        match std::panic::catch_unwind(|| {
            let test_timeline = ges::Timeline::new_audio_video();
            let test_layer = test_timeline.append_layer();
            test_layer.set_priority(0);
            info!("Basic GES test passed - timeline and layer creation successful");
        }) {
            Ok(()) => {
                info!("GES functionality test completed successfully");
            }
            Err(e) => {
                log::error!("GES functionality test failed: {:?}", e);
                panic!("GES is not working properly on worker thread");
            }
        }
        
        Self {
            timeline: None,
            pipeline: None,
            frame_handler,
            clips: Vec::new(),
            is_playing: false,
        }
    }

    fn update_timeline(&mut self, clips: Vec<TimelineClipData>) -> Result<(), String> {
        info!("Updating timeline with {} clips on GES thread", clips.len());
        
        // Check if clips actually changed to avoid unnecessary rebuilds
        if clips == self.clips {
            debug!("Clips unchanged, skipping timeline rebuild");
            return Ok(());
        }
        
        let start_time = std::time::Instant::now();
        
        // Store clips for future reference
        self.clips = clips;
        
        // If no clips, clear the pipeline
        if self.clips.is_empty() {
            info!("No clips provided, clearing timeline");
            self.pipeline = None;
            self.timeline = None;
            return Ok(());
        }
        
        // Log each clip for debugging
        for clip in &self.clips {
            debug!("Processing clip {}: {} (track {}, {}ms-{}ms)", 
                   clip.id, clip.source_path, clip.track_id,
                   clip.start_time_on_track_ms, clip.end_time_on_track_ms);
        }
        
        // Validate clips for overlaps within the same track
        debug!("Validating clips...");
        if let Err(e) = self.validate_clips(&self.clips) {
            log::error!("Clip validation failed: {}", e);
            return Err(e);
        }
        debug!("Clip validation passed");
        
        // Create new timeline - this MUST happen on the GES thread
        debug!("Creating new GES timeline...");
        let timeline = match std::panic::catch_unwind(|| {
            ges::Timeline::new_audio_video()
        }) {
            Ok(timeline) => {
                debug!("Created new GES timeline successfully");
                timeline
            }
            Err(e) => {
                log::error!("Failed to create GES timeline: {:?}", e);
                return Err("Failed to create GES timeline".to_string());
            }
        };
        
        // Sort clips by track and start time
        let mut sorted_clips = self.clips.clone();
        sorted_clips.sort_by(|a, b| {
            let track_cmp = a.track_id.cmp(&b.track_id);
            if track_cmp == std::cmp::Ordering::Equal {
                a.start_time_on_track_ms.cmp(&b.start_time_on_track_ms)
            } else {
                track_cmp
            }
        });

        // Group clips by track
        let mut tracks: HashMap<i32, Vec<&TimelineClipData>> = HashMap::new();
        for clip in &sorted_clips {
            tracks.entry(clip.track_id).or_insert_with(Vec::new).push(clip);
        }

        // Create layers for each track
        for (track_id, track_clips) in tracks {
            debug!("Creating layer for track {} with {} clips", track_id, track_clips.len());
            
            let layer = match std::panic::catch_unwind(|| {
                timeline.append_layer()
            }) {
                Ok(layer) => {
                    debug!("Successfully created layer for track {}", track_id);
                    layer
                }
                Err(e) => {
                    log::error!("Failed to create layer for track {}: {:?}", track_id, e);
                    return Err(format!("Failed to create layer for track {}", track_id));
                }
            };
            
            if let Err(e) = std::panic::catch_unwind(|| {
                layer.set_priority(track_id as u32);
            }) {
                log::error!("Failed to set priority for track {}: {:?}", track_id, e);
                return Err(format!("Failed to set priority for track {}", track_id));
            }
            debug!("Set priority {} for track {}", track_id, track_id);

            // Add clips to this layer
            for clip_data in track_clips {
                debug!("About to add clip {} to track {}", clip_data.id, track_id);
                if let Err(e) = self.add_clip_to_layer(&layer, clip_data) {
                    log::error!("Failed to add clip {} to layer: {}", clip_data.id, e);
                    return Err(e);
                }
                debug!("Successfully added clip {} to track {}", clip_data.id, track_id);
            }
            debug!("Completed adding all clips to track {}", track_id);
        }

        // Create pipeline from timeline
        debug!("Creating pipeline from timeline...");
        if let Err(e) = self.create_pipeline_from_timeline(timeline) {
            log::error!("Failed to create pipeline from timeline: {}", e);
            return Err(e);
        }
        
        let elapsed = start_time.elapsed();
        info!("Timeline update completed successfully in {:?}", elapsed);
        Ok(())
    }

    fn validate_clips(&self, clips: &[TimelineClipData]) -> Result<(), String> {
        // Group clips by track for validation
        let mut tracks: HashMap<i32, Vec<&TimelineClipData>> = HashMap::new();
        for clip in clips {
            tracks.entry(clip.track_id).or_insert_with(Vec::new).push(clip);
        }

        // Check for overlaps within each track
        for (track_id, track_clips) in tracks {
            let mut sorted_clips = track_clips;
            sorted_clips.sort_by_key(|clip| clip.start_time_on_track_ms);

            for i in 0..sorted_clips.len().saturating_sub(1) {
                let current = sorted_clips[i];
                let next = sorted_clips[i + 1];

                if current.end_time_on_track_ms > next.start_time_on_track_ms {
                    return Err(format!(
                        "Clip overlap detected on track {}: clip {} ({}ms-{}ms) overlaps with clip {} ({}ms-{}ms)",
                        track_id,
                        current.id, current.start_time_on_track_ms, current.end_time_on_track_ms,
                        next.id, next.start_time_on_track_ms, next.end_time_on_track_ms
                    ));
                }
            }

            // Validate clip timing
            for clip in &sorted_clips {
                if clip.start_time_on_track_ms < 0 {
                    return Err(format!("Clip {} has negative start time: {}ms", clip.id, clip.start_time_on_track_ms));
                }
                if clip.end_time_on_track_ms <= clip.start_time_on_track_ms {
                    return Err(format!("Clip {} has invalid duration: {}ms-{}ms", 
                                     clip.id, clip.start_time_on_track_ms, clip.end_time_on_track_ms));
                }
                if clip.start_time_in_source_ms < 0 {
                    return Err(format!("Clip {} has negative source start time: {}ms", clip.id, clip.start_time_in_source_ms));
                }
                if clip.end_time_in_source_ms <= clip.start_time_in_source_ms {
                    return Err(format!("Clip {} has invalid source duration: {}ms-{}ms", 
                                     clip.id, clip.start_time_in_source_ms, clip.end_time_in_source_ms));
                }
            }
        }

        debug!("Clip validation passed");
        Ok(())
    }

    fn add_clip_to_layer(&mut self, layer: &ges::Layer, clip_data: &TimelineClipData) -> Result<(), String> {
        debug!("Adding clip {} to layer", clip_data.id);

        // Convert file path to URI
        let uri = if clip_data.source_path.starts_with("file://") {
            clip_data.source_path.clone()
        } else {
            format!("file://{}", clip_data.source_path)
        };

        debug!("Converted path to URI: {}", uri);

        // Validate file exists
        if !uri.starts_with("file://") {
            return Err(format!("Invalid URI format: {}", uri));
        }
        
        let file_path = uri.strip_prefix("file://").unwrap_or(&uri);
        debug!("Checking file existence: {}", file_path);
        
        if !std::path::Path::new(file_path).exists() {
            return Err(format!("Video file does not exist: {}", file_path));
        }
        
        debug!("File exists, creating URI clip");

        // Always create a fresh URI clip to avoid conflicts
        debug!("Creating new URI clip for {}", uri);
        let uri_clip = match std::panic::catch_unwind(|| {
            ges::UriClip::new(&uri)
        }) {
            Ok(Ok(clip)) => {
                debug!("Successfully created URI clip for {}", uri);
                clip
            }
            Ok(Err(e)) => {
                log::error!("GES UriClip::new returned error for {}: {:?}", uri, e);
                return Err(format!("Failed to create URI clip for {}: {:?}", uri, e));
            }
            Err(panic_info) => {
                log::error!("UriClip::new panicked for {}: {:?}", uri, panic_info);
                return Err(format!("UriClip creation panicked for {}", uri));
            }
        };

        // Set timing properties
        let start_ns = clip_data.start_time_on_track_ms * 1_000_000;
        let duration_ns = (clip_data.end_time_on_track_ms - clip_data.start_time_on_track_ms) * 1_000_000;
        let inpoint_ns = clip_data.start_time_in_source_ms * 1_000_000;

        debug!("Setting timing properties: start={}ns, duration={}ns, inpoint={}ns", 
               start_ns, duration_ns, inpoint_ns);

        uri_clip.set_start(gst::ClockTime::from_nseconds(start_ns as u64));
        uri_clip.set_duration(gst::ClockTime::from_nseconds(duration_ns as u64));
        uri_clip.set_inpoint(gst::ClockTime::from_nseconds(inpoint_ns as u64));

        debug!("Set timing properties, now adding clip to layer");

        // Add clip to layer
        match std::panic::catch_unwind(|| {
            layer.add_clip(&uri_clip)
        }) {
            Ok(Ok(_)) => {
                debug!("Successfully added clip {} to layer", clip_data.id);
            }
            Ok(Err(e)) => {
                log::error!("layer.add_clip returned error for clip {}: {:?}", clip_data.id, e);
                return Err(format!("Failed to add clip {} to layer: {:?}", clip_data.id, e));
            }
            Err(panic_info) => {
                log::error!("layer.add_clip panicked for clip {}: {:?}", clip_data.id, panic_info);
                return Err(format!("Adding clip {} to layer panicked", clip_data.id));
            }
        }

        Ok(())
    }

    fn create_pipeline_from_timeline(&mut self, timeline: ges::Timeline) -> Result<(), String> {
        info!("Creating GES pipeline from timeline");

        // Create a GES pipeline and set the timeline
        let ges_pipeline = ges::Pipeline::new();
        debug!("Created GES pipeline");
        
        ges_pipeline.set_timeline(&timeline).map_err(|e| format!("Failed to set timeline on pipeline: {}", e))?;
        debug!("Set timeline on pipeline");

        // Configure pipeline for low latency
        let gst_pipeline = ges_pipeline.upcast_ref::<gst::Pipeline>();
        gst_pipeline.set_latency(gst::ClockTime::from_mseconds(50));
        debug!("Set pipeline latency to 50ms");

        // Create our custom video sink
        let video_sink = gst::ElementFactory::make("appsink")
            .property("emit-signals", true)
            .property("sync", true)
            .property("max-buffers", 2u32)
            .property("drop", true)
            .build()
            .map_err(|e| format!("Failed to create video appsink: {}", e))?;

        debug!("Created video sink");

        // Configure video sink
        let video_appsink = video_sink.clone().dynamic_cast::<gst_app::AppSink>().unwrap();
        video_appsink.set_caps(Some(
            &gst::Caps::builder("video/x-raw")
                .field("format", "BGRA")
                .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
                .build()
        ));

        debug!("Configured video sink caps");

        // Set up frame callbacks
        self.setup_video_callbacks(&video_appsink)?;
        debug!("Set up video callbacks");

        // Set our video sink directly - let GES do all the conversion/processing
        ges_pipeline.set_video_sink(Some(&video_sink));
        debug!("Set custom video sink on GES pipeline");

        self.timeline = Some(timeline);
        self.pipeline = Some(gst_pipeline.clone());

        info!("GES timeline pipeline created successfully");
        Ok(())
    }

    fn setup_video_callbacks(&self, video_appsink: &gst_app::AppSink) -> Result<(), String> {
        let frame_handler = self.frame_handler.clone();

        video_appsink.set_callbacks(
            gst_app::AppSinkCallbacks::builder()
                .new_sample(move |appsink| {
                    let sample = match appsink.pull_sample() {
                        Ok(sample) => sample,
                        Err(e) => {
                            debug!("Failed to pull sample from appsink: {:?}", e);
                            return Err(gst::FlowError::Eos);
                        }
                    };

                    if let Some(buffer) = sample.buffer() {
                        if let Some(caps) = sample.caps() {
                            if let Ok(video_info) = gst_video::VideoInfo::from_caps(&caps) {
                                let width = video_info.width();
                                let height = video_info.height();

                                if let Ok(map) = buffer.map_readable() {
                                    let data = map.as_slice();

                                    // Only copy if we actually have a texture to render to
                                    if frame_handler.texture_ptr.is_some() {
                                        let frame_data = FrameData {
                                            data: data.to_vec(),
                                            width,
                                            height,
                                        };

                                        debug!("Received video frame: {}x{}, {} bytes", width, height, data.len());
                                        frame_handler.store_frame(frame_data);
                                    }
                                } else {
                                    debug!("Failed to map buffer for reading");
                                }
                            } else {
                                debug!("Failed to get video info from caps: {:?}", caps);
                            }
                        } else {
                            debug!("Sample has no caps");
                        }
                    } else {
                        debug!("Sample has no buffer");
                    }

                    Ok(gst::FlowSuccess::Ok)
                })
                .build()
        );

        Ok(())
    }

    fn play(&mut self) -> Result<(), String> {
        if let Some(pipeline) = &self.pipeline {
            match pipeline.set_state(gst::State::Playing) {
                Ok(_) => {
                    self.is_playing = true;
                    info!("Timeline playback started");
                    Ok(())
                }
                Err(e) => Err(format!("Failed to start timeline playback: {:?}", e)),
            }
        } else {
            Err("No timeline pipeline available".to_string())
        }
    }

    fn pause(&mut self) -> Result<(), String> {
        if let Some(pipeline) = &self.pipeline {
            match pipeline.set_state(gst::State::Paused) {
                Ok(_) => {
                    self.is_playing = false;
                    info!("Timeline playback paused");
                    Ok(())
                }
                Err(e) => Err(format!("Failed to pause timeline playback: {:?}", e)),
            }
        } else {
            Err("No timeline pipeline available".to_string())
        }
    }

    fn seek(&mut self, position_ms: i64) -> Result<(), String> {
        debug!("Attempting to seek to {}ms", position_ms);
        
        if let Some(pipeline) = &self.pipeline {
            // Validate the position is reasonable
            if position_ms < 0 {
                return Err(format!("Invalid seek position: {}ms (negative)", position_ms));
            }
            
            // Check pipeline state before seeking
            let current_state = pipeline.current_state();
            debug!("Pipeline state before seek: {:?}", current_state);
            
            // Only seek if pipeline is in a seekable state
            if current_state == gst::State::Null || current_state == gst::State::VoidPending {
                return Err(format!("Pipeline not ready for seeking (state: {:?})", current_state));
            }
            
            // Get the timeline duration to validate seek position
            let duration = if let Some(duration) = pipeline.query_duration::<gst::ClockTime>() {
                duration
            } else {
                debug!("Could not query pipeline duration, using default");
                gst::ClockTime::from_seconds(3600) // 1 hour default
            };
            
            let position_ns = position_ms * 1_000_000;
            let seek_pos = gst::ClockTime::from_nseconds(position_ns as u64);
            
            // Ensure seek position is within bounds
            if seek_pos >= duration {
                debug!("Clamping seek position from {}ms to duration {}ms", 
                       position_ms, duration.mseconds());
                let clamped_pos = if duration > gst::ClockTime::from_mseconds(1) {
                    duration - gst::ClockTime::from_mseconds(1)
                } else {
                    gst::ClockTime::ZERO
                };
                
                let seek_event = gst::event::Seek::new(
                    1.0,
                    gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
                    gst::SeekType::Set,
                    clamped_pos,
                    gst::SeekType::Set,
                    duration,
                );
                
                debug!("Sending clamped seek event to pipeline");
                
                if pipeline.send_event(seek_event) {
                    debug!("Timeline seek to {}ms (clamped) completed successfully", 
                           clamped_pos.mseconds());
                    Ok(())
                } else {
                    log::error!("Failed to send clamped seek event to pipeline");
                    Err("Failed to seek timeline - seek event not accepted".to_string())
                }
            } else {
                debug!("Creating seek event for position {}ms ({}ns)", position_ms, position_ns);
                
                // Create a proper seek event with valid start and stop positions
                let seek_event = gst::event::Seek::new(
                    1.0,
                    gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
                    gst::SeekType::Set,
                    seek_pos,
                    gst::SeekType::Set,
                    duration,
                );

                debug!("Sending seek event to pipeline (pos: {}ms, duration: {}ms)", 
                       position_ms, duration.mseconds());
                
                if pipeline.send_event(seek_event) {
                    debug!("Timeline seek to {}ms completed successfully", position_ms);
                    Ok(())
                } else {
                    log::error!("Failed to send seek event to pipeline");
                    Err("Failed to seek timeline - seek event not accepted".to_string())
                }
            }
        } else {
            log::error!("Attempt to seek with no pipeline available");
            Err("No timeline pipeline available".to_string())
        }
    }

    fn get_position(&self) -> i64 {
        if let Some(pipeline) = &self.pipeline {
            if let Some(position) = pipeline.query_position::<gst::ClockTime>() {
                return (position.nseconds() / 1_000_000) as i64;
            }
        }
        0
    }

    fn get_duration(&self) -> i64 {
        if let Some(pipeline) = &self.pipeline {
            if let Some(duration) = pipeline.query_duration::<gst::ClockTime>() {
                return (duration.nseconds() / 1_000_000) as i64;
            }
        }
        0
    }

    fn is_playing(&self) -> bool {
        self.is_playing
    }

    fn set_texture_ptr(&mut self, ptr: i64) {
        self.frame_handler.set_texture_ptr(ptr);
    }

    fn dispose(&mut self) {
        info!("Disposing timeline worker");
        
        if let Some(pipeline) = &self.pipeline {
            let _ = pipeline.set_state(gst::State::Null);
        }

        self.pipeline = None;
        self.timeline = None;
        self.clips.clear();
    }
}

pub struct TimelineComposer {
    command_sender: mpsc::Sender<TimelineCommand>,
    worker_handle: Option<JoinHandle<()>>,
    frame_handler: FrameHandler,
}

impl TimelineComposer {
    pub fn new(frame_handler: FrameHandler) -> Self {
        let (command_sender, command_receiver) = mpsc::channel();
        let worker_frame_handler = frame_handler.clone();

        let worker_handle = thread::spawn(move || {
            // Set up panic hook to log panics before they kill the thread
            let original_hook = std::panic::take_hook();
            std::panic::set_hook(Box::new(move |panic_info| {
                log::error!("Timeline worker thread panicked: {:?}", panic_info);
                original_hook(panic_info);
            }));

            // Wrap worker creation in a panic-catching block
            let worker_result = std::panic::catch_unwind(|| {
                TimelineWorker::new(worker_frame_handler)
            });

            let mut worker = match worker_result {
                Ok(worker) => {
                    info!("Timeline worker created successfully");
                    worker
                }
                Err(e) => {
                    log::error!("Failed to create timeline worker: {:?}", e);
                    return;
                }
            };
            
            while let Ok(command) = command_receiver.recv() {
                // Wrap each command in panic catching
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    match command {
                        TimelineCommand::UpdateTimeline { clips, response } => {
                            info!("Worker received UpdateTimeline command with {} clips", clips.len());
                            
                            // Wrap the actual work in a detailed error handler
                            let result = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                                worker.update_timeline(clips)
                            })) {
                                Ok(result) => result,
                                Err(panic_info) => {
                                    let panic_msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                                        s.to_string()
                                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                                        s.clone()
                                    } else {
                                        "Unknown panic occurred".to_string()
                                    };
                                    log::error!("UpdateTimeline panicked: {}", panic_msg);
                                    Err(format!("Timeline update panicked: {}", panic_msg))
                                }
                            };
                            
                            info!("UpdateTimeline command completed with result: {:?}", result);
                            if let Err(send_err) = response.send(result) {
                                log::error!("Failed to send UpdateTimeline response: {:?}", send_err);
                            }
                        }
                        TimelineCommand::Play { response } => {
                            info!("Worker received Play command");
                            let result = worker.play();
                            info!("Play command completed with result: {:?}", result);
                            let _ = response.send(result);
                        }
                        TimelineCommand::Pause { response } => {
                            info!("Worker received Pause command");
                            let result = worker.pause();
                            info!("Pause command completed with result: {:?}", result);
                            let _ = response.send(result);
                        }
                        TimelineCommand::Seek { position_ms, response } => {
                            info!("Worker received Seek command to {}ms", position_ms);
                            let result = worker.seek(position_ms);
                            info!("Seek command completed with result: {:?}", result);
                            let _ = response.send(result);
                        }
                        TimelineCommand::GetPosition { response } => {
                            debug!("Worker received GetPosition command");
                            let result = worker.get_position();
                            debug!("GetPosition command completed with result: {}", result);
                            let _ = response.send(result);
                        }
                        TimelineCommand::GetDuration { response } => {
                            debug!("Worker received GetDuration command");
                            let result = worker.get_duration();
                            debug!("GetDuration command completed with result: {}", result);
                            let _ = response.send(result);
                        }
                        TimelineCommand::IsPlaying { response } => {
                            debug!("Worker received IsPlaying command");
                            let result = worker.is_playing();
                            debug!("IsPlaying command completed with result: {}", result);
                            let _ = response.send(result);
                        }
                        TimelineCommand::SetTexturePtr { ptr } => {
                            info!("Worker received SetTexturePtr command with ptr: {}", ptr);
                            worker.set_texture_ptr(ptr);
                            info!("SetTexturePtr command completed");
                        }
                        TimelineCommand::Dispose => {
                            info!("Worker received Dispose command");
                            worker.dispose();
                            info!("Dispose command completed");
                            return false; // Signal to break the loop
                        }
                    }
                    true // Continue processing
                }));

                match result {
                    Ok(should_continue) => {
                        if !should_continue {
                            break;
                        }
                    }
                    Err(e) => {
                        log::error!("Timeline worker command panicked: {:?}", e);
                        // Try to recover by continuing, but log the error
                        continue;
                    }
                }
            }
            
            info!("Timeline worker thread exiting gracefully");
        });

        Self {
            command_sender,
            worker_handle: Some(worker_handle),
            frame_handler,
        }
    }

    pub fn update_timeline(&mut self, clips: Vec<TimelineClipData>) -> Result<(), String> {
        let (response_sender, response_receiver) = mpsc::channel();
        
        info!("Sending UpdateTimeline command to worker with {} clips", clips.len());
        
        self.command_sender
            .send(TimelineCommand::UpdateTimeline { clips, response: response_sender })
            .map_err(|_| "Failed to send update timeline command".to_string())?;
        
        info!("Command sent, waiting for response...");
        
        // Add timeout to detect if worker is hanging
        use std::time::Duration;
        match response_receiver.recv_timeout(Duration::from_secs(30)) {
            Ok(result) => {
                info!("Received response from worker: {:?}", result);
                result
            }
            Err(e) => {
                log::error!("Failed to receive update timeline response within 30 seconds: {:?}", e);
                Err(format!("Failed to receive update timeline response within timeout: {:?}", e))
            }
        }
    }

    pub fn play(&mut self) -> Result<(), String> {
        let (response_sender, response_receiver) = mpsc::channel();
        
        self.command_sender
            .send(TimelineCommand::Play { response: response_sender })
            .map_err(|_| "Failed to send play command".to_string())?;
        
        response_receiver
            .recv()
            .map_err(|_| "Failed to receive play response".to_string())?
    }

    pub fn pause(&mut self) -> Result<(), String> {
        let (response_sender, response_receiver) = mpsc::channel();
        
        self.command_sender
            .send(TimelineCommand::Pause { response: response_sender })
            .map_err(|_| "Failed to send pause command".to_string())?;
        
        response_receiver
            .recv()
            .map_err(|_| "Failed to receive pause response".to_string())?
    }

    pub fn seek(&mut self, position_ms: i64) -> Result<(), String> {
        let (response_sender, response_receiver) = mpsc::channel();
        
        self.command_sender
            .send(TimelineCommand::Seek { position_ms, response: response_sender })
            .map_err(|_| "Failed to send seek command".to_string())?;
        
        response_receiver
            .recv()
            .map_err(|_| "Failed to receive seek response".to_string())?
    }

    pub fn get_position(&self) -> i64 {
        let (response_sender, response_receiver) = mpsc::channel();
        
        if let Ok(()) = self.command_sender.send(TimelineCommand::GetPosition { response: response_sender }) {
            response_receiver.recv().unwrap_or(0)
        } else {
            0
        }
    }

    pub fn get_duration(&self) -> i64 {
        let (response_sender, response_receiver) = mpsc::channel();
        
        if let Ok(()) = self.command_sender.send(TimelineCommand::GetDuration { response: response_sender }) {
            response_receiver.recv().unwrap_or(0)
        } else {
            0
        }
    }

    pub fn is_playing(&self) -> bool {
        let (response_sender, response_receiver) = mpsc::channel();
        
        if let Ok(()) = self.command_sender.send(TimelineCommand::IsPlaying { response: response_sender }) {
            response_receiver.recv().unwrap_or(false)
        } else {
            false
        }
    }

    pub fn set_texture_ptr(&mut self, ptr: i64) {
        let _ = self.command_sender.send(TimelineCommand::SetTexturePtr { ptr });
        // Also set it on the frame handler for immediate access
        self.frame_handler.set_texture_ptr(ptr);
    }

    pub fn get_latest_frame(&self) -> Option<FrameData> {
        self.frame_handler.get_latest_frame()
    }

    pub fn dispose(&mut self) {
        info!("Disposing timeline composer");
        
        // Send dispose command and wait for worker to finish
        let _ = self.command_sender.send(TimelineCommand::Dispose);
        
        if let Some(handle) = self.worker_handle.take() {
            let _ = handle.join();
        }
    }
}

impl Drop for TimelineComposer {
    fn drop(&mut self) {
        self.dispose();
    }
} 