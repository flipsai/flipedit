use crate::audio_handler::{MediaSender, MediaData, AudioFrame};
use crate::video::frame_handler::FrameHandler;
use crate::common::types::FrameData;
use crate::video::player::FrameCallback;
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_video as gst_video;
use gstreamer_audio as gst_audio;
use gstreamer_app as gst_app;
use std::sync::{Arc, Mutex};
use log::{info, warn, error, debug};

pub struct PipelineManager {
    pub pipeline: Option<gst::Pipeline>,
    pub frame_handler: FrameHandler,
    pub audio_sender: Option<MediaSender>,
    pub has_audio: Arc<Mutex<bool>>,
    frame_callback: Arc<Mutex<Option<FrameCallback>>>,
}

impl PipelineManager {
    pub fn new(
        frame_handler: FrameHandler,
        audio_sender: Option<MediaSender>,
        has_audio: Arc<Mutex<bool>>,
        frame_callback: Arc<Mutex<Option<FrameCallback>>>,
    ) -> Result<Self, String> {
        Ok(Self {
            pipeline: None,
            frame_handler,
            audio_sender,
            has_audio,
            frame_callback,
        })
    }

    pub fn create_pipeline(&mut self, file_path: &str) -> Result<(), String> {
        info!("Creating GStreamer pipeline for: {}", file_path);
        debug!("Texture pointer: {:?}", self.frame_handler.texture_ptr);

        // Create a new pipeline
        let pipeline = gst::Pipeline::new();
        
        // Configure pipeline for low latency
        pipeline.set_latency(gst::ClockTime::from_mseconds(50));

        // Create elements
        let source = gst::ElementFactory::make("filesrc")
            .property("location", file_path)
            .build()
            .map_err(|e| format!("Failed to create filesrc: {}", e))?;

        let decodebin = gst::ElementFactory::make("decodebin")
            .build()
            .map_err(|e| format!("Failed to create decodebin: {}", e))?;

        // Video elements
        let videoconvert = gst::ElementFactory::make("videoconvert")
            .build()
            .map_err(|e| format!("Failed to create videoconvert: {}", e))?;

        let videoscale = gst::ElementFactory::make("videoscale")
            .property("add-borders", true)
            .build()
            .map_err(|e| format!("Failed to create videoscale: {}", e))?;

        // Add caps filter to limit resolution to prevent crashes
        let video_capsfilter = gst::ElementFactory::make("capsfilter")
            .build()
            .map_err(|e| format!("Failed to create video capsfilter: {}", e))?;

        let video_appsink = gst::ElementFactory::make("appsink")
            .property("emit-signals", true)
            .property("sync", true)
            .property("max-buffers", 2u32)
            .property("drop", true)
            .property("async", false)
            .build()
            .map_err(|e| format!("Failed to create video appsink: {}", e))?;

        // Audio elements
        let audioconvert = gst::ElementFactory::make("audioconvert")
            .build()
            .map_err(|e| format!("Failed to create audioconvert: {}", e))?;

        let audioresample = gst::ElementFactory::make("audioresample")
            .build()
            .map_err(|e| format!("Failed to create audioresample: {}", e))?;

        let audio_appsink = gst::ElementFactory::make("appsink")
            .property("emit-signals", true)
            .property("sync", true)
            .property("max-buffers", 3u32)
            .property("drop", true)
            .property("async", false)
            .build()
            .map_err(|e| format!("Failed to create audio appsink: {}", e))?;

        debug!("All GStreamer elements created successfully");

        // Configure video caps filter to limit maximum resolution (prevents crashes with huge videos)
        video_capsfilter.set_property("caps", &gst::Caps::builder("video/x-raw")
            .field("format", "BGRA")
            .field("width", gst::IntRange::new(1, 1920))
            .field("height", gst::IntRange::new(1, 1080))
            .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
            .build());

        // Configure video appsink to output BGRA format
        let video_appsink = video_appsink.dynamic_cast::<gst_app::AppSink>().unwrap();
        video_appsink.set_caps(Some(
            &gst::Caps::builder("video/x-raw")
                .field("format", "BGRA")
                .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
                .build()
        ));

        // Configure audio appsink to output PCM format
        let audio_appsink = audio_appsink.dynamic_cast::<gst_app::AppSink>().unwrap();
        audio_appsink.set_caps(Some(
            &gst::Caps::builder("audio/x-raw")
                .field("format", "S16LE")
                .field("channels", 2i32)
                .field("rate", 44100i32)
                .build()
        ));

        debug!("Appsink caps configured");

        // Add elements to pipeline
        pipeline.add_many(&[
            &source, 
            &decodebin, 
            &videoconvert, 
            &videoscale, 
            &video_capsfilter,
            video_appsink.upcast_ref(),
            &audioconvert,
            &audioresample,
            audio_appsink.upcast_ref()
        ]).map_err(|e| format!("Failed to add elements: {}", e))?;

        debug!("Elements added to pipeline");

        // Link static elements
        source.link(&decodebin)
            .map_err(|e| format!("Failed to link source to decodebin: {}", e))?;

        videoconvert.link(&videoscale)
            .map_err(|e| format!("Failed to link videoconvert to videoscale: {}", e))?;
        videoscale.link(&video_capsfilter)
            .map_err(|e| format!("Failed to link videoscale to video capsfilter: {}", e))?;
        video_capsfilter.link(&video_appsink)
            .map_err(|e| format!("Failed to link video capsfilter to video appsink: {}", e))?;

        audioconvert.link(&audioresample)
            .map_err(|e| format!("Failed to link audioconvert to audioresample: {}", e))?;
        audioresample.link(&audio_appsink)
            .map_err(|e| format!("Failed to link audioresample to audio appsink: {}", e))?;

        debug!("Static elements linked successfully");

        // Set up bus message handling
        self.setup_bus_handlers(&pipeline)?;

        // Set up appsink callbacks
        self.setup_video_appsink_callbacks(&video_appsink)?;
        self.setup_audio_appsink_callbacks(&audio_appsink)?;

        // Handle dynamic pads from decodebin
        self.setup_dynamic_pad_handler(&decodebin, &videoconvert, &audioconvert, &pipeline)?;

        self.pipeline = Some(pipeline);
        Ok(())
    }

    fn setup_bus_handlers(&self, pipeline: &gst::Pipeline) -> Result<(), String> {
        let bus = pipeline.bus().unwrap();
        bus.add_signal_watch();
        
        let pipeline_weak = pipeline.downgrade();
        bus.connect_message(Some("error"), move |_, msg| {
            if let gst::MessageView::Error(err) = msg.view() {
                error!(
                    "GStreamer Error from {:?}: {} ({:?})",
                    err.src().map(|s| s.path_string()),
                    err.error(),
                    err.debug()
                );
                
                if let Some(pipeline) = pipeline_weak.upgrade() {
                    let _ = pipeline.set_state(gst::State::Null);
                }
            }
        });

        let pipeline_weak2 = pipeline.downgrade();
        bus.connect_message(Some("state-changed"), move |_, msg| {
            if let gst::MessageView::StateChanged(state_changed) = msg.view() {
                if let Some(src) = msg.src() {
                    if let Some(pipeline) = pipeline_weak2.upgrade() {
                        if src == pipeline.upcast_ref::<gst::Object>() {
                            info!("Pipeline state changed from {:?} to {:?}", 
                                state_changed.old(), state_changed.current());
                        }
                    }
                }
            }
        });

        let _pipeline_weak3 = pipeline.downgrade();
        bus.connect_message(Some("warning"), move |_, msg| {
            if let gst::MessageView::Warning(warn) = msg.view() {
                warn!("GStreamer Warning from {:?}: {} ({:?})",
                    warn.src().map(|s| s.path_string()),
                    warn.error(),
                    warn.debug()
                );
            }
        });

        debug!("Bus message handlers set up");
        Ok(())
    }

    fn setup_video_appsink_callbacks(&self, video_appsink: &gst_app::AppSink) -> Result<(), String> {
        let frame_handler = self.frame_handler.clone();
        let frame_callback = self.frame_callback.clone();
        
        video_appsink.set_callbacks(
            gst_app::AppSinkCallbacks::builder()
                .new_sample(move |appsink| {
                    debug!("New video sample callback triggered");
                    
                    let sample = match appsink.pull_sample() {
                        Ok(sample) => sample,
                        Err(_) => {
                            debug!("Failed to pull video sample");
                            return Err(gst::FlowError::Eos);
                        }
                    };
                    
                    if let Some(buffer) = sample.buffer() {
                        debug!("Got video buffer from sample");
                        
                        if let Some(caps) = sample.caps() {
                            if let Ok(video_info) = gst_video::VideoInfo::from_caps(&caps) {
                                let width = video_info.width();
                                let height = video_info.height();
                                
                                debug!("Video dimensions: {}x{}", width, height);
                                frame_handler.update_dimensions(width, height);
                                
                                // Extract frame rate from caps
                                if let Some(caps_struct) = caps.structure(0) {
                                    if let Ok(framerate) = caps_struct.get::<gst::Fraction>("framerate") {
                                        let fps = framerate.numer() as f64 / framerate.denom() as f64;
                                        debug!("Detected frame rate: {} fps ({}/{})", fps, framerate.numer(), framerate.denom());
                                        frame_handler.update_frame_rate(fps);
                                    } else {
                                        debug!("No framerate field found in video caps");
                                    }
                                }
                                
                                if let Ok(map) = buffer.map_readable() {
                                    let data = map.as_slice();
                                    debug!("Buffer mapped, size: {} bytes", data.len());
                                    
                                    let frame_data = FrameData {
                                        data: data.to_vec(),
                                        width,
                                        height,
                                    };
                                    
                                    if let Ok(guard) = frame_callback.lock() {
                                        if let Some(cb) = &*guard {
                                            if let Err(e) = cb(frame_data) {
                                                warn!("Frame callback failed: {}", e);
                                            }
                                        } else {
                                            frame_handler.store_frame(frame_data);
                                        }
                                    } else {
                                        frame_handler.store_frame(frame_data);
                                    }
                                } else {
                                    debug!("Failed to map buffer");
                                }
                            } else {
                                debug!("Failed to get video info from caps");
                            }
                        } else {
                            debug!("No caps available");
                        }
                    } else {
                        debug!("No buffer in sample");
                    }
                    
                    debug!("Video sample processing completed");
                    Ok(gst::FlowSuccess::Ok)
                })
                .build()
        );

        debug!("Video appsink callbacks configured");
        Ok(())
    }

    fn setup_audio_appsink_callbacks(&self, audio_appsink: &gst_app::AppSink) -> Result<(), String> {
        let has_audio_arc = self.has_audio.clone();
        let audio_tx_for_callback = self.audio_sender.clone();

        audio_appsink.set_callbacks(
            gst_app::AppSinkCallbacks::builder()
                .new_sample(move |appsink| {
                    debug!("New audio sample callback triggered");
                    
                    let sample = match appsink.pull_sample() {
                        Ok(sample) => sample,
                        Err(_) => {
                            debug!("Failed to pull audio sample");
                            return Err(gst::FlowError::Eos);
                        }
                    };
                    
                    if let Some(buffer) = sample.buffer() {
                        debug!("Got audio buffer from sample");
                        
                        if let Some(caps) = sample.caps() {
                            if let Ok(audio_info) = gst_audio::AudioInfo::from_caps(&caps) {
                                let sample_rate = audio_info.rate();
                                let channels = audio_info.channels();
                                let bytes_per_sample = (audio_info.depth() / 8) as u32;
                                
                                debug!("Audio info: {}Hz, {} channels, {} bytes per sample", 
                                    sample_rate, channels, bytes_per_sample);
                                
                                if let Ok(mut has_audio_guard) = has_audio_arc.try_lock() {
                                    *has_audio_guard = true;
                                }
                                
                                if let Ok(map) = buffer.map_readable() {
                                    let data = map.as_slice();
                                    debug!("Audio buffer mapped, size: {} bytes", data.len());
                                    
                                    let timestamp = buffer.pts().map(|pts| pts.nseconds());
                                    
                                    let audio_frame = AudioFrame {
                                        data: data.to_vec(),
                                        sample_rate,
                                        channels,
                                        bytes_per_sample,
                                        timestamp,
                                    };
                                    
                                    if let Some(ref audio_tx) = audio_tx_for_callback {
                                        if let Err(e) = audio_tx.send(MediaData::AudioFrame(Box::new(audio_frame))) {
                                            debug!("Failed to send audio frame: {}", e);
                                        } else {
                                            debug!("Sent audio frame to audio system");
                                        }
                                    }
                                } else {
                                    debug!("Failed to map audio buffer");
                                }
                            } else {
                                debug!("Failed to get audio info from caps");
                            }
                        } else {
                            debug!("No audio caps available");
                        }
                    } else {
                        debug!("No audio buffer in sample");
                    }
                    
                    debug!("Audio sample processing completed");
                    Ok(gst::FlowSuccess::Ok)
                })
                .build()
        );

        debug!("Audio appsink callbacks configured");
        Ok(())
    }

    fn setup_dynamic_pad_handler(
        &self,
        decodebin: &gst::Element,
        videoconvert: &gst::Element,
        audioconvert: &gst::Element,
        pipeline: &gst::Pipeline,
    ) -> Result<(), String> {
        let videoconvert_weak = videoconvert.downgrade();
        let audioconvert_weak = audioconvert.downgrade();
        let pipeline_weak = pipeline.downgrade();
        
        decodebin.connect_pad_added(move |_dbin, src_pad| {
            debug!("Pad added callback triggered");
            
            let new_pad_caps = match src_pad.current_caps() {
                Some(caps) => caps,
                None => {
                    error!("Failed to get caps from new pad");
                    return;
                }
            };
            
            let new_pad_struct = new_pad_caps.structure(0).unwrap();
            let new_pad_type = new_pad_struct.name();

            info!("Received new pad {} from {} with caps {}",
                src_pad.name(), _dbin.name(), new_pad_caps);

            if new_pad_type.starts_with("video/") {
                let videoconvert = match videoconvert_weak.upgrade() {
                    Some(vc) => vc,
                    None => {
                        error!("Failed to upgrade videoconvert weak reference");
                        return;
                    }
                };

                let sink_pad = match videoconvert.static_pad("sink") {
                    Some(pad) => pad,
                    None => {
                        error!("Failed to get sink pad from videoconvert");
                        return;
                    }
                };

                if sink_pad.is_linked() {
                    debug!("Video sink pad is already linked, skipping");
                    return;
                }

                match src_pad.link(&sink_pad) {
                    Ok(_) => {
                        info!("Linked video pad successfully");
                        if let Some(pipeline) = pipeline_weak.upgrade() {
                            match pipeline.set_state(gst::State::Paused) {
                                Ok(_) => info!("Pipeline set to paused after linking video"),
                                Err(e) => error!("Failed to set pipeline to paused after linking video: {:?}", e),
                            }
                        }
                    },
                    Err(e) => error!("Failed to link video pad: {:?}", e),
                }
            } else if new_pad_type.starts_with("audio/") {
                let audioconvert = match audioconvert_weak.upgrade() {
                    Some(ac) => ac,
                    None => {
                        error!("Failed to upgrade audioconvert weak reference");
                        return;
                    }
                };

                let sink_pad = match audioconvert.static_pad("sink") {
                    Some(pad) => pad,
                    None => {
                        error!("Failed to get sink pad from audioconvert");
                        return;
                    }
                };

                if sink_pad.is_linked() {
                    debug!("Audio sink pad is already linked, skipping");
                    return;
                }

                match src_pad.link(&sink_pad) {
                    Ok(_) => {
                        info!("Linked audio pad successfully");
                    },
                    Err(e) => error!("Failed to link audio pad: {:?}", e),
                }
            } else {
                debug!("Ignoring unsupported pad type: {}", new_pad_type);
            }
        });

        debug!("Dynamic pad handler configured");
        Ok(())
    }

    pub fn play(&mut self) -> Result<(), String> {
        if let Some(pipeline) = &self.pipeline {
            let (current_state_result, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
            
            match current_state_result {
                Ok(_) => {
                    info!("Current pipeline state: {:?}", current_state);
                    
                    if current_state == gst::State::Null {
                        info!("Pipeline is in null state, setting to paused first...");
                        match pipeline.set_state(gst::State::Paused) {
                            Ok(gst::StateChangeSuccess::Success) => {
                                info!("Pipeline successfully set to paused");
                            },
                            Ok(gst::StateChangeSuccess::Async) => {
                                info!("Pipeline is transitioning to paused, not waiting...");
                                // Don't wait for async state changes to avoid blocking
                            },
                            Ok(gst::StateChangeSuccess::NoPreroll) => {
                                info!("Pipeline set to paused without preroll");
                            },
                            Err(e) => {
                                return Err(format!("Failed to set pipeline to paused: {:?}", e));
                            }
                        }
                    }
                    
                    match pipeline.set_state(gst::State::Playing) {
                        Ok(gst::StateChangeSuccess::Success) => {
                            info!("Pipeline is now playing");
                            Ok(())
                        },
                        Ok(gst::StateChangeSuccess::Async) => {
                            info!("Pipeline is transitioning to playing state");
                            Ok(())
                        },
                        Ok(gst::StateChangeSuccess::NoPreroll) => {
                            info!("Pipeline is playing without preroll");
                            Ok(())
                        },
                        Err(e) => {
                            Err(format!("Failed to set pipeline to playing: {:?}", e))
                        }
                    }
                },
                Err(e) => {
                    Err(format!("Failed to get pipeline state: {:?}", e))
                }
            }
        } else {
            Err("No pipeline available".to_string())
        }
    }

    pub fn pause(&mut self) -> Result<(), String> {
        if let Some(pipeline) = &self.pipeline {
            info!("Setting pipeline to paused state");
            
            match pipeline.set_state(gst::State::Paused) {
                Ok(gst::StateChangeSuccess::Success) => {
                    info!("Pipeline successfully set to paused");
                },
                Ok(gst::StateChangeSuccess::Async) => {
                    info!("Pipeline transitioning to paused asynchronously");
                    // Don't wait for async completion to avoid blocking
                },
                Ok(gst::StateChangeSuccess::NoPreroll) => {
                    info!("Pipeline set to paused without preroll");
                },
                Err(e) => {
                    return Err(format!("Failed to set pipeline to paused: {:?}", e));
                }
            }
            
            // Quick state check without waiting
            let (_, current_state, _) = pipeline.state(Some(gst::ClockTime::from_nseconds(0)));
            info!("Pipeline state after pause command: {:?}", current_state);
            
            Ok(())
        } else {
            Err("No pipeline available".to_string())
        }
    }

    pub fn stop(&mut self) -> Result<(), String> {
        if let Some(pipeline) = &self.pipeline {
            pipeline.set_state(gst::State::Null)
                .map_err(|e| format!("Failed to set pipeline to null: {:?}", e))?;
            Ok(())
        } else {
            Err("No pipeline available".to_string())
        }
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        info!("Disposing PipelineManager");
        
        if let Some(pipeline) = &self.pipeline {
            match pipeline.set_state(gst::State::Null) {
                Ok(_) => info!("Pipeline set to null state"),
                Err(e) => warn!("Failed to set pipeline to null: {:?}", e),
            }
            
            if let Some(bus) = pipeline.bus() {
                bus.remove_signal_watch();
            }
        }
        
        self.pipeline = None;
        info!("PipelineManager disposed successfully");
        Ok(())
    }
} 