# Hot Restart Issues with GStreamer Bus Watch Guards

## Problem

When using GStreamer bus watch guards in Rust-Flutter applications, hot restart can hang indefinitely. This occurs because `BusWatchGuard` objects are not `Send` but are being used in multi-threaded contexts during hot restart.

## Symptoms

- Hot restart gets stuck at "Performing hot restart..." 
- Application appears to freeze during development
- GStreamer pipeline continues running in background
- No error messages, just indefinite hanging

## Root Cause

The issue stems from storing `gst::bus::BusWatchGuard` in structs that need to be `Send + Sync`:

```rust
// ❌ Problematic - BusWatchGuard is not Send
pub struct TimelinePlayer {
    bus_watch_guard: Option<gst::bus::BusWatchGuard>, // Causes hot restart hang
    // ... other fields
}
```

During hot restart, Dart/Flutter tries to dispose of Rust objects across thread boundaries, but the `BusWatchGuard` cannot be safely transferred between threads.

## Solution

### 1. Don't Store the Bus Watch Guard

Instead of storing the guard, let it be automatically cleaned up when the pipeline is destroyed:

```rust
// ✅ Fixed - Don't store the guard
fn setup_message_bus_handling(&mut self, pipeline: &ges::Pipeline) -> Result<()> {
    let bus = pipeline.bus().ok_or_else(|| anyhow!("Failed to get pipeline bus"))?;
    
    // Clone necessary data for the closure
    let is_playing = Arc::clone(&self.is_playing);
    
    // Create the watch but don't store the guard
    let _watch_guard = bus.add_watch(move |_bus, message| {
        match message.type_() {
            gst::MessageType::Eos => {
                info!("Timeline playback completed");
                *is_playing.lock().unwrap() = false;
            },
            // ... handle other message types
            _ => {}
        }
        gst::glib::ControlFlow::Continue
    })?;
    
    // Let _watch_guard be automatically dropped
    // The bus watch will be cleaned up when the pipeline is destroyed
    
    Ok(())
}
```

### 2. Remove Bus Watch Guard from Struct

```rust
// ✅ Remove the problematic field entirely
pub struct TimelinePlayer {
    pipeline: Option<ges::Pipeline>,
    // bus_watch_guard: Option<gst::bus::BusWatchGuard>, // ❌ Remove this
    is_playing: Arc<Mutex<bool>>,
    // ... other fields that are Send + Sync
}
```

### 3. Clean Pipeline Disposal

Ensure the pipeline is properly disposed without trying to manually clean up the bus watch:

```rust
pub fn dispose(&mut self) -> Result<()> {
    // Clean up other resources first
    if let Some(texture_id) = self.texture_id {
        unregister_texture(texture_id);
    }
    
    // Stop the pipeline - this will automatically clean up the bus watch
    self.stop_pipeline()
}

fn stop_pipeline(&self) -> Result<()> {
    // Stop timers
    if let Some(timer_id) = self.position_timer_id.lock().unwrap().take() {
        timer_id.remove();
    }
    
    // Set pipeline to NULL - this cleans up bus watches automatically
    if let Some(pipeline) = &self.pipeline {
        pipeline.set_state(gst::State::Null)?;
        *self.is_playing.lock().unwrap() = false;
    }
    
    Ok(())
}
```

## Why This Works

1. **Automatic Cleanup**: GStreamer automatically removes bus watches when the pipeline is destroyed
2. **No Cross-Thread Issues**: We don't store non-`Send` objects in `Send + Sync` structs
3. **Proper Lifecycle**: The bus watch lives as long as the pipeline, which is the correct lifetime
4. **Hot Restart Friendly**: Flutter can properly dispose of the Rust objects during hot restart

## General Guidelines

### Do ✅
- Use `let _guard = bus.add_watch(...)` and let it be automatically dropped
- Store only `Send + Sync` types in structs that cross FFI boundaries
- Rely on GStreamer's automatic cleanup when setting pipeline to `Null`
- Test hot restart frequently during development

### Don't ❌
- Store `BusWatchGuard` in structs that need to be `Send + Sync`
- Try to manually manage bus watch lifecycle across threads
- Ignore `Send + Sync` trait bounds when working with FFI
- Assume that "working in release" means hot restart will work

## Testing

To verify the fix works:

1. Start your Flutter app with GStreamer integration
2. Make a small code change (like updating a string)
3. Trigger hot restart (Ctrl+Shift+R or equivalent)
4. Verify it completes quickly (< 2-3 seconds)
5. Check that GStreamer functionality still works after restart

The hot restart should be fast and reliable, without hanging at "Performing hot restart...".

## Related Issues

This pattern applies to any GStreamer object that:
- Is not `Send + Sync` by default
- Has automatic cleanup tied to pipeline lifecycle  
- Gets stored in FFI-crossing structs

Examples: `BusWatchGuard`, certain `Element` handles, custom GStreamer callbacks with non-`Send` closures.