//! Common track operations

use anyhow::{Result, Context};
use gstreamer_editing_services as ges;
use gstreamer::prelude::*; // For ElementExt (if context() was still used) and potentially others
use gstreamer_editing_services::prelude::*; // For TimelineExt
use log::{info}; // Removed debug, warn as unused

use super::{VideoTrack, AudioTrack};

/// Add a new video track to the timeline
pub fn add_video_track(timeline: &ges::Timeline, name: &str) -> Result<VideoTrack> {
    // Create a new video track in the GES timeline
    let ges_track = ges::VideoTrack::new(); // Returns VideoTrack directly, panics on GObject creation failure
    
    timeline.add_track(&ges_track) // TimelineExt
        .map_err(|e| anyhow::anyhow!("Failed to add video track to timeline: {}", e))?;
    
    let track = VideoTrack::new(ges_track.upcast(), name)?; // Cast needed if VideoTrack::new expects ges::Track
    info!("Added video track: {}", name);
    
    Ok(track)
}

/// Add a new audio track to the timeline
pub fn add_audio_track(timeline: &ges::Timeline, name: &str) -> Result<AudioTrack> {
    // Create a new audio track in the GES timeline
    let ges_track = ges::AudioTrack::new(); // Returns AudioTrack directly
    
    timeline.add_track(&ges_track) // TimelineExt
        .map_err(|e| anyhow::anyhow!("Failed to add audio track to timeline: {}", e))?;
    
    let track = AudioTrack::new(ges_track.upcast(), name)?; // Cast needed if AudioTrack::new expects ges::Track
    info!("Added audio track: {}", name);
    
    Ok(track)
}

/// Remove a track from the timeline
pub fn remove_track(timeline: &ges::Timeline, track: &ges::Track) -> Result<()> {
    timeline.remove_track(track)
        .context("Failed to remove track from timeline")?;
    
    info!("Removed track from timeline");
    Ok(())
}

// Removed placeholder/out-of-scope track operations: move_track, set_audio_track_mute, set_video_track_visible.
// These operations would require further implementation to interact correctly with GES properties (e.g., 'active' for mute/visible)
// or are not relevant for the current single-track focus.

// /// Move a track to a new position in the timeline
// pub fn move_track(timeline: &ges::Timeline, track: &ges::Track, new_position: u32) -> Result<()> {
//     // In GES, we need to remove and re-add the track at the new position
//     // This is a simplified implementation
//     timeline.remove_track(track)
//         .context("Failed to remove track for repositioning")?;
//
//     // Re-add the track
//     timeline.add_track(track)
//         .context("Failed to re-add track at new position")?;
//
//     info!("Moved track to new position: {}", new_position);
//     Ok(())
// }

// /// Mute or unmute an audio track
// pub fn set_audio_track_mute(track: &mut AudioTrack, mute: bool) -> Result<()> {
//     // In a real implementation, you would set the mute state on the GES track (e.g. track.get_ges_track().set_active(!mute))
//     // For now, we just log it
//     if mute {
//         debug!("Muted audio track: {}", track.get_info().name);
//     } else {
//         debug!("Unmuted audio track: {}", track.get_info().name);
//     }
//
//     Ok(())
// }

// /// Hide or show a video track
// pub fn set_video_track_visible(track: &mut VideoTrack, visible: bool) -> Result<()> {
//     // In a real implementation, you would set the visibility on the GES track (e.g. track.get_ges_track().set_active(visible))
//     // For now, we just log it
//     if visible {
//         debug!("Made video track visible: {}", track.get_info().name);
//     } else {
//         debug!("Made video track invisible: {}", track.get_info().name);
//     }
//
//     Ok(())
// }