//! V2 Video Editor Module
//! 
//! This module provides a clean, modular architecture for video editing
//! built on top of GStreamer Editing Services.

pub mod core;
pub mod clips;
pub mod tracks;
pub mod rendering;
pub mod flutter_bridge;
pub mod utils;

pub use core::*;
pub use flutter_bridge::api::*;