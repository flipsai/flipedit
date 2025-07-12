use anyhow::{anyhow, Result};
use ges::prelude::*;
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gst::prelude::*;
use log::{info, warn};
use std::sync::{Arc, Mutex};

/// GES Pipeline Manager - handles GES pipeline creation and management
pub struct GESPipelineManager {
    pipeline: Option<ges::Pipeline>,
    test_pipeline: Option<gst::Pipeline>,  // For test patterns
    current_position_ms: Arc<Mutex<u64>>,
    is_playing: bool,
}

impl GESPipelineManager {
    pub fn new() -> Self {
        Self {
            pipeline: None,
            test_pipeline: None,
            current_position_ms: Arc::new(Mutex::new(0)),
            is_playing: false,
        }
    }

    /// Create a GES pipeline from a timeline
    pub fn create_pipeline(
        &mut self,
        timeline: &ges::Timeline,
        video_sink: &gst::Element,
    ) -> Result<()> {
        info!("Creating GES pipeline from timeline");

        // Create pipeline from timeline
        let pipeline = ges::Pipeline::new();
        
        // Set the timeline on the GES pipeline
        pipeline.set_timeline(timeline)
            .map_err(|e| anyhow!("Failed to set timeline on GES pipeline: {}", e))?;

        // Set up video output sink for preview
        pipeline.preview_set_video_sink(Some(video_sink));

        // Temporarily disable audio to avoid aggregator issues - focus on video first
        // Set up audio sink - use fakesink to avoid audio aggregator issues
        let audio_sink = gst::ElementFactory::make("fakesink")
            .name("ges-audio-sink")
            .property("sync", false)  // Don't sync audio for now
            .build()
            .map_err(|e| anyhow!("Failed to create audio sink: {}", e))?;
        pipeline.set_property("audio-sink", &audio_sink);

        // Set pipeline mode to FULL_PREVIEW for both video and audio output
        pipeline.set_mode(ges::PipelineFlags::FULL_PREVIEW)
            .map_err(|e| anyhow!("Failed to set pipeline mode to FULL_PREVIEW: {}", e))?;

        info!("GES pipeline configured with video sink and audio sink");
        self.pipeline = Some(pipeline);

        info!("GES pipeline created successfully");
        Ok(())
    }

    /// Set a test pipeline (for testing GPU context without GES)
    pub fn set_test_pipeline(&mut self, pipeline: gst::Pipeline) {
        info!("Setting test pipeline for GPU context testing");
        self.test_pipeline = Some(pipeline);
    }

    /// Start playback
    pub fn play(&mut self) -> Result<()> {
        // Use test pipeline if available, otherwise use GES pipeline
        if let Some(test_pipeline) = &self.test_pipeline {
            info!("Starting test pipeline playback");
            match test_pipeline.set_state(gst::State::Playing) {
                Ok(_) => {
                    self.is_playing = true;
                    info!("✅ Test pipeline started successfully");
                    Ok(())
                }
                Err(e) => {
                    let error_msg = format!("Failed to start test pipeline: {}", e);
                    warn!("{}", error_msg);
                    Err(anyhow!(error_msg))
                }
            }
        } else {
            let pipeline = self
                .pipeline
                .as_ref()
                .ok_or_else(|| anyhow!("No pipeline available for playback"))?;

            info!("Setting GES pipeline to PLAYING (non-blocking approach)");

            // According to GES guide: First set to PAUSED for preroll, then to PLAYING
            // But we'll do this without blocking the main thread
            info!("Step 1: Setting pipeline to PAUSED");
            match pipeline.set_state(gst::State::Paused) {
                Ok(gst::StateChangeSuccess::Success) => {
                    info!("✅ GES pipeline set to PAUSED successfully");
                }
                Ok(gst::StateChangeSuccess::Async) => {
                    info!("⏳ GES pipeline transitioning to PAUSED asynchronously (non-blocking)");
                    // Don't wait synchronously - let the bus messages handle state change notifications
                }
                Ok(gst::StateChangeSuccess::NoPreroll) => {
                    info!("✅ GES pipeline set to PAUSED (no preroll)");
                }
                Err(e) => {
                    let error_msg = format!("Failed to set GES pipeline to PAUSED: {}", e);
                    warn!("{}", error_msg);
                    return Err(anyhow!(error_msg));
                }
            }

            // Step 2: Now set to PLAYING
            info!("Step 2: Setting pipeline to PLAYING");
            match pipeline.set_state(gst::State::Playing) {
                Ok(gst::StateChangeSuccess::Success) => {
                    info!("✅ GES pipeline set to PLAYING successfully");
                    self.is_playing = true;
                    Ok(())
                }
                Ok(gst::StateChangeSuccess::Async) => {
                    info!("⏳ GES pipeline transitioning to PLAYING asynchronously (non-blocking)");
                    // Don't wait synchronously - let the bus messages handle state change notifications
                    self.is_playing = true;
                    Ok(())
                }
                Ok(gst::StateChangeSuccess::NoPreroll) => {
                    info!("✅ GES pipeline set to PLAYING (no preroll)");
                    self.is_playing = true;
                    Ok(())
                }
                Err(e) => {
                    let error_msg = format!("Failed to set GES pipeline to PLAYING: {}", e);
                    warn!("{}", error_msg);
                    Err(anyhow!(error_msg))
                }
            }
        }
    }

    /// Pause playback
    pub fn pause(&mut self) -> Result<()> {
        // Use test pipeline if available, otherwise use GES pipeline
        if let Some(test_pipeline) = &self.test_pipeline {
            info!("Pausing test pipeline");
            match test_pipeline.set_state(gst::State::Paused) {
                Ok(_) => {
                    self.is_playing = false;
                    info!("✅ Test pipeline paused successfully");
                    Ok(())
                }
                Err(e) => {
                    let error_msg = format!("Failed to pause test pipeline: {}", e);
                    warn!("{}", error_msg);
                    Err(anyhow!(error_msg))
                }
            }
        } else {
            let pipeline = self
                .pipeline
                .as_ref()
                .ok_or_else(|| anyhow!("No pipeline available for pause"))?;

        info!("Setting GES pipeline to PAUSED (non-blocking)");

        match pipeline.set_state(gst::State::Paused) {
            Ok(gst::StateChangeSuccess::Success) => {
                info!("✅ GES pipeline paused successfully");
                self.is_playing = false;
                Ok(())
            }
            Ok(gst::StateChangeSuccess::Async) => {
                info!("⏳ GES pipeline transitioning to PAUSED asynchronously (non-blocking)");
                // Don't wait synchronously - let the bus messages handle state change notifications
                self.is_playing = false;
                Ok(())
            }
            Ok(gst::StateChangeSuccess::NoPreroll) => {
                info!("✅ GES pipeline paused (no preroll)");
                self.is_playing = false;
                Ok(())
            }
            Err(e) => {
                let error_msg = format!("Failed to pause GES pipeline: {}", e);
                warn!("{}", error_msg);
                Err(anyhow!(error_msg))
            }
        }
        }
    }

    /// Stop playback
    pub fn stop(&mut self) -> Result<()> {
        // Stop test pipeline if available
        if let Some(test_pipeline) = &self.test_pipeline {
            info!("Setting test pipeline to NULL");
            match test_pipeline.set_state(gst::State::Null) {
                Ok(_) => {
                    info!("✅ Test pipeline stopped successfully");
                    self.is_playing = false;
                    *self.current_position_ms.lock().unwrap() = 0;
                    Ok(())
                }
                Err(e) => {
                    let error_msg = format!("Failed to stop test pipeline: {}", e);
                    warn!("{}", error_msg);
                    Err(anyhow!(error_msg))
                }
            }
        } else if let Some(pipeline) = &self.pipeline {
            info!("Setting GES pipeline to NULL");

            match pipeline.set_state(gst::State::Null) {
                Ok(_) => {
                    info!("✅ GES pipeline stopped successfully");
                    self.is_playing = false;
                    *self.current_position_ms.lock().unwrap() = 0;
                    Ok(())
                }
                Err(e) => {
                    let error_msg = format!("Failed to stop GES pipeline: {}", e);
                    warn!("{}", error_msg);
                    Err(anyhow!(error_msg))
                }
            }
        } else {
            Ok(())
        }
    }

    /// Seek to a specific position
    pub fn seek(&mut self, position_ms: u64) -> Result<()> {
        let pipeline = self
            .pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("No GES pipeline available for seeking"))?;

        info!("🎯 Seeking GES pipeline to position: {}ms", position_ms);

        // Store the current playing state
        let was_playing = self.is_playing;

        // For GES pipelines, we need to use seek_simple which is more reliable
        let position_time = gst::ClockTime::from_mseconds(position_ms);
        let seek_flags = gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE;

        let success = pipeline.seek_simple(seek_flags, position_time);

        if success.is_ok() {
            info!("✅ GES pipeline seek command sent successfully to {}ms", position_ms);
            *self.current_position_ms.lock().unwrap() = position_ms;

            // According to GES guide, we should wait for ASYNC_DONE after seeking
            // Use a brief non-blocking wait to allow the seek to settle
            std::thread::sleep(std::time::Duration::from_millis(50));

            // Restore the previous state properly (non-blocking)
            if was_playing {
                info!("🔄 Restoring PLAYING state after seek (non-blocking)");
                match pipeline.set_state(gst::State::Playing) {
                    Ok(gst::StateChangeSuccess::Success) => {
                        info!("✅ Successfully restored PLAYING state after seek");
                        self.is_playing = true;
                    }
                    Ok(gst::StateChangeSuccess::Async) => {
                        info!("⏳ Restoring PLAYING state asynchronously after seek (non-blocking)");
                        // Don't wait synchronously - let the bus messages handle state change notifications
                        self.is_playing = true;
                    }
                    Ok(gst::StateChangeSuccess::NoPreroll) => {
                        info!("✅ PLAYING state restored (no preroll) after seek");
                        self.is_playing = true;
                    }
                    Err(e) => {
                        warn!("⚠️ Failed to restore PLAYING state after seek: {}", e);
                        self.is_playing = false;
                    }
                }
            } else {
                // If we weren't playing, ensure we're in PAUSED state for frame display
                info!("🔄 Setting PAUSED state after seek for frame display (non-blocking)");
                match pipeline.set_state(gst::State::Paused) {
                    Ok(gst::StateChangeSuccess::Success) => {
                        info!("✅ Successfully set PAUSED state after seek");
                    }
                    Ok(gst::StateChangeSuccess::Async) => {
                        info!("⏳ Setting PAUSED state asynchronously after seek (non-blocking)");
                        // Don't wait synchronously - let the bus messages handle state change notifications
                    }
                    Ok(gst::StateChangeSuccess::NoPreroll) => {
                        info!("✅ PAUSED state set (no preroll) after seek");
                    }
                    Err(e) => {
                        warn!("⚠️ Failed to set PAUSED state after seek: {}", e);
                    }
                }
            }

            Ok(())
        } else {
            let error_msg = format!(
                "Failed to seek GES pipeline to {}ms: {:?}",
                position_ms,
                success.err()
            );
            warn!("{}", error_msg);
            Err(anyhow!(error_msg))
        }
    }

    /// Update position tracking
    pub fn update_position(&self, position_ms: u64) {
        *self.current_position_ms.lock().unwrap() = position_ms;
    }

    /// Get current position
    pub fn get_position(&self) -> u64 {
        *self.current_position_ms.lock().unwrap()
    }

    /// Get the underlying GStreamer pipeline
    pub fn get_gst_pipeline(&self) -> Option<gst::Pipeline> {
        self.pipeline
            .as_ref()
            .map(|p| p.clone().upcast::<gst::Pipeline>())
    }

    /// Check if currently playing
    pub fn is_playing(&self) -> bool {
        self.is_playing
    }

    /// Check pipeline state and attempt recovery if needed
    pub fn check_and_recover_state(&mut self) -> Result<()> {
        if let Some(pipeline) = &self.pipeline {
            let current_state = pipeline.current_state();
            let pending_state = pipeline.pending_state();

            info!(
                "🔍 Pipeline state check - Current: {:?}, Pending: {:?}, Expected playing: {}",
                current_state, pending_state, self.is_playing
            );

            // If we think we're playing but pipeline is not, try to recover
            if self.is_playing
                && current_state != gst::State::Playing
                && pending_state != gst::State::Playing
            {
                warn!(
                    "🚨 Pipeline state mismatch detected! Expected PLAYING but got {:?}",
                    current_state
                );

                // Try to restart playback
                info!("🔄 Attempting to recover by restarting playback");
                match pipeline.set_state(gst::State::Playing) {
                    Ok(_) => {
                        info!("✅ Successfully recovered pipeline to PLAYING state");
                    }
                    Err(e) => {
                        warn!("❌ Failed to recover pipeline state: {}", e);
                        self.is_playing = false;
                        return Err(anyhow!("Pipeline state recovery failed: {}", e));
                    }
                }
            }

            // If pipeline is in error state, report it
            if current_state == gst::State::Null && self.is_playing {
                warn!("🚨 Pipeline is in NULL state but should be playing");
                self.is_playing = false;
                return Err(anyhow!("Pipeline is in NULL state"));
            }
        }

        Ok(())
    }

    /// Get the bus for message handling
    pub fn get_bus(&self) -> Option<gst::Bus> {
        self.pipeline.as_ref().and_then(|p| p.bus())
    }

    /// Query current position from pipeline
    pub fn query_position(&self) -> Option<u64> {
        // Check test pipeline first, then GES pipeline
        if let Some(test_pipeline) = &self.test_pipeline {
            // Use get_state to get the actual current state including pending changes
            let (_result, current_state, pending_state) = test_pipeline.state(gst::ClockTime::ZERO);
            info!("🔍 Query position (test): current_state = {:?}, pending_state = {:?}", current_state, pending_state);
            
            // Only query position if pipeline is in PLAYING or PAUSED state
            if current_state == gst::State::Playing || current_state == gst::State::Paused ||
               pending_state == gst::State::Playing || pending_state == gst::State::Paused {
                if let Some(position) = test_pipeline.query_position::<gst::ClockTime>() {
                    let position_ns = position.nseconds();
                    let position_ms = (position_ns as f64 / 1_000_000.0) as u64;
                    info!("✅ Position query successful (test): {}ms", position_ms);
                    return Some(position_ms);
                } else {
                    info!("❌ Position query failed (test) - pipeline not ready or no position available");
                }
            } else {
                info!("⚠️ Position query skipped (test) - current_state={:?}, pending_state={:?}", current_state, pending_state);
            }
        } else if let Some(pipeline) = &self.pipeline {
            // Use get_state to get the actual current state including pending changes
            let (_result, current_state, pending_state) = pipeline.state(gst::ClockTime::ZERO);
            info!("🔍 Query position: current_state = {:?}, pending_state = {:?}", current_state, pending_state);
            
            // Only query position if pipeline is in PLAYING or PAUSED state
            // or if it's transitioning to one of these states
            if current_state == gst::State::Playing || current_state == gst::State::Paused ||
               pending_state == gst::State::Playing || pending_state == gst::State::Paused {
                if let Some(position) = pipeline.query_position::<gst::ClockTime>() {
                    let position_ns = position.nseconds();
                    let position_ms = (position_ns as f64 / 1_000_000.0) as u64;
                    info!("✅ Position query successful: {}ms", position_ms);
                    return Some(position_ms);
                } else {
                    info!("❌ Position query failed - pipeline not ready or no position available");
                }
            } else {
                info!("⚠️ Position query skipped - current_state={:?}, pending_state={:?}", current_state, pending_state);
            }
        } else {
            info!("❌ No pipeline available for position query");
        }
        None
    }

    pub fn dispose(&mut self) -> Result<()> {
        self.stop()?;
        self.pipeline = None;
        Ok(())
    }
}
