# GStreamer Editing Services with irondash Integration

## Overview

This document explains how to integrate GStreamer Editing Services (GES) with irondash for creating professional video editing applications in Flutter. This integration provides zero-copy video rendering from GStreamer directly to Flutter widgets using OpenGL textures.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Flutter UI    │    │   Rust Backend   │    │   GStreamer     │
│                 │    │                  │    │   Pipeline      │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │VideoPlayer  │◄┼────┼─┤TimelinePlayer│◄┼────┼─┤GES Timeline │ │
│ │Widget       │ │    │ │              │ │    │ │             │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
│                 │    │        │         │    │        │        │
│ ┌─────────────┐ │    │ ┌──────▼──────┐ │    │ ┌─────▼─────┐ │
│ │irondash     │◄┼────┼─┤irondash     │ │    │ │AppSink    │ │
│ │Texture      │ │    │ │Texture      │ │    │ │(RGBA)     │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └───────────┘ │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Key Components

### 1. GStreamer Editing Services (GES)
- **Timeline**: Non-linear video editing timeline
- **Clips**: Video/audio segments with timing information
- **Tracks**: Parallel streams for video/audio
- **Pipeline**: Rendering pipeline that processes the timeline

### 2. irondash Integration
- **Texture**: OpenGL texture shared between GStreamer and Flutter
- **PayloadProvider**: Interface for providing frame data to textures
- **SendableTexture**: Thread-safe texture invalidation mechanism

### 3. Frame Update Chain
```
GStreamer Sample → handle_video_sample() → update_video_frame() → 
irondash Texture → mark_frame_available() → Flutter Repaint
```

## Implementation Guide

### Step 1: Dependencies Setup

Add to your `Cargo.toml`:

```toml
[dependencies]
gstreamer = "0.23.6"
gstreamer-editing-services = "0.23.5"
gstreamer-app = "0.23.5"
gstreamer-gl = { version = "0.23.6", features = ["v1_16"] }
irondash_engine_context = { git = "https://github.com/irondash/irondash.git", rev = "...", package = "irondash_engine_context" }
irondash_texture = { git = "https://github.com/irondash/irondash.git", rev = "...", package = "irondash_texture" }
lazy_static = "1.4"
anyhow = "1.0"
log = "0.4"
```

### Step 2: Create Frame Provider

```rust
use irondash_texture::{Texture, PayloadProvider, BoxedPixelData, SimplePixelData};

pub struct FrameProvider {
    frame_data: Arc<Mutex<Option<FrameData>>>,
    width: u32,
    height: u32,
}

impl PayloadProvider<BoxedPixelData> for FrameProvider {
    fn get_payload(&self) -> BoxedPixelData {
        if let Ok(frame_guard) = self.frame_data.lock() {
            if let Some(frame) = frame_guard.as_ref() {
                return SimplePixelData::new_boxed(
                    frame.width as i32,
                    frame.height as i32,
                    frame.data.clone()
                );
            }
        }
        
        // Return empty frame if no data available
        let empty_data = vec![0u8; (self.width * self.height * 4) as usize];
        SimplePixelData::new_boxed(self.width as i32, self.height as i32, empty_data)
    }
}
```

### Step 3: Create irondash Texture (Main Thread)

**Critical**: Texture creation must happen on the main thread:

```rust
pub fn create_player_texture(
    width: u32, 
    height: u32, 
    engine_handle: i64
) -> Result<(i64, Box<dyn Fn(FrameData) + Send + Sync>)> {
    let (tx, rx) = mpsc::channel();

    // Schedule texture creation on main thread - CRITICAL for irondash
    EngineContext::perform_on_main_thread(move || {
        let provider = Arc::new(FrameProvider::new(width, height));
        let texture = Texture::new_with_provider(engine_handle, provider.clone())?;
        let texture_id = texture.id();
        
        // Convert to sendable texture for cross-thread frame invalidation
        let sendable_texture = texture.into_sendable_texture();
        
        // Create update function with actual irondash invalidation
        let update_fn = Box::new(move |frame_data: FrameData| {
            if let Some(provider) = provider_weak.upgrade() {
                provider.update_frame(frame_data);
                
                // KEY: This triggers Flutter repaint
                sendable_texture.mark_frame_available();
            }
        });
        
        // Register in global registry for update_video_frame() calls
        register_irondash_update_function(texture_id, update_fn);
        
        tx.send(Ok((texture_id, placeholder_fn))).ok();
    })?;

    rx.recv().unwrap_or_else(|_| Err(anyhow!("Failed to receive texture creation result")))
}
```

### Step 4: Setup GES Timeline

```rust
pub struct TimelinePlayer {
    pipeline: Option<ges::Pipeline>,
    timeline: Option<ges::Timeline>,
    texture_id: Option<i64>,
    // ... other fields
}

impl TimelinePlayer {
    pub fn load_timeline(&mut self, timeline_data: TimelineData) -> Result<()> {
        // Create GES timeline
        let timeline = ges::Timeline::new_audio_video();
        let layer = timeline.append_layer();

        // Add clips to timeline
        for clip in timeline_data.tracks.iter().flat_map(|t| &t.clips) {
            let uri = format!("file://{}", clip.source_path);
            let asset = ges::UriClipAsset::request_sync(&uri)?;
            
            layer.add_asset(
                &asset,
                gst::ClockTime::from_mseconds(clip.start_time_on_track_ms as u64),
                gst::ClockTime::from_mseconds(clip.start_time_in_source_ms as u64),
                gst::ClockTime::from_mseconds(
                    (clip.end_time_on_track_ms - clip.start_time_on_track_ms) as u64
                ),
                ges::TrackType::UNKNOWN,
            )?;
        }

        self.timeline = Some(timeline.clone());
        
        // Create GES pipeline
        let pipeline = ges::Pipeline::new();
        pipeline.set_timeline(&timeline)?;
        
        // Setup video sink for texture rendering
        let video_sink = self.create_texture_video_sink()?;
        pipeline.preview_set_video_sink(Some(&video_sink));
        
        self.pipeline = Some(pipeline);
        Ok(())
    }
}
```

### Step 5: Create Texture Video Sink

```rust
fn create_texture_video_sink(&self) -> Result<gst::Element> {
    let video_sink = gst::ElementFactory::make("appsink")
        .name("texture_video_sink")
        .build()?;

    video_sink.set_property("emit-signals", true);
    video_sink.set_property("sync", true);
    video_sink.set_property("drop", true);
    video_sink.set_property("max-buffers", 1u32);

    // Set RGBA format for irondash compatibility
    let caps = gst::Caps::builder("video/x-raw")
        .field("format", "RGBA")
        .field("width", 1920i32)
        .field("height", 1080i32)
        .build();
    video_sink.set_property("caps", &caps);

    // Setup frame callback
    let appsink = video_sink.clone().dynamic_cast::<gst_app::AppSink>().unwrap();
    
    if let Some(texture_id) = self.texture_id {
        appsink.set_callbacks(
            gst_app::AppSinkCallbacks::builder()
                .new_sample(move |sink| {
                    match Self::handle_video_sample(sink, texture_id) {
                        Ok(_) => Ok(gst::FlowSuccess::Ok),
                        Err(_) => Err(gst::FlowError::Error),
                    }
                })
                .build(),
        );
    }

    Ok(video_sink)
}
```

### Step 6: Handle Video Samples

```rust
fn handle_video_sample(
    appsink: &gst_app::AppSink,
    texture_id: i64,
) -> Result<(), gst::FlowError> {
    let sample = appsink.pull_sample().map_err(|_| gst::FlowError::Eos)?;
    let buffer = sample.buffer().ok_or(gst::FlowError::Error)?;
    let map = buffer.map_readable().map_err(|_| gst::FlowError::Error)?;

    let caps = sample.caps().ok_or(gst::FlowError::Error)?;
    let s = caps.structure(0).ok_or(gst::FlowError::Error)?;
    let width = s.get::<i32>("width").unwrap() as u32;
    let height = s.get::<i32>("height").unwrap() as u32;

    let frame_data = FrameData {
        data: map.as_slice().to_vec(),
        width,
        height,
        texture_id: Some(texture_id as u64),
    };

    // KEY: This calls the registered irondash update functions
    if let Err(e) = crate::api::simple::update_video_frame(frame_data) {
        debug!("Failed to update video frame: {}", e);
        return Err(gst::FlowError::Error);
    }

    Ok(())
}
```

### Step 7: Global Update Function Registry

```rust
// Global registry for REAL irondash texture update functions
lazy_static::lazy_static! {
    static ref IRONDASH_UPDATE_FUNCTIONS: Arc<Mutex<HashMap<i64, Box<dyn Fn(FrameData) + Send + Sync>>>> = 
        Arc::new(Mutex::new(HashMap::new()));
}

pub fn update_video_frame(frame_data: FrameData) -> Result<()> {
    // Call the REAL irondash texture update functions
    if let Ok(functions) = IRONDASH_UPDATE_FUNCTIONS.lock() {
        for (texture_id, update_fn) in functions.iter() {
            update_fn(frame_data.clone());
            debug!("Called REAL irondash update for texture {}", texture_id);
        }
    }
    Ok(())
}
```

## Critical Threading Considerations

### 1. Main Thread Requirements
- **irondash texture creation** MUST happen on the main thread
- Use `EngineContext::perform_on_main_thread()` for cross-thread calls
- Never create textures directly from GStreamer callbacks

### 2. Frame Processing Thread Safety
- GStreamer callbacks run on GStreamer's internal threads
- Use `Arc<Mutex<>>` for shared state
- Keep frame processing lightweight to avoid blocking

### 3. Memory Management
- Use `SendableTexture` for cross-thread texture invalidation
- Implement proper cleanup in disposal methods
- Avoid memory leaks with weak references where appropriate

## Performance Optimizations

### 1. Buffer Management
```rust
// Use buffer pools to avoid allocations
let caps = gst::Caps::builder("video/x-raw")
    .field("format", "RGBA")
    .field("pixel-aspect-ratio", gst::Fraction::new(1, 1))
    .build();
```

### 2. Frame Dropping
```rust
video_sink.set_property("drop", true);
video_sink.set_property("max-buffers", 1u32);
```

### 3. Sync Settings
```rust
// Use GStreamer's internal clock only
video_sink.set_property("sync", true);
```

## OpenGL Context Sharing (Future Enhancement)

For optimal performance, GStreamer and Flutter should share the same OpenGL context:

```rust
// TODO: Implement GL context sharing
fn setup_gl_context_sharing(&mut self) -> Result<()> {
    // 1. Extract Flutter's GL context handle
    let flutter_gl_handle = get_flutter_gl_context_handle(self.engine_handle)?;
    
    // 2. Create GStreamer GL context from Flutter handle
    let gl_context_message = create_gl_context_message(flutter_gl_handle);
    
    // 3. Configure GStreamer GL elements to use shared context
    // This would allow: glupload ! glcolorconvert ! gldownload ! appsink
    
    Ok(())
}
```

## Troubleshooting

### Common Issues

1. **No Video Display**
   - Check texture creation happens on main thread
   - Verify `mark_frame_available()` is called
   - Ensure frame data format is RGBA

2. **Thread Errors**
   - Use `EngineContext::perform_on_main_thread()` for texture operations
   - Check for `Send + Sync` trait implementations

3. **Memory Leaks**
   - Implement proper disposal in `Drop` trait
   - Unregister textures from global registries

### Debug Logging

Enable debug logging to trace the frame update chain:

```rust
debug!("GStreamer sample received: {}x{}", width, height);
debug!("Called REAL irondash update for texture {}", texture_id);
debug!("Marked frame available for texture {}", texture_id);
```

## Example Usage

```rust
// Create timeline player
let mut player = TimelinePlayer::new()?;

// Create irondash texture
let texture_id = player.create_texture(engine_handle)?;

// Load timeline with clips
player.load_timeline(timeline_data)?;

// Start playback
player.play()?;

// The video will now render to the Flutter widget via irondash texture
```

## Conclusion

This integration provides a robust foundation for professional video editing applications in Flutter, combining the power of GStreamer Editing Services with the efficiency of irondash's zero-copy texture rendering. The key to success is proper thread management and ensuring the frame update chain correctly triggers Flutter repaints. 