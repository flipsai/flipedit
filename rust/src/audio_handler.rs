use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, Host, Stream, StreamConfig, SampleFormat, SampleRate, ChannelCount};
use std::sync::{Arc, Mutex, mpsc};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use log::{info, error, debug};

#[derive(Debug, Clone)]
pub struct AudioFormat {
    pub sample_rate: u32,
    pub channels: u32,
    pub bytes_per_sample: u32,
}

#[derive(Debug)]
pub enum MediaData {
    AudioFormat(AudioFormat),
    Stop,
    Pause,
    Resume
}

pub type MediaSender = mpsc::Sender<MediaData>;

pub struct AudioHandler {
    host: Host,
    device: Option<Device>,
    stream: Option<Stream>,
    config: Option<StreamConfig>,
    is_playing: Arc<AtomicBool>,
    audio_buffer: Arc<Mutex<Vec<f32>>>,
    target_sample_rate: u32,
    target_channels: u16,
    devices_enumerated: bool, // Track if we've already enumerated devices
}

impl Default for AudioHandler {
    fn default() -> Self {
        let host = cpal::default_host();
        info!("Using audio host: {}", host.id().name());
        
        Self {
            host,
            device: None,
            stream: None,
            config: None,
            is_playing: Arc::new(AtomicBool::new(false)),
            audio_buffer: Arc::new(Mutex::new(Vec::new())),
            target_sample_rate: 44100, // Standard sample rate
            target_channels: 2, // Stereo
            devices_enumerated: false,
        }
    }
}

impl AudioHandler {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn handle_format(&mut self, format: AudioFormat) {
        info!("Setting audio format: {}Hz, {} channels, {} bytes per sample", 
              format.sample_rate, format.channels, format.bytes_per_sample);
        
        // Initialize audio output only if not already initialized
        if self.stream.is_none() {
            if let Err(e) = self.init_audio_output() {
                error!("Failed to initialize audio output: {}", e);
            }
        }
    }

    fn init_audio_output(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // Get default output device
        let device = self.host.default_output_device()
            .ok_or("No output device available")?;
        
        info!("Using audio device: {}", device.name().unwrap_or_else(|_| "Unknown".to_string()));
        
        // Only enumerate devices and configs once for performance
        if !self.devices_enumerated {
            // Enumerate devices only on first initialization to avoid performance issues
            debug!("Enumerating audio devices (first time only)...");
            if let Ok(devices) = self.host.output_devices() {
                info!("Available output devices:");
                for (i, device) in devices.enumerate() {
                    if let Ok(name) = device.name() {
                        info!("  {}: {}", i, name);
                        if i >= 5 { break; } // Limit to first 5 devices to reduce spam
                    }
                }
            }

            // Limit config enumeration to reduce log spam
            debug!("Supported audio configurations (summary):");
            if let Ok(mut temp_configs) = device.supported_output_configs() {
                let mut count = 0;
                for config in temp_configs.by_ref() {
                    if count < 3 { // Only show first 3 configs
                        info!("  Channels: {}, Sample rate: {:?}, Format: {:?}", 
                              config.channels(), config.min_sample_rate(), config.sample_format());
                        count += 1;
                    } else {
                        break;
                    }
                }
                if count >= 3 {
                    info!("  ... (additional configs suppressed for performance)");
                }
            }
            
            self.devices_enumerated = true;
        }
        
        // Get a fresh iterator for finding the right config
        let mut supported_configs_range = device.supported_output_configs()?;
        let _supported_config = supported_configs_range
            .find(|c| c.channels() == self.target_channels && c.sample_format() == SampleFormat::F32)
            .ok_or("No suitable audio config found")?
            .with_sample_rate(SampleRate(self.target_sample_rate));

        let config = StreamConfig {
            channels: self.target_channels as ChannelCount,
            sample_rate: SampleRate(self.target_sample_rate),
            buffer_size: cpal::BufferSize::Fixed(512), // Smaller buffer for lower latency
        };

        info!("Selected audio config: {:?}", config);

        let audio_buffer = self.audio_buffer.clone();
        let is_playing = self.is_playing.clone();

        // Create audio stream with enhanced error reporting
        let stream = device.build_output_stream(
            &config,
            move |data: &mut [f32], _info: &cpal::OutputCallbackInfo| {
                if !is_playing.load(Ordering::Relaxed) {
                    // Fill with silence when not playing
                    for sample in data.iter_mut() {
                        *sample = 0.0;
                    }
                    return;
                }

                if let Ok(mut buffer) = audio_buffer.try_lock() {
                    let samples_needed = data.len();
                    let samples_available = buffer.len();
                    
                    if samples_available >= samples_needed {
                        // Copy samples from buffer to output
                        data.copy_from_slice(&buffer[..samples_needed]);
                        buffer.drain(..samples_needed);
                    } else if samples_available > 0 {
                        // Not enough samples, copy what we have and fill rest with silence
                        data[..samples_available].copy_from_slice(&buffer[..]);
                        for sample in &mut data[samples_available..] {
                            *sample = 0.0;
                        }
                        buffer.clear();
                    } else {
                        // No samples available, fill with silence
                        for sample in data.iter_mut() {
                            *sample = 0.0;
                        }
                    }
                } else {
                    // Failed to lock buffer, fill with silence
                    for sample in data.iter_mut() {
                        *sample = 0.0;
                    }
                }
            },
            |err| error!("Audio stream error: {}", err),
            None,
        )?;

        // Start the stream
        info!("Starting audio stream...");
        stream.play()?;
        info!("Audio stream started successfully");
        
        self.device = Some(device);
        self.stream = Some(stream);
        self.config = Some(config);
        
        Ok(())
    }

    pub fn start_playback(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        if self.stream.is_none() {
            self.init_audio_output()?;
        }
        
        self.is_playing.store(true, Ordering::Relaxed);
        info!("Audio playback started");
        Ok(())
    }

    pub fn stop_playback(&mut self) {
        self.is_playing.store(false, Ordering::Relaxed);
        
        // Clear audio buffer
        if let Ok(mut buffer) = self.audio_buffer.lock() {
            buffer.clear();
        }
        
        info!("Audio playback stopped");
    }

    pub fn pause_playback(&mut self) {
        self.is_playing.store(false, Ordering::Relaxed);
        info!("Audio playback paused");
    }

    pub fn resume_playback(&mut self) {
        // Ensure audio output is initialized before resuming
        if self.stream.is_none() {
            if let Err(e) = self.init_audio_output() {
                error!("Failed to initialize audio output for resume: {}", e);
                return;
            }
        }
        
        // Add a small pre-buffer of silence to help with timing
        if let Ok(mut buffer) = self.audio_buffer.lock() {
            if buffer.is_empty() {
                // Add ~20ms of silence for initial timing buffer
                let prebuffer_samples = (self.target_sample_rate as usize * self.target_channels as usize) / 50; // 20ms
                buffer.resize(prebuffer_samples, 0.0);
                // debug!("Added {} prebuffer silence samples for timing", prebuffer_samples); // Disabled for performance
            }
        }
        
        self.is_playing.store(true, Ordering::Relaxed);
        info!("Audio playback resumed");
    }
}

impl Drop for AudioHandler {
    fn drop(&mut self) {
        self.stop_playback();
        if let Some(stream) = self.stream.take() {
            drop(stream);
        }
        info!("AudioHandler dropped");
    }
}

/// Start the audio thread that handles direct system audio playback
pub fn start_audio_thread() -> MediaSender {
    let (audio_sender, audio_receiver) = mpsc::channel::<MediaData>();
    
    thread::spawn(move || {
        let mut audio_handler = AudioHandler::default();
        info!("Audio thread started");
        
        loop {
            match audio_receiver.recv() {
                Ok(data) => {
                    match data {
                        MediaData::AudioFormat(f) => {
                            audio_handler.handle_format(f);
                        }
                        MediaData::Stop => {
                            info!("Audio thread received stop signal");
                            audio_handler.stop_playback();
                            break;
                        }
                        MediaData::Pause => {
                            audio_handler.pause_playback();
                        }
                        MediaData::Resume => {
                            audio_handler.resume_playback();
                        }
                    }
                }
                Err(e) => {
                    error!("Audio thread receiver error: {}", e);
                    break;
                }
            }
        }
        
        info!("Audio thread finished");
    });
    
    audio_sender
} 