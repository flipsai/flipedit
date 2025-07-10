use anyhow::{anyhow, Result};
use ges::prelude::*;
use gst::prelude::*;
use gstreamer as gst;
use gstreamer_editing_services as ges;
use log::{info, warn};
use std::sync::{Arc, Mutex};

/// GES Pipeline Manager - handles GES pipeline creation and management
pub struct GESPipelineManager {
    pipeline: Option<ges::Pipeline>,
    current_position_ms: Arc<Mutex<u64>>,
    is_playing: bool,
}

impl GESPipelineManager {
    pub fn new() -> Self {
        Self {
            pipeline: None,
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
        pipeline.set_timeline(timeline)?;

        // Set up video output
        pipeline.preview_set_video_sink(Some(video_sink));

        // Configure audio sink to reduce underflow issues
        self.configure_audio_sink(&pipeline)?;

        self.pipeline = Some(pipeline);

        info!("GES pipeline created successfully");
        Ok(())
    }

    /// Configure audio sink to reduce underflow warnings
    fn configure_audio_sink(&self, pipeline: &ges::Pipeline) -> Result<()> {
        // Create a custom audio sink with larger buffer to prevent underflows
        let audio_sink = gst::ElementFactory::make("pulsesink")
            .name("custom_audio_sink")
            .property("buffer-time", 200000i64) // 200ms buffer (larger than default)
            .property("latency-time", 20000i64) // 20ms latency
            .property("sync", true)
            .build()
            .map_err(|e| anyhow!("Failed to create custom audio sink: {}", e))?;

        pipeline.preview_set_audio_sink(Some(&audio_sink));
        info!("Configured custom audio sink with larger buffer to reduce underflows");

        Ok(())
    }

    /// Start playback
    pub fn play(&mut self) -> Result<()> {
        let pipeline = self
            .pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("No GES pipeline available for playback"))?;

        info!("Setting GES pipeline to PLAYING");

        // Set pipeline to PLAYING state
        match pipeline.set_state(gst::State::Playing) {
            Ok(gst::StateChangeSuccess::Success) => {
                info!("✅ GES pipeline set to PLAYING successfully");
                self.is_playing = true;
                Ok(())
            }
            Ok(gst::StateChangeSuccess::Async) => {
                info!("⏳ GES pipeline transitioning to PLAYING asynchronously");
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

    /// Pause playback
    pub fn pause(&mut self) -> Result<()> {
        let pipeline = self
            .pipeline
            .as_ref()
            .ok_or_else(|| anyhow!("No GES pipeline available for pause"))?;

        info!("Setting GES pipeline to PAUSED");

        match pipeline.set_state(gst::State::Paused) {
            Ok(_) => {
                info!("✅ GES pipeline paused successfully");
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

    /// Stop playback
    pub fn stop(&mut self) -> Result<()> {
        if let Some(pipeline) = &self.pipeline {
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
            info!("✅ GES pipeline seek successful to {}ms", position_ms);
            *self.current_position_ms.lock().unwrap() = position_ms;

            // If we were playing before seek, make sure we're still in playing state
            if was_playing {
                info!("🔄 Restoring PLAYING state after seek");
                match pipeline.set_state(gst::State::Playing) {
                    Ok(_) => {
                        info!("✅ Successfully restored PLAYING state after seek");
                        self.is_playing = true;
                    }
                    Err(e) => {
                        warn!("⚠️ Failed to restore PLAYING state after seek: {}", e);
                        self.is_playing = false;
                    }
                }
            } else {
                // If we weren't playing, ensure we're in PAUSED state for frame display
                info!("🔄 Setting PAUSED state after seek for frame display");
                match pipeline.set_state(gst::State::Paused) {
                    Ok(_) => {
                        info!("✅ Successfully set PAUSED state after seek");
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

    /// Query current position from pipeline
    pub fn query_position(&self) -> Option<u64> {
        if let Some(pipeline) = &self.pipeline {
            if let Some(position) = pipeline.query_position::<gst::ClockTime>() {
                let position_ns = position.nseconds();
                let position_ms = (position_ns as f64 / 1_000_000.0) as u64;
                return Some(position_ms);
            }
        }
        None
    }

    pub fn dispose(&mut self) -> Result<()> {
        self.stop()?;
        self.pipeline = None;
        Ok(())
    }
}
