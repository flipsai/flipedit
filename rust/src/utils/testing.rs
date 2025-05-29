use gstreamer as gst;
use gstreamer::prelude::*;
use log::info;
use std::time::Duration;

/// Test method to verify GStreamer pipeline works without texture
pub fn test_pipeline(file_path: String) -> Result<(), String> {
    info!("Testing GStreamer pipeline with file: {}", file_path);
    
    // Check if file exists
    if !std::path::Path::new(&file_path).exists() {
        return Err(format!("Video file not found: {}", file_path));
    }

    // Check file permissions
    match std::fs::metadata(&file_path) {
        Ok(metadata) => {
            info!("File metadata: size={}, readonly={}", metadata.len(), metadata.permissions().readonly());
        },
        Err(e) => {
            info!("Failed to get file metadata: {}", e);
            return Err(format!("Cannot access file metadata: {}", e));
        }
    }

    // Try to open and read a few bytes to verify access
    match std::fs::File::open(&file_path) {
        Ok(mut file) => {
            let mut buffer = [0u8; 16];
            match std::io::Read::read(&mut file, &mut buffer) {
                Ok(bytes_read) => {
                    info!("Successfully read {} bytes from file", bytes_read);
                },
                Err(e) => {
                    info!("Failed to read from file: {}", e);
                    return Err(format!("Cannot read file: {}", e));
                }
            }
        },
        Err(e) => {
            info!("Failed to open file: {}", e);
            return Err(format!("Cannot open file: {}", e));
        }
    }

    info!("File exists and is readable, testing basic GStreamer functionality...");

    // First, test if we can create a simple pipeline without any elements
    info!("Creating empty pipeline...");
    let empty_pipeline = gst::Pipeline::new();
    match empty_pipeline.set_state(gst::State::Paused) {
        Ok(_) => info!("Empty pipeline set to paused successfully"),
        Err(e) => {
            info!("Failed to set empty pipeline to paused: {:?}", e);
            return Err(format!("Basic GStreamer functionality broken: {:?}", e));
        }
    }
    let _ = empty_pipeline.set_state(gst::State::Null);

    // Test creating individual elements
    info!("Testing element creation...");
    
    let _filesrc = gst::ElementFactory::make("filesrc")
        .build()
        .map_err(|e| format!("Failed to create filesrc: {}", e))?;
    info!("filesrc created successfully");

    let _fakesink = gst::ElementFactory::make("fakesink")
        .build()
        .map_err(|e| format!("Failed to create fakesink: {}", e))?;
    info!("fakesink created successfully");

    // Test a simple filesrc -> fakesink pipeline with error handling
    info!("Creating simple filesrc -> fakesink pipeline...");
    let simple_pipeline = gst::Pipeline::new();
    
    let source = gst::ElementFactory::make("filesrc")
        .property("location", &file_path)
        .build()
        .map_err(|e| format!("Failed to create filesrc: {}", e))?;

    let sink = gst::ElementFactory::make("fakesink")
        .build()
        .map_err(|e| format!("Failed to create fakesink: {}", e))?;

    simple_pipeline.add_many(&[&source, &sink])
        .map_err(|e| format!("Failed to add elements: {}", e))?;

    source.link(&sink)
        .map_err(|e| format!("Failed to link source to sink: {}", e))?;

    info!("Simple pipeline created and linked");

    // Set up error handling for the simple pipeline
    let bus = simple_pipeline.bus().unwrap();
    bus.add_signal_watch();
    
    bus.connect_message(Some("error"), move |_, msg| {
        if let gst::MessageView::Error(err) = msg.view() {
            info!(
                "Simple pipeline error from {:?}: {} ({:?})",
                err.src().map(|s| s.path_string()),
                err.error(),
                err.debug()
            );
        }
    });

    // Try to set simple pipeline to paused
    info!("Setting simple pipeline to paused...");
    match simple_pipeline.set_state(gst::State::Paused) {
        Ok(gst::StateChangeSuccess::Success) => {
            info!("Simple pipeline set to paused successfully");
        },
        Ok(gst::StateChangeSuccess::Async) => {
            info!("Simple pipeline transitioning to paused...");
            match simple_pipeline.state(Some(gst::ClockTime::from_seconds(5))) {
                (Ok(_), state, _) => {
                    info!("Simple pipeline reached state: {:?}", state);
                },
                (Err(e), current_state, pending_state) => {
                    info!("Simple pipeline state change failed: {:?}, current: {:?}, pending: {:?}", e, current_state, pending_state);
                }
            }
        },
        Ok(gst::StateChangeSuccess::NoPreroll) => {
            info!("Simple pipeline set to paused without preroll");
        },
        Err(e) => {
            info!("Simple pipeline failed to set to paused: {:?}", e);
            
            // Give error messages time to be processed
            std::thread::sleep(Duration::from_millis(100));
            
            let _ = simple_pipeline.set_state(gst::State::Null);
            return Err(format!("Simple pipeline failed: {:?}", e));
        }
    }

    let _ = simple_pipeline.set_state(gst::State::Null);
    info!("Simple pipeline test completed successfully");

    info!("All tests completed successfully");
    Ok(())
} 