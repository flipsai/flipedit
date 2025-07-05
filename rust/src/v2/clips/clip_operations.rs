//! Common clip operations like move, resize, trim

use anyhow::{Result, Context};
use gstreamer_editing_services as ges;
use gstreamer as gst;
use gstreamer_editing_services::prelude::*; // For ClipExt, TimelineElementExt, GESContainerExt
use log::{info, debug, warn};

// ClipInfo and AudioClip are unused based on diagnostics, VideoClip is used by functions
use super::{VideoClip};

/// Move a clip to a new position on the timeline
pub fn move_clip(clip: &mut VideoClip, new_start: u64) -> Result<()> {
    clip.set_start(new_start)?;
    debug!("Moved clip {} to start position {}ns", clip.get_info().id, new_start);
    Ok(())
}

/// Resize a clip by changing its duration
pub fn resize_clip(clip: &mut VideoClip, new_duration: u64) -> Result<()> {
    clip.set_duration(new_duration)?;
    debug!("Resized clip {} to duration {}ns", clip.get_info().id, new_duration);
    Ok(())
}

/// Trim a clip by adjusting its in-point and duration
pub fn trim_clip(clip: &mut VideoClip, new_in_point: u64, new_duration: u64) -> Result<()> {
    clip.set_in_point(new_in_point)?;
    clip.set_duration(new_duration)?;
    debug!("Trimmed clip {} to in-point {}ns and duration {}ns", 
           clip.get_info().id, new_in_point, new_duration);
    Ok(())
}

/// Split a clip at the specified position
pub fn split_clip(timeline: &ges::Timeline, clip: &ges::Clip, position: u64) -> Result<()> {
    // Find the layer containing the clip
    let layer = clip.layer().context("Failed to get clip layer")?;
    
    // Calculate the position relative to the clip's start
    let clip_start = clip.start().nseconds();
    let clip_duration = clip.duration().nseconds();
    
    if position <= clip_start || position >= clip_start + clip_duration {
        warn!("Split position outside clip boundaries");
        return Ok(());
    }
    
    // Split the clip at the specified position
    layer.split_object(clip, gst::ClockTime::from_nseconds(position))
        .context("Failed to split clip")?;
    
    info!("Split clip at position {}ns", position);
    Ok(())
}

/// Merge two adjacent clips
pub fn merge_clips(timeline: &ges::Timeline, clip1: &ges::Clip, clip2: &ges::Clip) -> Result<()> {
    // Find the layer containing the clips
    let layer = clip1.layer().context("Failed to get clip layer")?;
    
    // Check if clips are adjacent
    let clip1_end = clip1.start().nseconds() + clip1.duration().nseconds();
    let clip2_start = clip2.start().nseconds();
    
    if clip1_end != clip2_start {
        warn!("Clips are not adjacent, cannot merge");
        return Ok(());
    }
    
    // Group the clips
    let group = ges::Group::new();
    group.add(clip1).context("Failed to add clip1 to group")?;
    group.add(clip2).context("Failed to add clip2 to group")?;
    
    // Ungrouping dissolves the group, placing its children (clip1, clip2)
    // directly into the container the group was in (e.g., the layer).
    // This does not create a single new ges::Clip from the two inputs.
    GESContainerExt::ungroup(&group, true).map_err(|e| anyhow::anyhow!("Failed to ungroup clips: {}", e))?;
    
    info!("Grouped and then ungrouped clips (effectively placing them sequentially in parent container)");
    Ok(())
}