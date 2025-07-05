//! Flutter API definitions

use anyhow::{Result, Context};
use flutter_rust_bridge::frb;
use irondash_texture::{TextureId, Texture};
use log::{info, error};
use std::sync::Arc;

use crate::v2::core::{Project, VideoInfo, TimelineState};
use crate.v2::rendering::PreviewRenderer;
// Assuming TextureHandler might still be used for other purposes or future explicit release.
// use super::texture_handler::TextureHandler;

pub struct VideoEditorV2 {
    project: Project,
    renderer: Option<PreviewRenderer>,
    preview_texture: Option<Arc<Texture>>, // To keep the texture alive with PreviewRenderer
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
pub fn setup_preview_v2(editor: &mut VideoEditorV2, width: u32, height: u32) -> Result<i64> {
    // 1. Create the Texture object that Rust will update.
    let new_preview_texture = Arc::new(Texture::new_with_size(width, height)
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