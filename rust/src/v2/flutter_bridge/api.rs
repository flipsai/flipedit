//! Flutter API definitions

use anyhow::Result;
use flutter_rust_bridge::frb;
use log::{info, error};

use crate::v2::core::{Project, VideoInfo, TimelineState};
use crate::v2::rendering::PreviewRenderer;

pub struct VideoEditorV2 {
    project: Project,
    renderer: Option<PreviewRenderer>,
}

impl VideoEditorV2 {
    pub fn new() -> Result<Self> {
        let project = Project::new()?;
        
        Ok(VideoEditorV2 {
            project,
            renderer: None,
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
pub fn setup_preview_v2(editor: &mut VideoEditorV2, engine_handle: i64, width: u32, height: u32) -> Result<i64> {
    let mut renderer = PreviewRenderer::new(editor.project.get_timeline())?;
    let texture_id = renderer.setup_texture_output(engine_handle, width, height)?;
    
    editor.renderer = Some(renderer);
    
    // Return texture ID as i64 for Flutter
    Ok(texture_id)
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

#[frb(sync)]
pub fn set_clip_duration(editor: &mut VideoEditorV2, clip_id: String, duration: u64) -> Result<()> {
    // TODO: Implement clip duration setting
    Ok(())
}

#[frb(sync)]
pub fn set_clip_in_point(editor: &mut VideoEditorV2, clip_id: String, in_point: u64) -> Result<()> {
    // TODO: Implement clip in point setting
    Ok(())
}

#[frb(sync)]
pub fn set_clip_start_time(editor: &mut VideoEditorV2, clip_id: String, start_time: u64) -> Result<()> {
    // TODO: Implement clip start time setting
    Ok(())
}

#[frb(sync)]
pub fn split_ges_clip_at_position(editor: &mut VideoEditorV2, clip_id: String, position: u64) -> Result<()> {
    // TODO: Implement clip splitting
    Ok(())
}