use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, Host, Stream, StreamConfig, SampleFormat, SampleRate, ChannelCount};
use std::sync::{Arc, Mutex, mpsc};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use log::{info, warn, error, debug};
use rubato::{Resampler, SincFixedIn, SincInterpolationType, SincInterpolationParameters, WindowFunction};

#[derive(Debug, Clone)]
pub struct AudioFrame {
    pub data: Vec<u8>,
    pub sample_rate: u32,
    pub channels: u32,
    pub bytes_per_sample: u32,
    pub timestamp: Option<u64>, // Timestamp in nanoseconds for A/V sync
}

#[derive(Debug, Clone)]
pub struct AudioFormat {
    pub sample_rate: u32,
    pub channels: u32,
    pub bytes_per_sample: u32,
}

#[derive(Debug)]
pub enum MediaData {
    AudioFrame(Box<AudioFrame>),
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
    resampler: Option<SincFixedIn<f32>>,
    current_format: Option<AudioFormat>,
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
            resampler: None,
            current_format: None,
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
        
        self.current_format = Some(format.clone());
        
        // Initialize audio output only if not already initialized
        if self.stream.is_none() {
            if let Err(e) = self.init_audio_output() {
                error!("Failed to initialize audio output: {}", e);
            }
        }
        
        // Setup resampler if needed
        if format.sample_rate != self.target_sample_rate || format.channels != (self.target_channels as u32) {
            self.setup_resampler(format.sample_rate, format.channels);
        }
    }

    pub fn handle_frame(&mut self, frame: AudioFrame) {
        // debug!("Received audio frame: {} bytes, {}Hz, {}ch, {} bytes/sample", 
        //        frame.data.len(), frame.sample_rate, frame.channels, frame.bytes_per_sample); // Disabled for performance
        
        if !self.is_playing.load(Ordering::Relaxed) {
            // debug!("Audio not playing, ignoring frame"); // Disabled for performance
            return;
        }

        // Convert audio data to f32 samples
        let samples = self.convert_to_f32_samples(&frame);
        // debug!("Converted to {} f32 samples", samples.len()); // Disabled for performance
        
        // Resample if necessary
        let final_samples = if self.resampler.is_some() {
            // debug!("Resampling audio data"); // Disabled for performance
            // Need to extract resampler to avoid borrow checker issues
            let mut temp_resampler = self.resampler.take().unwrap();
            let result = self.resample_audio(samples, &mut temp_resampler);
            self.resampler = Some(temp_resampler);
            
            match result {
                Ok(resampled) => {
                    debug!("Resampled to {} samples", resampled.len());
                    resampled
                },
                Err(e) => {
                    error!("Failed to resample audio: {}", e);
                    return;
                }
            }
        } else {
            // debug!("No resampling needed"); // Disabled for performance
            samples
        };

        // Add to audio buffer with size limit for better sync
        if let Ok(mut buffer) = self.audio_buffer.try_lock() {
            // Limit buffer size to prevent excessive latency (max ~100ms of audio)
            let max_buffer_size = (self.target_sample_rate as usize * self.target_channels as usize) / 10; // 100ms
            
            if buffer.len() > max_buffer_size {
                // Buffer is getting too large, drop some old samples to maintain sync
                let excess = buffer.len() - max_buffer_size / 2; // Keep only half max
                buffer.drain(..excess);
                warn!("Audio buffer overflow, dropped {} samples for sync", excess);
            }
            
            buffer.extend_from_slice(&final_samples);
            // debug!("Added {} samples to audio buffer (total: {}, max: {})", 
            //        final_samples.len(), buffer.len(), max_buffer_size); // Disabled for performance
        } else {
            warn!("Failed to lock audio buffer for frame processing");
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

    fn setup_resampler(&mut self, input_sample_rate: u32, input_channels: u32) {
        if input_sample_rate == self.target_sample_rate && input_channels == (self.target_channels as u32) {
            self.resampler = None;
            info!("No resampling needed");
            return;
        }

        info!("Setting up resampler: {}Hz {}ch -> {}Hz {}ch", 
              input_sample_rate, input_channels, self.target_sample_rate, self.target_channels);

        // Create high-quality resampler
        let params = SincInterpolationParameters {
            sinc_len: 256,
            f_cutoff: 0.95,
            interpolation: SincInterpolationType::Linear,
            oversampling_factor: 256,
            window: WindowFunction::BlackmanHarris2,
        };

        match SincFixedIn::<f32>::new(
            self.target_sample_rate as f64 / input_sample_rate as f64,
            2.0,
            params,
            1024, // chunk_size
            input_channels as usize,
        ) {
            Ok(resampler) => {
                self.resampler = Some(resampler);
                info!("Resampler created successfully");
            }
            Err(e) => {
                error!("Failed to create resampler: {}", e);
                self.resampler = None;
            }
        }
    }

    fn convert_to_f32_samples(&self, frame: &AudioFrame) -> Vec<f32> {
        match frame.bytes_per_sample {
            2 => {
                // S16LE format - convert to f32
                let mut samples = Vec::with_capacity(frame.data.len() / 2);
                for chunk in frame.data.chunks_exact(2) {
                    let sample_i16 = i16::from_le_bytes([chunk[0], chunk[1]]);
                    let sample_f32 = sample_i16 as f32 / i16::MAX as f32;
                    samples.push(sample_f32);
                }
                samples
            }
            4 => {
                // F32LE format - directly interpret as f32
                let mut samples = Vec::with_capacity(frame.data.len() / 4);
                for chunk in frame.data.chunks_exact(4) {
                    let sample_f32 = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                    samples.push(sample_f32);
                }
                samples
            }
            _ => {
                warn!("Unsupported audio format: {} bytes per sample", frame.bytes_per_sample);
                Vec::new()
            }
        }
    }

    fn resample_audio(&self, input_samples: Vec<f32>, resampler: &mut SincFixedIn<f32>) -> Result<Vec<f32>, Box<dyn std::error::Error + Send + Sync>> {
        let input_channels = self.current_format.as_ref().map(|f| f.channels as usize).unwrap_or(2);
        let samples_per_channel = input_samples.len() / input_channels;
        
        if samples_per_channel == 0 {
            return Ok(Vec::new());
        }

        // Deinterleave samples by channel
        let mut channels: Vec<Vec<f32>> = vec![Vec::with_capacity(samples_per_channel); input_channels];
        for (i, sample) in input_samples.iter().enumerate() {
            channels[i % input_channels].push(*sample);
        }

        // Ensure all channels have the same length
        let min_len = channels.iter().map(|ch| ch.len()).min().unwrap_or(0);
        for ch in &mut channels {
            ch.truncate(min_len);
        }

        // Process through resampler
        let output_channels = resampler.process(&channels, None)?;
        
        // Interleave output samples
        let mut output_samples = Vec::new();
        if !output_channels.is_empty() {
            let output_len = output_channels[0].len();
            for i in 0..output_len {
                for ch in &output_channels {
                    if i < ch.len() {
                        output_samples.push(ch[i]);
                    } else {
                        output_samples.push(0.0);
                    }
                }
            }
        }

        Ok(output_samples)
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
                        MediaData::AudioFrame(af) => {
                            audio_handler.handle_frame(*af);
                        }
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