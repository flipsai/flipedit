//! Flutter API definitions

use anyhow::{Result, Context};
use flutter_rust_bridge::frb;
use irondash_texture::{TextureId, Texture, BoxedPixelData, SimplePixelDataProvider};
use log::{info, error, warn}; // Added warn
use std::sync::Arc;

use crate::v2::core::{Project, VideoInfo, TimelineState};
use crate.v2::rendering::PreviewRenderer;
// Assuming TextureHandler might still be used for other purposes or future explicit release.
// use super::texture_handler::TextureHandler;
use gstreamer as gst; // For ClockTime
use gstreamer_editing_services::prelude::TimelineElementExt; // Corrected path
use rand::Rng; // Changed for more specific import

pub struct VideoEditorV2 {
    project: Project,
    renderer: Option<PreviewRenderer>,
    preview_texture: Option<Arc<Texture<BoxedPixelData>>>, // Corrected generic
    // texture_handler: TextureHandler, // If integrating TextureHandler more directly
}

impl VideoEditorV2 {
    pub fn new() -> Result<Self> {
        let project = Project::new()?;
        // let texture_handler = TextureHandler::new()?; // If creating here
        Ok(VideoEditorV2 {
            project,
            renderer: None,
            preview_texture: None,
            // texture_handler,
        })
    }
}

#[frb(sync)]
pub fn create_video_editor_v2() -> Result<VideoEditorV2> {
    VideoEditorV2::new()
}

#[frb(sync)]
pub fn add_video_file_v2(editor: &mut VideoEditorV2, file_path: String) -> Result<String> {
    editor.project.add_video_file(&file_path)
}

#[frb(sync)]
pub fn setup_preview_v2(editor: &mut VideoEditorV2, engine_handle: i64, width: u32, height: u32) -> Result<i64> { // Added engine_handle
    // 1. Create the Texture object that Rust will update.
    let initial_size = (width * height * 4) as usize; // Assuming RGBA
    let initial_pixels = vec![0u8; initial_size];
    // Assuming BoxedPixelData::from_vec exists and returns Result
    let initial_data = BoxedPixelData::from_vec(initial_pixels, width, height)
        .map_err(|e| anyhow::anyhow!("Failed to create BoxedPixelData for preview: {:?}", e))?;
    let provider = SimplePixelDataProvider::new(initial_data);

    // Use new_with_provider and pass the engine_handle
    let new_preview_texture = Arc::new(Texture::new_with_provider(engine_handle, Arc::new(provider))
        .context("Failed to create preview texture for setup_preview_v2")?);
    let texture_id = new_preview_texture.id();

    // 2. Instantiate PreviewRenderer with this texture.
    // Ensure project.get_timeline() provides a valid &Timeline
    let timeline = editor.project.get_timeline();
    let renderer = PreviewRenderer::new(
        timeline,
        texture_id,
        Arc::clone(&new_preview_texture)
    )?;
    
    // 3. Store the renderer and the texture in the editor.
    editor.renderer = Some(renderer);
    editor.preview_texture = Some(new_preview_texture); // Keep texture alive
    
    // 4. Return the texture_id (as i64) to Flutter.
    // Flutter will use this ID to refer to the texture in its UI.
    // The existing TextureHandler is somewhat bypassed for *this specific texture's updates*,
    // but the texture is still registered with irondash_texture's global registry.
    info!("Setup preview with Texture ID: {:?} ({}x{})", texture_id.0, width, height);
    Ok(texture_id.0 as i64)
}

#[frb(sync)]
pub fn play_preview_v2(editor: &VideoEditorV2) -> Result<()> {
    if let Some(renderer) = &editor.renderer {
        renderer.play()
    } else {
        Err(anyhow::anyhow!("Preview not initialized"))
    }
}

#[frb(sync)]
pub fn pause_preview_v2(editor: &VideoEditorV2) -> Result<()> {
    if let Some(renderer) = &editor.renderer {
        renderer.pause()
    } else {
        Err(anyhow::anyhow!("Preview not initialized"))
    }
}

#[frb(sync)]
pub fn get_video_info_v2(editor: &VideoEditorV2) -> Option<VideoInfo> {
    editor.project.get_timeline().get_video_info()
}

#[frb(sync)]
pub fn get_timeline_state_v2(editor: &VideoEditorV2) -> TimelineState {
    editor.project.get_state().clone()
}

// Clip Manipulation APIs

#[frb(sync)]
pub fn set_clip_start_time(editor: &mut VideoEditorV2, clip_id: String, start_time_ns: u64) -> Result<()> {
    let ges_clip = editor.project.find_ges_clip_by_id(&clip_id)
        .ok_or_else(|| anyhow::anyhow!("Clip with ID {} not found", clip_id))?;

    // Update GES clip
    // Note: ges::Clip specific methods like set_start are on TimelineElementExt trait
    ges_clip.set_start(gst::ClockTime::from_nseconds(start_time_ns))
        .map_err(|_| anyhow::anyhow!("Failed to set clip start time on ges_clip for ID {}", clip_id))?;

    // Update ClipInfo in Project
    if let Some(clip_info) = editor.project.clips.get_mut(&clip_id) {
        clip_info.start_time = start_time_ns;
    } else {
        // This case should ideally not happen if ges_clip was found by ID.
        // It implies an inconsistency if the ClipInfo map doesn't also have the ID.
        error!("ClipInfo not found for ID {} after ges_clip was found. Data inconsistency likely.", clip_id);
        return Err(anyhow::anyhow!("ClipInfo not found for ID {} after successful ges_clip retrieval.", clip_id));
    }

    info!("Set clip {} start time to {}ns", clip_id, start_time_ns);
    Ok(())
}

#[frb(sync)]
pub fn set_clip_duration(editor: &mut VideoEditorV2, clip_id: String, duration_ns: u64) -> Result<()> {
    let ges_clip = editor.project.find_ges_clip_by_id(&clip_id)
        .ok_or_else(|| anyhow::anyhow!("Clip with ID {} not found", clip_id))?;

    ges_clip.set_duration(gst::ClockTime::from_nseconds(duration_ns))
        .map_err(|_| anyhow::anyhow!("Failed to set clip duration on ges_clip for ID {}", clip_id))?;

    if let Some(clip_info) = editor.project.clips.get_mut(&clip_id) {
        clip_info.duration = duration_ns;
    } else {
        error!("ClipInfo not found for ID {} after ges_clip was found. Data inconsistency likely.", clip_id);
        return Err(anyhow::anyhow!("ClipInfo not found for ID {} after successful ges_clip retrieval.", clip_id));
    }

    info!("Set clip {} duration to {}ns", clip_id, duration_ns);
    Ok(())
}

#[frb(sync)]
pub fn set_clip_in_point(editor: &mut VideoEditorV2, clip_id: String, in_point_ns: u64) -> Result<()> {
    let ges_clip = editor.project.find_ges_clip_by_id(&clip_id)
        .ok_or_else(|| anyhow::anyhow!("Clip with ID {} not found", clip_id))?;

    ges_clip.set_inpoint(gst::ClockTime::from_nseconds(in_point_ns))
         .map_err(|_| anyhow::anyhow!("Failed to set clip in_point on ges_clip for ID {}", clip_id))?;

    if let Some(clip_info) = editor.project.clips.get_mut(&clip_id) {
        clip_info.in_point = in_point_ns;
    } else {
        error!("ClipInfo not found for ID {} after ges_clip was found. Data inconsistency likely.", clip_id);
        return Err(anyhow::anyhow!("ClipInfo not found for ID {} after successful ges_clip retrieval.", clip_id));
    }

    info!("Set clip {} in_point to {}ns", clip_id, in_point_ns);
    Ok(())
}

#[frb(sync)]
pub fn split_ges_clip_at_position(editor: &mut VideoEditorV2, clip_id: String, position_ns: u64) -> Result<Option<String>> {
    let ges_clip = editor.project.find_ges_clip_by_id(&clip_id)
        .ok_or_else(|| anyhow::anyhow!("Clip with ID {} not found for split", clip_id))?;

    let layer = ges_clip.layer().ok_or_else(|| anyhow::anyhow!("Clip {} has no layer", clip_id))?;

    let clip_start_abs = ges_clip.start().nseconds();
    let clip_dur_abs = ges_clip.duration().nseconds();

    if position_ns <= clip_start_abs || position_ns >= clip_start_abs + clip_dur_abs {
        warn!("Split position {}ns is outside of clip {} boundaries ({}ns - {}ns)",
              position_ns, clip_id, clip_start_abs, clip_start_abs + clip_dur_abs);
        return Err(anyhow::anyhow!("Split position {}ns is outside clip {} boundaries", position_ns, clip_id));
    }

    // split_object returns Result<Option<TimelineElement>, Error>
    let new_ges_element_opt = layer.split_object(&ges_clip, gst::ClockTime::from_nseconds(position_ns))
        .map_err(|e| anyhow::anyhow!("Failed to split ges_clip {}: {:?}", clip_id, e))?;

    info!("Split original clip {} at {}ns", clip_id, position_ns);

    if let Some(new_element) = new_ges_element_opt {
        if let Ok(new_clip_obj) = new_element.downcast::<ges::Clip>() {
            let random_part: u32 = rand::thread_rng().gen();
            let new_clip_id_val = format!("clip_{}_{}", new_clip_obj.start().nseconds(), random_part);
            new_clip_obj.set_name(Some(&new_clip_id_val));

            let original_clip_info = editor.project.clips.get(&clip_id).cloned();
            if let Some(mut derived_info) = original_clip_info {
                derived_info.id = new_clip_id_val.clone();
                derived_info.start_time = new_clip_obj.start().nseconds();
                derived_info.duration = new_clip_obj.duration().nseconds();
                // Original in-point I_orig, original start T_orig_start, split point S_abs (absolute timeline)
                // New in-point I_new = I_orig + (S_abs - T_orig_start)
                // However, S_abs is the split point *within the original clip's media items*, not timeline.
                // The `position_ns` for split_object is an absolute timeline position.
                // The `ges_clip.set_inpoint()` refers to the media's internal timeline.
                // If original clip had start T1, inpoint I1, duration D1.
                // It spans from T1 to T1+D1 on timeline, using media from I1 to I1+D1.
                // If split at timeline position S (where T1 < S < T1+D1).
                // First part: start T1, duration S-T1, inpoint I1.
                // Second part: start S, duration (T1+D1)-S, inpoint I1+(S-T1).
                derived_info.in_point = derived_info.in_point + (position_ns - clip_start_abs);

                editor.project.clips.insert(new_clip_id_val.clone(), derived_info);
                info!("New clip segment {} (media in-point {}ns) created from split.", new_clip_id_val, new_clip_obj.inpoint().nseconds());

                if let Some(original_info_mut) = editor.project.clips.get_mut(&clip_id) {
                    original_info_mut.duration = ges_clip.duration().nseconds(); // ges_clip is the first part, its duration was modified by split_object
                     info!("Original clip {} duration updated to {}ns after split.", clip_id, original_info_mut.duration);
                }
                return Ok(Some(new_clip_id_val));
            } else {
                error!("Could not find original ClipInfo for ID {} to derive split info.", clip_id);
                // Note: new_clip_obj was created, but its associated ClipInfo couldn't be. This is an inconsistency.
                // Should we remove new_clip_obj from layer? Or proceed without ClipInfo?
                // For now, proceed but log error.
                return Err(anyhow::anyhow!("Original ClipInfo for ID {} not found after split, new clip {} created in GES but not in Project metadata.", clip_id, new_clip_id_val));
            }
        } else {
             warn!("Split operation returned a TimelineElement that is not a ges::Clip.");
        }
    } else {
        info!("Split operation did not return a new element (e.g. split at the very end).");
    }
    Ok(None)
}