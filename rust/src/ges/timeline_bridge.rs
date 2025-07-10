use flutter_rust_bridge::frb;
use anyhow::Result;
use log::info;
use gstreamer_editing_services::prelude::*;

use crate::common::types::TimelineClip;
use super::{TimelineHandle, GESClipPlacement, GESOverlapInfo, GESOverlapAction};
use super::{create_timeline as create_timeline_internal, with_timeline, destroy_timeline as destroy_timeline_internal};

/// Data structure for clip placement results that can cross the FFI boundary
#[derive(Debug, Clone)]
pub struct ClipPlacementResult {
    pub clip_id: Option<i32>,
    pub track_id: i32,
    pub start_time_ms: u64,
    pub end_time_ms: u64,
    pub start_time_in_source_ms: u64,
    pub end_time_in_source_ms: u64,
    pub overlapping_clips: Vec<OverlapInfo>,
    pub success: bool,
}

/// Overlap information that can cross the FFI boundary
#[derive(Debug, Clone)]
pub struct OverlapInfo {
    pub clip_id: i32,
    pub start_time_ms: u64,
    pub end_time_ms: u64,
    pub overlap_start_ms: u64,
    pub overlap_end_ms: u64,
    pub action_type: String, // "remove", "trim_start", "trim_end", "split"
    pub action_time_ms: Option<u64>,
}

impl From<GESClipPlacement> for ClipPlacementResult {
    fn from(placement: GESClipPlacement) -> Self {
        Self {
            clip_id: placement.clip_id,
            track_id: placement.track_id,
            start_time_ms: placement.start_time_ms,
            end_time_ms: placement.end_time_ms,
            start_time_in_source_ms: placement.start_time_in_source_ms,
            end_time_in_source_ms: placement.end_time_in_source_ms,
            overlapping_clips: placement.overlapping_clips.into_iter().map(Into::into).collect(),
            success: placement.success,
        }
    }
}

impl From<GESOverlapInfo> for OverlapInfo {
    fn from(info: GESOverlapInfo) -> Self {
        let (action_type, action_time_ms) = match info.action {
            GESOverlapAction::Remove => ("remove".to_string(), None),
            GESOverlapAction::TrimStart(time) => ("trim_start".to_string(), Some(time)),
            GESOverlapAction::TrimEnd(time) => ("trim_end".to_string(), Some(time)),
            GESOverlapAction::Split(time) => ("split".to_string(), Some(time)),
        };
        
        Self {
            clip_id: info.clip_id,
            start_time_ms: info.start_time_ms,
            end_time_ms: info.end_time_ms,
            overlap_start_ms: info.overlap_start_ms,
            overlap_end_ms: info.overlap_end_ms,
            action_type,
            action_time_ms,
        }
    }
}

/// Create a new GES timeline
#[frb(sync)]
pub fn ges_create_timeline() -> Result<TimelineHandle> {
    info!("Creating new GES timeline via bridge");
    create_timeline_internal()
}

/// Destroy a GES timeline
#[frb(sync)]
pub fn ges_destroy_timeline(handle: TimelineHandle) -> Result<()> {
    info!("Destroying GES timeline {} via bridge", handle);
    destroy_timeline_internal(handle)
}

/// Add a clip to the GES timeline
#[frb(sync)]
pub fn ges_add_clip(handle: TimelineHandle, clip_data: TimelineClip) -> Result<ClipPlacementResult> {
    info!("Adding clip to GES timeline {} via bridge: {:?}", handle, clip_data.source_path);
    
    with_timeline(handle, |timeline| {
        let result = timeline.add_clip(&clip_data)?;
        Ok(result.into())
    })
}

/// Move a clip in the GES timeline
#[frb(sync)]
pub fn ges_move_clip(handle: TimelineHandle, clip_id: i32, new_track_id: i32, new_start_time_ms: u64) -> Result<ClipPlacementResult> {
    info!("Moving clip {} in GES timeline {} to track {} at {}ms", clip_id, handle, new_track_id, new_start_time_ms);
    
    with_timeline(handle, |timeline| {
        let result = timeline.move_clip(clip_id, new_track_id, new_start_time_ms)?;
        Ok(result.into())
    })
}

/// Resize a clip in the GES timeline
#[frb(sync)]
pub fn ges_resize_clip(handle: TimelineHandle, clip_id: i32, new_start_time_ms: u64, new_end_time_ms: u64) -> Result<ClipPlacementResult> {
    info!("Resizing clip {} in GES timeline {} to {}ms - {}ms", clip_id, handle, new_start_time_ms, new_end_time_ms);
    
    with_timeline(handle, |timeline| {
        let result = timeline.resize_clip(clip_id, new_start_time_ms, new_end_time_ms)?;
        Ok(result.into())
    })
}

/// Remove a clip from the GES timeline
#[frb(sync)]
pub fn ges_remove_clip(handle: TimelineHandle, clip_id: i32) -> Result<()> {
    info!("Removing clip {} from GES timeline {}", clip_id, handle);
    
    with_timeline(handle, |timeline| {
        timeline.remove_clip(clip_id)
    })
}

/// Find overlapping clips in a specific track and time range
#[frb(sync)]
pub fn ges_find_overlapping_clips(
    handle: TimelineHandle,
    track_id: i32,
    start_time_ms: u64,
    end_time_ms: u64,
    exclude_clip_id: Option<i32>,
) -> Result<Vec<OverlapInfo>> {
    with_timeline(handle, |timeline| {
        let overlaps = timeline.find_overlapping_clips(track_id, start_time_ms, end_time_ms, exclude_clip_id)?;
        Ok(overlaps.into_iter().map(Into::into).collect())
    })
}

/// Get all clips in the timeline for rendering
#[frb(sync)]
pub fn ges_get_timeline_data(handle: TimelineHandle) -> Result<Vec<TimelineClip>> {
    with_timeline(handle, |timeline| {
        timeline.get_timeline_data()
    })
}

/// Get timeline duration in milliseconds
#[frb(sync)]
pub fn ges_get_timeline_duration_ms(handle: TimelineHandle) -> Result<u64> {
    with_timeline(handle, |timeline| {
        Ok(timeline.get_duration_ms())
    })
}

/// Calculate optimal clip placement with overlap resolution
#[frb(sync)]
pub fn ges_calculate_clip_placement(
    handle: TimelineHandle,
    clip_data: TimelineClip,
) -> Result<ClipPlacementResult> {
    info!("Calculating clip placement for GES timeline {}", handle);
    
    with_timeline(handle, |timeline| {
        // Find overlaps without adding the clip first
        let overlaps = timeline.find_overlapping_clips(
            clip_data.track_id,
            clip_data.start_time_on_track_ms as u64,
            clip_data.end_time_on_track_ms as u64,
            clip_data.id,
        )?;
        
        // Create placement result with overlap information
        let result = ClipPlacementResult {
            clip_id: clip_data.id,
            track_id: clip_data.track_id,
            start_time_ms: clip_data.start_time_on_track_ms as u64,
            end_time_ms: clip_data.end_time_on_track_ms as u64,
            start_time_in_source_ms: clip_data.start_time_in_source_ms as u64,
            end_time_in_source_ms: clip_data.end_time_in_source_ms as u64,
            overlapping_clips: overlaps.into_iter().map(Into::into).collect(),
            success: true,
        };
        
        Ok(result)
    })
}

/// Validate a clip operation without actually performing it
#[frb(sync)]
pub fn ges_validate_clip_operation(
    handle: TimelineHandle,
    clip_data: TimelineClip,
) -> Result<bool> {
    with_timeline(handle, |timeline| {
        // Check if the operation would be valid
        // For now, we consider all operations valid if they don't exceed timeline bounds
        let _duration_ms = timeline.get_duration_ms();
        
        let valid = clip_data.start_time_on_track_ms >= 0 &&
                    clip_data.end_time_on_track_ms > clip_data.start_time_on_track_ms &&
                    clip_data.start_time_in_source_ms >= 0 &&
                    clip_data.end_time_in_source_ms > clip_data.start_time_in_source_ms;
        
        Ok(valid)
    })
}

/// Perform a ripple edit operation (move clip and shift following clips)
#[frb(sync)]
pub fn ges_ripple_edit(
    handle: TimelineHandle,
    clip_id: i32,
    new_start_time_ms: u64,
) -> Result<Vec<ClipPlacementResult>> {
    info!("Performing ripple edit on clip {} in timeline {}", clip_id, handle);
    
    with_timeline(handle, |timeline| {
        // Get the clip being moved
        let clip = timeline.clips.get(&clip_id)
            .ok_or_else(|| anyhow::anyhow!("Clip {} not found", clip_id))?
            .clone();
        
        let current_start = clip.start().mseconds();
        let delta = new_start_time_ms as i64 - current_start as i64;
        
        if delta == 0 {
            return Ok(vec![]); // No change needed
        }
        
        // Get track ID
        let layer = clip.layer()
            .ok_or_else(|| anyhow::anyhow!("Clip {} has no layer", clip_id))?;
        let track_id = layer.priority() as i32;
        
        let mut results = Vec::new();
        
        // Move the primary clip
        let result = timeline.move_clip(clip_id, track_id, new_start_time_ms)?;
        results.push(result.into());
        
        // If moving forward (delta > 0), shift clips that start after the original position
        // If moving backward (delta < 0), shift clips that would overlap
        if delta > 0 {
            // Moving forward - shift clips that come after the original end position
            let original_end = current_start + clip.duration().mseconds();
            
            // Collect clips that need to be moved to avoid borrowing issues
            let clips_to_move: Vec<_> = timeline.clips.iter()
                .filter(|(other_clip_id, other_clip)| {
                    if **other_clip_id == clip_id {
                        return false;
                    }
                    
                    if let Some(other_layer) = other_clip.layer() {
                        if other_layer.priority() as i32 == track_id {
                            let other_start = other_clip.start().mseconds();
                            return other_start >= original_end;
                        }
                    }
                    false
                })
                .map(|(other_clip_id, other_clip)| (*other_clip_id, other_clip.start().mseconds()))
                .collect();
            
            // Now move the clips
            for (other_clip_id, other_start) in clips_to_move {
                let new_other_start = other_start + delta as u64;
                let result = timeline.move_clip(other_clip_id, track_id, new_other_start)?;
                results.push(result.into());
            }
        } else {
            // Moving backward - shift clips that would overlap with the new position
            let new_end = new_start_time_ms + clip.duration().mseconds();
            
            // Collect clips that need to be moved to avoid borrowing issues
            let clips_to_move: Vec<_> = timeline.clips.iter()
                .filter(|(other_clip_id, other_clip)| {
                    if **other_clip_id == clip_id {
                        return false;
                    }
                    
                    if let Some(other_layer) = other_clip.layer() {
                        if other_layer.priority() as i32 == track_id {
                            let other_start = other_clip.start().mseconds();
                            let other_end = other_start + other_clip.duration().mseconds();
                            
                            // If other clip overlaps with new position, shift it
                            return other_start < new_end && other_end > new_start_time_ms;
                        }
                    }
                    false
                })
                .map(|(other_clip_id, _)| *other_clip_id)
                .collect();
            
            // Now move the clips
            for other_clip_id in clips_to_move {
                let new_other_start = new_end;
                let result = timeline.move_clip(other_clip_id, track_id, new_other_start)?;
                results.push(result.into());
            }
        }
        
        info!("Ripple edit completed, affected {} clips", results.len());
        Ok(results)
    })
}

/// Get frame position in milliseconds based on frame number and framerate
#[frb(sync)]
pub fn ges_frame_to_ms(frame_number: i32, framerate_num: i32, framerate_den: i32) -> u64 {
    let frame_duration_ms = (framerate_den as f64 / framerate_num as f64) * 1000.0;
    (frame_number as f64 * frame_duration_ms) as u64
}

/// Get frame number from milliseconds based on framerate  
#[frb(sync)]
pub fn ges_ms_to_frame(time_ms: u64, framerate_num: i32, framerate_den: i32) -> i32 {
    let frame_duration_ms = (framerate_den as f64 / framerate_num as f64) * 1000.0;
    (time_ms as f64 / frame_duration_ms).floor() as i32
}