//! Common types and enums for the video editor

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoInfo {
    pub width: u32,
    pub height: u32,
    pub fps: f64,
    pub duration: u64, // in nanoseconds
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipInfo {
    pub id: String,
    pub name: String,
    pub start_time: u64,    // in nanoseconds
    pub duration: u64,      // in nanoseconds
    pub in_point: u64,      // in nanoseconds
    pub clip_type: ClipType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ClipType {
    Video,
    Audio,
    Image,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackInfo {
    pub id: String,
    pub name: String,
    pub track_type: TrackType,
    pub clips: Vec<ClipInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TrackType {
    Video,
    Audio,
}

#[derive(Debug, Clone)]
pub struct TimelineState {
    pub position: u64,      // current playback position in nanoseconds
    pub duration: u64,      // total timeline duration in nanoseconds
    pub is_playing: bool,
}