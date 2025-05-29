use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrameData {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineClip {
    pub id: Option<i32>,
    pub track_id: i32,
    pub source_path: String,
    pub start_time_on_track_ms: i32,
    pub end_time_on_track_ms: i32,
    pub start_time_in_source_ms: i32,
    pub end_time_in_source_ms: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineTrack {
    pub id: i32,
    pub name: String,
    pub clips: Vec<TimelineClip>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineData {
    pub tracks: Vec<TimelineTrack>,
} 