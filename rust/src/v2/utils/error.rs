//! Error handling utilities

use thiserror::Error;

#[derive(Error, Debug)]
pub enum VideoEditorError {
    #[error("GStreamer error: {0}")]
    GStreamer(#[from] gstreamer::glib::Error),
    
    #[error("GES error: {0}")]
    GES(String),
    
    #[error("Texture error: {0}")]
    Texture(String),
    
    #[error("File not found: {0}")]
    FileNotFound(String),
    
    #[error("Invalid operation: {0}")]
    InvalidOperation(String),
}