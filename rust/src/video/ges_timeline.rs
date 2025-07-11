use anyhow::{anyhow, Result};
use gstreamer_editing_services as ges;
use gstreamer as gst;
use ges::prelude::*;
use log::{info, warn};
use crate::common::types::{TimelineData, TimelineClip};
use std::sync::Once;

static INIT: Once = Once::new();

/// GES Timeline Manager - handles creating and managing GES timelines
pub struct GESTimelineManager {
    timeline: Option<ges::Timeline>,
    project: Option<ges::Project>,
    duration_ms: Option<u64>,
}

impl GESTimelineManager {
    pub fn new() -> Self {
        Self {
            timeline: None,
            project: None,
            duration_ms: None,
        }
    }

    /// Create a simple test timeline with black background
    pub fn create_test_timeline(&mut self) -> Result<ges::Timeline> {
        info!("Creating simple GES timeline with 10-second black background for testing");
        
        // Initialize GES if not already done - use Once to ensure it happens only once
        INIT.call_once(|| {
            if let Err(e) = ges::init() {
                warn!("Failed to initialize GStreamer Editing Services: {}", e);
            } else {
                info!("GStreamer Editing Services initialized successfully");
            }
        });
        
        // Create GES timeline with standard single video and audio tracks
        let timeline = ges::Timeline::new_audio_video();
        
        // Set timeline properties for better performance
        timeline.set_property("auto-transition", false);
        
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
        
        // Initialize GES if not already done - use Once to ensure it happens only once
        INIT.call_once(|| {
            if let Err(e) = ges::init() {
                warn!("Failed to initialize GStreamer Editing Services: {}", e);
            } else {
                info!("GStreamer Editing Services initialized successfully");
            }
        });
        
        // Create GES project first - this manages assets and reduces discoverer warnings
        let project = ges::Project::new(None);
        
        // Create GES timeline with single video and audio tracks (GES standard)
        let timeline = ges::Timeline::new_audio_video();
        
        // Set timeline properties for better performance
        timeline.set_property("auto-transition", false); // Disable automatic transitions initially
        
        // Get all clips from all tracks for duration calculation
        let all_clips: Vec<_> = timeline_data.tracks.iter().flat_map(|t| &t.clips).collect();
        
        println!("📊 Timeline analysis: {} total clips found across {} tracks", all_clips.len(), timeline_data.tracks.len());
        info!("📊 Timeline analysis: {} total clips found across {} tracks", all_clips.len(), timeline_data.tracks.len());
        for (track_idx, track) in timeline_data.tracks.iter().enumerate() {
            println!("  Track {}: {} clips", track_idx, track.clips.len());
            info!("  Track {}: {} clips", track_idx, track.clips.len());
            for (clip_idx, clip) in track.clips.iter().enumerate() {
                println!("    Clip {}: {} ({}ms-{}ms)", clip_idx, clip.source_path, 
                          clip.start_time_on_track_ms, clip.end_time_on_track_ms);
                info!("    Clip {}: {} ({}ms-{}ms)", clip_idx, clip.source_path, 
                      clip.start_time_on_track_ms, clip.end_time_on_track_ms);
            }
        }
        
        if all_clips.is_empty() {
            warn!("⚠️ No clips found in timeline data, creating test timeline with black background");
            return self.create_test_timeline();
        }
        
        // Calculate timeline duration based on the furthest end position (not clip durations)
        let max_end_time = all_clips
            .iter()
            .map(|clip| clip.end_time_on_track_ms as u64)
            .max()
            .unwrap_or(10000);
        let duration_ms = max_end_time.max(1000); // At least 1 second
        
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
                println!("🎬 Attempting to add clip {} from track {}: {}", clip_index, track_index, clip.source_path);
                info!("🎬 Attempting to add clip {} from track {}: {}", clip_index, track_index, clip.source_path);
                if let Err(e) = self.add_clip_to_layer(&project, &layer, clip, track_index, clip_index) {
                    println!("❌ Failed to add clip {} from track {}: {}, skipping", clip_index, track_index, e);
                    warn!("❌ Failed to add clip {} from track {}: {}, skipping", clip_index, track_index, e);
                    continue;
                }
                println!("✅ Successfully added clip {} from track {}", clip_index, track_index);
                info!("✅ Successfully added clip {} from track {}", clip_index, track_index);
                clips_added += 1;
            }
        }
        
        // If no clips were successfully added, fall back to test timeline
        if clips_added == 0 {
            println!("⚠️ No clips could be loaded successfully (had {} clips to try), falling back to test timeline with black background", all_clips.len());
            println!("This means you'll see a black screen instead of your video - check file paths and formats");
            warn!("⚠️ No clips could be loaded successfully (had {} clips to try), falling back to test timeline with black background", all_clips.len());
            warn!("This means you'll see a black screen instead of your video - check file paths and formats");
            return self.create_test_timeline();
        }
        
        // Commit the timeline to finalize all changes
        println!("🔄 Committing timeline with {} clips", clips_added);
        if !timeline.commit() {
            return Err(anyhow!("Failed to commit timeline changes"));
        }
        println!("✅ Timeline committed successfully");
        
        // Store timeline, project, and duration
        self.timeline = Some(timeline.clone());
        self.project = Some(project);
        self.duration_ms = Some(duration_ms);
        
        println!("🎉 GES timeline created successfully with {} layers and {} clips", timeline_data.tracks.len(), clips_added);
        info!("GES timeline created successfully with {} layers (from Flutter tracks) and {} clips", timeline_data.tracks.len(), clips_added);
        Ok(timeline)
    }
    
    /// Add a single clip to a GES layer
    fn add_clip_to_layer(&self, project: &ges::Project, layer: &ges::Layer, clip: &TimelineClip, track_index: usize, clip_index: usize) -> Result<()> {
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
        
        // Create GES asset using project-based approach (recommended by GES guide)
        info!("🔍 Creating asset via project for: {}", uri);
        
        // Validate URI format before creating asset
        if !uri.starts_with("file://") || uri.len() <= 7 {
            return Err(anyhow!("Invalid URI format: {}", uri));
        }
        
        // Create the asset using the direct approach since project.create_asset_sync has type issues
        let uri_asset = ges::UriClipAsset::request_sync(&uri)
            .map_err(|e| anyhow!("Failed to create asset for {}: {} (possible codec/format issue)", uri, e))?;
        
        info!("✅ Asset created successfully via project for: {}", uri);
        
        // Create GES clip from asset
        info!("🎬 Extracting clip from asset");
        let ges_clip = uri_asset.extract()?.downcast::<ges::UriClip>()
            .map_err(|_| anyhow!("Failed to downcast extracted clip to UriClip"))?;
        
        // Set clip timing (convert ms to nanoseconds)
        // For now, let's start all clips at 0 to avoid composition issues
        let start_time = clip.start_time_on_track_ms as u64 * gst::ClockTime::MSECOND.nseconds();
        let clip_duration = ((clip.end_time_on_track_ms - clip.start_time_on_track_ms) as u64) * gst::ClockTime::MSECOND.nseconds();
        let in_point = (clip.start_time_in_source_ms as u64) * gst::ClockTime::MSECOND.nseconds();
        
        println!("⏰ Setting timing - start: {}ns, duration: {}ns, in_point: {}ns", 
                 start_time, clip_duration, in_point);
        info!("⏰ Setting timing - start: {}ns, duration: {}ns, in_point: {}ns", 
              start_time, clip_duration, in_point);
        
        ges_clip.set_start(gst::ClockTime::from_nseconds(start_time));
        ges_clip.set_duration(gst::ClockTime::from_nseconds(clip_duration));
        ges_clip.set_inpoint(gst::ClockTime::from_nseconds(in_point));
        
        // Add clip to layer - GES automatically creates track elements and assigns them 
        // to the timeline's single video/audio tracks based on the clip's content
        layer.add_clip(&ges_clip)?;
        
        println!("✅ Added GES clip to layer {} (Flutter track {}): start={}ms, duration={}ms, in_point={}ms", 
                 layer.priority(), track_index,
                 clip.start_time_on_track_ms, // Show actual start time
                 clip.end_time_on_track_ms - clip.start_time_on_track_ms,
                 clip.start_time_in_source_ms);
        info!("✅ Added GES clip to layer {} (Flutter track {}): start={}ms, duration={}ms, in_point={}ms", 
              layer.priority(), track_index,
              clip.start_time_on_track_ms, // Show actual start time
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
        self.project = None;
        self.duration_ms = None;
    }
}