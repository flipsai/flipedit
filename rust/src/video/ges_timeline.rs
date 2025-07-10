use anyhow::{anyhow, Result};
use gstreamer_editing_services as ges;
use gstreamer as gst;
use ges::prelude::*;
use log::{info, warn};
use crate::common::types::{TimelineData, TimelineClip};

/// GES Timeline Manager - handles creating and managing GES timelines
pub struct GESTimelineManager {
    timeline: Option<ges::Timeline>,
    duration_ms: Option<u64>,
}

impl GESTimelineManager {
    pub fn new() -> Self {
        Self {
            timeline: None,
            duration_ms: None,
        }
    }

    /// Create a simple test timeline with black background
    pub fn create_test_timeline(&mut self) -> Result<ges::Timeline> {
        info!("Creating simple GES timeline with 10-second black background for testing");
        
        // Initialize GES if not already done
        ges::init().map_err(|e| anyhow!("Failed to initialize GStreamer Editing Services: {}", e))?;
        
        // Create GES timeline with standard single video and audio tracks
        let timeline = ges::Timeline::new_audio_video();
        
        // Create a layer for our test content
        let layer = timeline.append_layer();
        
        // Create a 10-second black test clip
        let test_clip = ges::TestClip::for_nick("black")
            .ok_or_else(|| anyhow!("Failed to create TestClip for black pattern"))?;
        
        // Set the duration to 10 seconds (10000ms = 10,000,000,000 nanoseconds)
        let duration_ns = 10_000_000_000u64; // 10 seconds in nanoseconds
        test_clip.set_duration(gst::ClockTime::from_nseconds(duration_ns));
        test_clip.set_start(gst::ClockTime::from_nseconds(0));
        
        // Add the test clip to the layer - GES automatically handles track element creation
        layer.add_clip(&test_clip)?;
        
        info!("Added 10-second black test clip to GES timeline");
        
        // Store timeline and duration
        self.timeline = Some(timeline.clone());
        self.duration_ms = Some(10000); // 10 seconds
        
        Ok(timeline)
    }

    /// Create a timeline from provided timeline data
    pub fn create_timeline_from_data(&mut self, timeline_data: TimelineData) -> Result<ges::Timeline> {
        info!("Creating GES timeline from data with {} Flutter tracks", timeline_data.tracks.len());
        
        // Initialize GES if not already done
        ges::init().map_err(|e| anyhow!("Failed to initialize GStreamer Editing Services: {}", e))?;
        
        // Create GES timeline with single video and audio tracks (GES standard)
        let timeline = ges::Timeline::new_audio_video();
        
        // Get all clips from all tracks for duration calculation
        let all_clips: Vec<_> = timeline_data.tracks.iter().flat_map(|t| &t.clips).collect();
        
        if all_clips.is_empty() {
            info!("No clips found, creating timeline with test background");
            return self.create_test_timeline();
        }
        
        // Calculate timeline duration
        let max_clip_end = all_clips
            .iter()
            .map(|clip| clip.end_time_on_track_ms as u64)
            .max()
            .unwrap_or(10000);
        let duration_ms = max_clip_end.max(1000); // At least 1 second
        
        info!("Timeline duration: {}ms with {} total clips across {} Flutter tracks", duration_ms, all_clips.len(), timeline_data.tracks.len());
        
        // Create layers for organizing clips (one layer per Flutter track)
        let mut clips_added = 0;
        for (track_index, track_data) in timeline_data.tracks.iter().enumerate() {
            if track_data.clips.is_empty() {
                info!("Flutter track {} is empty, skipping", track_index);
                continue;
            }
            
            info!("Creating layer for Flutter track {} with {} clips", track_index, track_data.clips.len());
            
            // Create a layer for this Flutter track
            let layer = timeline.append_layer();
            
            // Add each clip to the layer - GES will automatically create track elements 
            // and assign them to the single video/audio tracks
            for (clip_index, clip) in track_data.clips.iter().enumerate() {
                if let Err(e) = self.add_clip_to_layer(&layer, clip, track_index, clip_index) {
                    warn!("Failed to add clip {} from track {}: {}, skipping", clip_index, track_index, e);
                    continue;
                }
                clips_added += 1;
            }
        }
        
        // If no clips were successfully added, fall back to test timeline
        if clips_added == 0 {
            warn!("⚠️ No clips could be loaded, falling back to test timeline");
            return self.create_test_timeline();
        }
        
        // Store timeline and duration
        self.timeline = Some(timeline.clone());
        self.duration_ms = Some(duration_ms);
        
        info!("GES timeline created successfully with {} layers (from Flutter tracks) and {} clips", timeline_data.tracks.len(), clips_added);
        Ok(timeline)
    }
    
    /// Add a single clip to a GES layer
    fn add_clip_to_layer(&self, layer: &ges::Layer, clip: &TimelineClip, track_index: usize, clip_index: usize) -> Result<()> {
        // Check if file exists
        if !std::path::Path::new(&clip.source_path).exists() {
            return Err(anyhow!("Video file does not exist: {}", clip.source_path));
        }
        
        let uri = format!("file://{}", clip.source_path);
        info!("🎬 Adding clip {} to GES track {}: {} (track: {}ms-{}ms, source: {}ms)", 
              clip_index + 1, track_index, uri, clip.start_time_on_track_ms, clip.end_time_on_track_ms, clip.start_time_in_source_ms);
        
        // Check for potential problematic formats that cause libav errors
        let file_extension = std::path::Path::new(&clip.source_path)
            .extension()
            .and_then(|ext| ext.to_str())
            .unwrap_or("")
            .to_lowercase();
        
        if matches!(file_extension.as_str(), "mov" | "m4v" | "3gp") {
            warn!("⚠️ Video format '{}' may cause reference frame errors. Consider using MP4/WebM for better compatibility.", file_extension);
        }
        
        // Validate timing values
        if clip.end_time_on_track_ms <= clip.start_time_on_track_ms {
            return Err(anyhow!("Invalid clip timing: end ({}) <= start ({})", 
                              clip.end_time_on_track_ms, clip.start_time_on_track_ms));
        }
        
        // Create GES asset first for proper discovery
        info!("🔍 Discovering asset for: {}", uri);
        let asset = ges::UriClipAsset::request_sync(&uri)
            .map_err(|e| anyhow!("Failed to create asset for {}: {} (possible codec/format issue)", uri, e))?;
        
        // Create GES clip from asset
        info!("🎬 Extracting clip from asset");
        let ges_clip = asset.extract()?.downcast::<ges::UriClip>()
            .map_err(|_| anyhow!("Failed to downcast extracted clip to UriClip"))?;
        
        // Set clip timing (convert ms to nanoseconds)
        let start_time = (clip.start_time_on_track_ms as u64) * gst::ClockTime::MSECOND.nseconds();
        let clip_duration = ((clip.end_time_on_track_ms - clip.start_time_on_track_ms) as u64) * gst::ClockTime::MSECOND.nseconds();
        let in_point = (clip.start_time_in_source_ms as u64) * gst::ClockTime::MSECOND.nseconds();
        
        info!("⏰ Setting timing - start: {}ns, duration: {}ns, in_point: {}ns", 
              start_time, clip_duration, in_point);
        
        ges_clip.set_start(gst::ClockTime::from_nseconds(start_time));
        ges_clip.set_duration(gst::ClockTime::from_nseconds(clip_duration));
        ges_clip.set_inpoint(gst::ClockTime::from_nseconds(in_point));
        
        // Add clip to layer - GES automatically creates track elements and assigns them 
        // to the timeline's single video/audio tracks based on the clip's content
        layer.add_clip(&ges_clip)?;
        
        info!("✅ Added GES clip to layer {} (Flutter track {}): start={}ms, duration={}ms, in_point={}ms", 
              layer.priority(), track_index,
              clip.start_time_on_track_ms, 
              clip.end_time_on_track_ms - clip.start_time_on_track_ms,
              clip.start_time_in_source_ms);
        
        Ok(())
    }

    pub fn get_timeline(&self) -> Option<&ges::Timeline> {
        self.timeline.as_ref()
    }

    pub fn get_duration_ms(&self) -> Option<u64> {
        self.duration_ms
    }

    pub fn dispose(&mut self) {
        self.timeline = None;
        self.duration_ms = None;
    }
}