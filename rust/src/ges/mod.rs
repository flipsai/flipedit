use anyhow::{anyhow, Result};
use gstreamer as gst;
use gstreamer_editing_services as ges;
use gst::prelude::*;
use ges::prelude::*;
use log::{info, warn};
use std::collections::HashMap;
use std::ptr;

use crate::common::types::TimelineClip;

pub mod timeline_bridge;

/// Handle to a GES timeline instance
pub type TimelineHandle = u64;

/// Handle to a GES clip instance  
pub type ClipHandle = u64;

/// Handle to a GES layer instance
pub type LayerHandle = u64;

/// Clip placement result from GES operations
#[derive(Debug, Clone)]
pub struct GESClipPlacement {
    pub clip_id: Option<i32>,
    pub track_id: i32,
    pub start_time_ms: u64,
    pub end_time_ms: u64,
    pub start_time_in_source_ms: u64,
    pub end_time_in_source_ms: u64,
    pub overlapping_clips: Vec<GESOverlapInfo>,
    pub success: bool,
}

/// Information about overlapping clips from GES
#[derive(Debug, Clone)]
pub struct GESOverlapInfo {
    pub clip_id: i32,
    pub start_time_ms: u64,
    pub end_time_ms: u64,
    pub overlap_start_ms: u64,
    pub overlap_end_ms: u64,
    pub action: GESOverlapAction,
}

/// Actions GES can take to resolve overlaps
#[derive(Debug, Clone)]
pub enum GESOverlapAction {
    Remove,
    TrimStart(u64),
    TrimEnd(u64),
    Split(u64),
}

/// GES Timeline wrapper for safe Rust operations
pub struct GESTimelineWrapper {
    pub timeline: ges::Timeline,
    pub layers: HashMap<i32, ges::Layer>,
    pub clips: HashMap<i32, ges::Clip>,
    pub next_clip_id: i32,
    pub framerate: gst::Fraction,
}

// Note: GES Timeline objects are not Send/Sync due to raw pointers
// This is safe because GStreamer is designed to be used from a single thread
// We'll use thread_local storage instead of lazy_static with Mutex
use std::cell::RefCell;

thread_local! {
    static TIMELINE_REGISTRY: RefCell<HashMap<TimelineHandle, GESTimelineWrapper>> = RefCell::new(HashMap::new());
    static NEXT_TIMELINE_HANDLE: RefCell<TimelineHandle> = RefCell::new(1);
}

impl GESTimelineWrapper {
    /// Create a new GES timeline
    pub fn new() -> Result<Self> {
        // Initialize GES if not already done
        ges::init().map_err(|e| anyhow!("Failed to initialize GES: {}", e))?;
        
        info!("Creating new GES timeline");
        
        let timeline = ges::Timeline::new();
        let framerate = gst::Fraction::new(30, 1); // Default to 30fps
        
        // Set timeline properties
        timeline.set_property("auto-transition", true);
        
        Ok(Self {
            timeline,
            layers: HashMap::new(),
            clips: HashMap::new(),
            next_clip_id: 1,
            framerate,
        })
    }
    
    /// Get or create a layer for the given track ID
    pub fn get_or_create_layer(&mut self, track_id: i32) -> Result<&ges::Layer> {
        if !self.layers.contains_key(&track_id) {
            info!("Creating new GES layer for track {}", track_id);
            
            let layer = ges::Layer::new();
            
            // Set layer priority (this will produce a deprecation warning but still works)
            layer.set_priority(track_id as u32);
            
            self.timeline.add_layer(&layer)
                .map_err(|_| anyhow!("Failed to add layer to timeline"))?;
            
            self.layers.insert(track_id, layer);
        }
        
        Ok(self.layers.get(&track_id).unwrap())
    }
    
    /// Add a clip to the timeline using GES
    pub fn add_clip(&mut self, clip_data: &TimelineClip) -> Result<GESClipPlacement> {
        info!("Adding clip to GES timeline: {:?}", clip_data.source_path);
        
        // Ensure the file exists before creating URI
        let file_path = if clip_data.source_path.starts_with("file://") {
            clip_data.source_path[7..].to_string()
        } else {
            clip_data.source_path.clone()
        };
        
        if !std::path::Path::new(&file_path).exists() {
            return Err(anyhow!("Video file not found: {}", file_path));
        }
        
        // Create proper URI for the clip
        let uri = if clip_data.source_path.starts_with("file://") {
            clip_data.source_path.clone()
        } else {
            format!("file://{}", std::path::Path::new(&clip_data.source_path).canonicalize()
                .map_err(|e| anyhow!("Failed to canonicalize path {}: {}", clip_data.source_path, e))?
                .to_string_lossy())
        };
        
        info!("Creating GES URI clip with URI: {}", uri);
        
        // Create GES URI clip with proper error handling
        let ges_clip = ges::UriClip::new(&uri)
            .map_err(|e| anyhow!("Failed to create GES URI clip for {}: {}", uri, e))?;
        
        // Set clip timing
        let start_time = gst::ClockTime::from_mseconds(clip_data.start_time_on_track_ms as u64);
        let duration = gst::ClockTime::from_mseconds(
            (clip_data.end_time_on_track_ms - clip_data.start_time_on_track_ms) as u64
        );
        let in_point = gst::ClockTime::from_mseconds(clip_data.start_time_in_source_ms as u64);
        
        ges_clip.set_start(start_time);
        ges_clip.set_duration(duration);
        ges_clip.set_inpoint(in_point);
        
        // Store clip with assigned ID
        let clip_id = clip_data.id.unwrap_or_else(|| {
            let id = self.next_clip_id;
            self.next_clip_id += 1;
            id
        });
        
        self.clips.insert(clip_id, ges_clip.clone().upcast());
        
        // Get or create the layer for this track
        let layer = self.get_or_create_layer(clip_data.track_id)?;
        
        // Add to layer - GES will handle overlap detection and resolution
        let added = layer.add_clip(&ges_clip.upcast::<ges::Clip>());
        if added.is_err() {
            return Err(anyhow!("Failed to add clip to GES layer"));
        }

        // Commit timeline changes to ensure proper gap handling
        if !self.timeline.commit() {
            warn!("Failed to commit timeline after adding clip");
        }
        
        // Query for any overlaps that GES detected and resolved
        let overlapping_clips = self.find_overlapping_clips(
            clip_data.track_id,
            clip_data.start_time_on_track_ms as u64,
            clip_data.end_time_on_track_ms as u64,
            Some(clip_id),
        )?;
        
        info!("Successfully added clip {} to GES timeline", clip_id);
        
        Ok(GESClipPlacement {
            clip_id: Some(clip_id),
            track_id: clip_data.track_id,
            start_time_ms: clip_data.start_time_on_track_ms as u64,
            end_time_ms: clip_data.end_time_on_track_ms as u64,
            start_time_in_source_ms: clip_data.start_time_in_source_ms as u64,
            end_time_in_source_ms: clip_data.end_time_in_source_ms as u64,
            overlapping_clips,
            success: true,
        })
    }
    
    /// Move a clip to a new position using GES
    pub fn move_clip(&mut self, clip_id: i32, new_track_id: i32, new_start_time_ms: u64) -> Result<GESClipPlacement> {
        info!("Moving clip {} to track {} at {}ms", clip_id, new_track_id, new_start_time_ms);
        
        let clip = self.clips.get(&clip_id)
            .ok_or_else(|| anyhow!("Clip {} not found", clip_id))?
            .clone();
        
        // Get current properties
        let current_duration = clip.duration();
        let current_in_point = clip.inpoint();
        
        // Remove from current layer
        let current_layer = clip.layer()
            .ok_or_else(|| anyhow!("Clip {} has no layer", clip_id))?;
        current_layer.remove_clip(&clip)?;
        
        // Get or create target layer
        let target_layer = self.get_or_create_layer(new_track_id)?;
        
        // Update clip timing
        let new_start_time = gst::ClockTime::from_mseconds(new_start_time_ms);
        clip.set_start(new_start_time);
        
        // Add to new layer
        let added = target_layer.add_clip(&clip);
        if added.is_err() {
            return Err(anyhow!("Failed to add clip to new layer"));
        }

        // Commit timeline changes to ensure proper gap handling
        if !self.timeline.commit() {
            warn!("Failed to commit timeline after moving clip");
        }
        
        // Calculate end time
        let end_time_ms = new_start_time_ms + current_duration.mseconds();
        
        // Find any overlaps
        let overlapping_clips = self.find_overlapping_clips(
            new_track_id,
            new_start_time_ms,
            end_time_ms,
            Some(clip_id),
        )?;
        
        info!("Successfully moved clip {} to track {} at {}ms", clip_id, new_track_id, new_start_time_ms);
        
        Ok(GESClipPlacement {
            clip_id: Some(clip_id),
            track_id: new_track_id,
            start_time_ms: new_start_time_ms,
            end_time_ms,
            start_time_in_source_ms: current_in_point.mseconds(),
            end_time_in_source_ms: current_in_point.mseconds() + current_duration.mseconds(),
            overlapping_clips,
            success: true,
        })
    }
    
    /// Resize a clip using GES trimming
    pub fn resize_clip(&mut self, clip_id: i32, new_start_time_ms: u64, new_end_time_ms: u64) -> Result<GESClipPlacement> {
        info!("Resizing clip {} to {}ms - {}ms", clip_id, new_start_time_ms, new_end_time_ms);
        
        let clip = self.clips.get(&clip_id)
            .ok_or_else(|| anyhow!("Clip {} not found", clip_id))?
            .clone();
        
        // Calculate new duration
        let new_duration = gst::ClockTime::from_mseconds(new_end_time_ms - new_start_time_ms);
        let new_start_time = gst::ClockTime::from_mseconds(new_start_time_ms);
        
        // Update clip timing
        clip.set_start(new_start_time);
        clip.set_duration(new_duration);

        // Commit timeline changes to ensure proper gap handling
        if !self.timeline.commit() {
            warn!("Failed to commit timeline after resizing clip");
        }
        
        // Get track ID from layer
        let layer = clip.layer()
            .ok_or_else(|| anyhow!("Clip {} has no layer", clip_id))?;
        let track_id = layer.priority() as i32;
        
        // Find any overlaps
        let overlapping_clips = self.find_overlapping_clips(
            track_id,
            new_start_time_ms,
            new_end_time_ms,
            Some(clip_id),
        )?;
        
        info!("Successfully resized clip {}", clip_id);
        
        Ok(GESClipPlacement {
            clip_id: Some(clip_id),
            track_id,
            start_time_ms: new_start_time_ms,
            end_time_ms: new_end_time_ms,
            start_time_in_source_ms: clip.inpoint().mseconds(),
            end_time_in_source_ms: clip.inpoint().mseconds() + new_duration.mseconds(),
            overlapping_clips,
            success: true,
        })
    }
    
    /// Remove a clip from the timeline
    pub fn remove_clip(&mut self, clip_id: i32) -> Result<()> {
        info!("Removing clip {} from GES timeline", clip_id);
        
        let clip = self.clips.remove(&clip_id)
            .ok_or_else(|| anyhow!("Clip {} not found", clip_id))?;
        
        if let Some(layer) = clip.layer() {
            layer.remove_clip(&clip)?;
            
            // Commit timeline changes to ensure proper gap handling
            if !self.timeline.commit() {
                warn!("Failed to commit timeline after removing clip");
            }
        }
        
        info!("Successfully removed clip {}", clip_id);
        Ok(())
    }
    
    /// Find overlapping clips in a specific track and time range
    pub fn find_overlapping_clips(
        &self,
        track_id: i32,
        start_time_ms: u64,
        end_time_ms: u64,
        exclude_clip_id: Option<i32>,
    ) -> Result<Vec<GESOverlapInfo>> {
        let mut overlaps = Vec::new();
        
        if let Some(layer) = self.layers.get(&track_id) {
            let clips = layer.clips();
            
            for clip in clips {
                // Get clip ID from our registry
                let clip_id = self.clips.iter()
                    .find(|(_, c)| ptr::eq(c.as_ptr(), clip.as_ptr()))
                    .map(|(id, _)| *id);
                
                if let Some(clip_id) = clip_id {
                    if Some(clip_id) == exclude_clip_id {
                        continue;
                    }
                    
                    let clip_start = clip.start().mseconds();
                    let clip_end = clip_start + clip.duration().mseconds();
                    
                    // Check for overlap
                    if clip_start < end_time_ms && clip_end > start_time_ms {
                        let overlap_start = clip_start.max(start_time_ms);
                        let overlap_end = clip_end.min(end_time_ms);
                        
                        // Determine overlap action based on overlap type
                        let action = if clip_start >= start_time_ms && clip_end <= end_time_ms {
                            GESOverlapAction::Remove
                        } else if clip_start < start_time_ms && clip_end > start_time_ms {
                            GESOverlapAction::TrimEnd(start_time_ms)
                        } else if clip_start < end_time_ms && clip_end > end_time_ms {
                            GESOverlapAction::TrimStart(end_time_ms)
                        } else {
                            GESOverlapAction::Split(start_time_ms)
                        };
                        
                        overlaps.push(GESOverlapInfo {
                            clip_id,
                            start_time_ms: clip_start,
                            end_time_ms: clip_end,
                            overlap_start_ms: overlap_start,
                            overlap_end_ms: overlap_end,
                            action,
                        });
                    }
                }
            }
        }
        
        Ok(overlaps)
    }
    
    /// Get all clips in the timeline as TimelineClip data for the renderer
    pub fn get_timeline_data(&self) -> Result<Vec<TimelineClip>> {
        let mut clips = Vec::new();
        
        for (track_id, layer) in &self.layers {
            let layer_clips = layer.clips();
            
            for clip in layer_clips {
                if let Some(uri_clip) = clip.downcast_ref::<ges::UriClip>() {
                    // Get clip ID from registry
                    let clip_id = self.clips.iter()
                        .find(|(_, c)| ptr::eq(c.as_ptr(), clip.as_ptr()))
                        .map(|(id, _)| *id);
                    
                    let uri = uri_clip.uri();
                    let source_path = if uri.starts_with("file://") {
                        uri[7..].to_string()
                    } else {
                        uri.to_string()
                    };
                    
                    clips.push(TimelineClip {
                        id: clip_id,
                        track_id: *track_id,
                        source_path,
                        start_time_on_track_ms: clip.start().mseconds() as i32,
                        end_time_on_track_ms: (clip.start() + clip.duration()).mseconds() as i32,
                        start_time_in_source_ms: clip.inpoint().mseconds() as i32,
                        end_time_in_source_ms: (clip.inpoint() + clip.duration()).mseconds() as i32,
                        preview_position_x: 0.0, // Will be set by renderer
                        preview_position_y: 0.0,
                        preview_width: 1920.0,
                        preview_height: 1080.0,
                    });
                }
            }
        }
        
        Ok(clips)
    }
    
    /// Get timeline duration in milliseconds
    pub fn get_duration_ms(&self) -> u64 {
        let mut max_end_time = 0u64;
        
        for layer in self.layers.values() {
            let clips = layer.clips();
            for clip in clips {
                let end_time = (clip.start() + clip.duration()).mseconds();
                max_end_time = max_end_time.max(end_time);
            }
        }
        
        max_end_time
    }
}

/// Create a new GES timeline and return its handle
pub fn create_timeline() -> Result<TimelineHandle> {
    let timeline = GESTimelineWrapper::new()?;
    
    let handle = NEXT_TIMELINE_HANDLE.with(|next_handle| {
        let mut handle = next_handle.borrow_mut();
        let current = *handle;
        *handle += 1;
        current
    });
    
    TIMELINE_REGISTRY.with(|registry| {
        registry.borrow_mut().insert(handle, timeline);
    });
    
    info!("Created GES timeline with handle {}", handle);
    Ok(handle)
}

/// Execute a function with a timeline by handle
pub fn with_timeline<F, R>(handle: TimelineHandle, f: F) -> Result<R>
where
    F: FnOnce(&mut GESTimelineWrapper) -> Result<R>,
{
    TIMELINE_REGISTRY.with(|registry| {
        let mut registry = registry.borrow_mut();
        let timeline = registry.get_mut(&handle)
            .ok_or_else(|| anyhow!("Timeline handle {} not found", handle))?;
        f(timeline)
    })
}

/// Destroy a timeline and free its resources
pub fn destroy_timeline(handle: TimelineHandle) -> Result<()> {
    TIMELINE_REGISTRY.with(|registry| {
        registry.borrow_mut().remove(&handle)
            .ok_or_else(|| anyhow!("Timeline handle {} not found", handle))?;
        
        info!("Destroyed GES timeline with handle {}", handle);
        Ok(())
    })
}