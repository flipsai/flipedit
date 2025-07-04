use crate::common::types::TimelineData;
use crate::video::player::VideoPlayer as InternalVideoPlayer;
use crate::video::frame_handler::FrameHandler;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, Duration};
use std::thread;
use log::{info, warn, debug, error};

pub struct TimelinePlayer {
    timeline_data: Option<TimelineData>,
    video_players: HashMap<String, InternalVideoPlayer>, // source_path -> player
    is_playing: Arc<Mutex<bool>>,
    texture_ptr: Option<i64>,
    pub frame_handler: FrameHandler,
    playback_start_time: Arc<Mutex<Option<SystemTime>>>,
    playback_start_position_ms: Arc<Mutex<i32>>,
    current_position_ms: Arc<Mutex<i32>>,
}

impl TimelinePlayer {
    pub fn new() -> Self {
        Self {
            timeline_data: None,
            video_players: HashMap::new(),
            is_playing: Arc::new(Mutex::new(false)),
            texture_ptr: None,
            frame_handler: FrameHandler::new(),
            playback_start_time: Arc::new(Mutex::new(None)),
            playback_start_position_ms: Arc::new(Mutex::new(0)),
            current_position_ms: Arc::new(Mutex::new(0)),
        }
    }

    pub fn set_texture_ptr(&mut self, ptr: i64) {
        self.texture_ptr = Some(ptr);
        self.frame_handler.set_texture_ptr(ptr);
    }

    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<(), String> {
        info!("Loading timeline with {} tracks", timeline_data.tracks.len());
        
        // Clear existing players
        self.video_players.clear();
        
        // Set timeline data in frame handler
        self.frame_handler.set_timeline_data(timeline_data.clone());
        
        // Preload all unique video sources
        let mut unique_sources = std::collections::HashSet::new();
        for track in &timeline_data.tracks {
            for clip in &track.clips {
                unique_sources.insert(clip.source_path.clone());
            }
        }

        info!("Preloading {} unique video sources", unique_sources.len());
        
        for source_path in unique_sources {
            if !std::path::Path::new(&source_path).exists() {
                warn!("Video file not found: {}", source_path);
                continue;
            }

            let mut player = InternalVideoPlayer::new();
            if let Some(texture_ptr) = self.texture_ptr {
                player.set_texture_ptr(texture_ptr);
            }
            
            match player.load_video(source_path.clone()) {
                Ok(_) => {
                    info!("Successfully loaded video: {}", source_path);
                    self.video_players.insert(source_path, player);
                }
                Err(e) => {
                    error!("Failed to load video {}: {}", source_path, e);
                }
            }
        }

        self.timeline_data = Some(timeline_data);
        Ok(())
    }

    pub fn play(&mut self) -> Result<(), String> {
        *self.is_playing.lock().unwrap() = true;
        
        // Record the start time and position for playback timing
        *self.playback_start_time.lock().unwrap() = Some(SystemTime::now());
        *self.playback_start_position_ms.lock().unwrap() = *self.current_position_ms.lock().unwrap();
        
        // Start playback monitoring thread
        self.start_playback_monitoring();
        
        Ok(())
    }

    pub fn pause(&mut self) -> Result<(), String> {
        *self.is_playing.lock().unwrap() = false;
        
        // Update current position based on elapsed time since playback started
        self.update_current_position();
        
        // Pause all players
        for player in self.video_players.values_mut() {
            let _ = player.pause(); // Ignore errors
        }
        
        Ok(())
    }

    pub fn stop(&mut self) -> Result<(), String> {
        *self.is_playing.lock().unwrap() = false;
        
        // Reset position
        *self.current_position_ms.lock().unwrap() = 0;
        self.frame_handler.update_current_time(0);
        
        // Stop all players
        for player in self.video_players.values_mut() {
            let _ = player.stop(); // Ignore errors
        }
        
        Ok(())
    }

    pub fn get_position_ms(&self) -> i32 {
        if *self.is_playing.lock().unwrap() {
            self.update_current_position();
        }
        *self.current_position_ms.lock().unwrap()
    }

    pub fn is_playing(&self) -> bool {
        *self.is_playing.lock().unwrap()
    }

    pub fn dispose(&mut self) -> Result<(), String> {
        self.stop()?;
        
        // Dispose all players
        for player in self.video_players.values_mut() {
            let _ = player.dispose(); // Ignore errors
        }
        
        self.video_players.clear();
        Ok(())
    }

    fn update_current_position(&self) {
        if let (Ok(start_time), Ok(start_pos)) = (
            self.playback_start_time.lock(),
            self.playback_start_position_ms.lock()
        ) {
            if let Some(start) = *start_time {
                let elapsed = SystemTime::now().duration_since(start).unwrap_or(Duration::ZERO);
                let new_position = *start_pos + elapsed.as_millis() as i32;
                *self.current_position_ms.lock().unwrap() = new_position;
                self.frame_handler.update_current_time(new_position);
            }
        }
    }

    fn start_playback_monitoring(&self) {
        let is_playing_clone = Arc::clone(&self.is_playing);
        let playback_start_time_clone = Arc::clone(&self.playback_start_time);
        let playback_start_position_clone = Arc::clone(&self.playback_start_position_ms);
        let current_position_clone = Arc::clone(&self.current_position_ms);
        let frame_handler_clone = self.frame_handler.clone();

        thread::spawn(move || {
            while *is_playing_clone.lock().unwrap() {
                // Update current position based on elapsed time
                if let (Ok(start_time), Ok(start_pos)) = (
                    playback_start_time_clone.lock(),
                    playback_start_position_clone.lock()
                ) {
                    if let Some(start) = *start_time {
                        let elapsed = SystemTime::now().duration_since(start).unwrap_or(Duration::ZERO);
                        let new_position = *start_pos + elapsed.as_millis() as i32;
                        *current_position_clone.lock().unwrap() = new_position;
                        frame_handler_clone.update_current_time(new_position);
                    }
                }
                
                // Sleep for a short interval (about 30 FPS monitoring)
                thread::sleep(Duration::from_millis(33));
            }
        });
    }

    fn frame_to_ms(frame: i32) -> i32 {
        // Match Flutter's conversion: frames * (1000.0 / 30.0) with rounding
        let ms_per_frame = 1000.0 / 30.0; // 33.33... ms per frame
        (frame as f64 * ms_per_frame).round() as i32
    }

    fn ms_to_frame(ms: i32) -> i32 {
        // Match Flutter's conversion: ms / (1000.0 / 30.0) with floor
        let ms_per_frame = 1000.0 / 30.0; // 33.33... ms per frame
        (ms as f64 / ms_per_frame).floor() as i32
    }

    pub fn set_position_ms(&mut self, position_ms: i32) {
        *self.current_position_ms.lock().unwrap() = position_ms;
        self.frame_handler.update_current_time(position_ms);
        
        // If we're playing, update the playback start time and position to maintain sync
        if *self.is_playing.lock().unwrap() {
            *self.playback_start_time.lock().unwrap() = Some(SystemTime::now());
            *self.playback_start_position_ms.lock().unwrap() = position_ms;
        }
        
        debug!("Timeline position set to {}ms", position_ms);
    }
}

impl Default for TimelinePlayer {
    fn default() -> Self {
        Self::new()
    }
} 