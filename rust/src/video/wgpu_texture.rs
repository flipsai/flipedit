use anyhow::{anyhow, Result};
use gstreamer_gl as gst_gl;
use gstreamer_gl::prelude::GLContextExtManual;
use irondash_texture::{Texture, PayloadProvider};
use irondash_engine_context::EngineContext;
use log::{info, debug};
use std::sync::{Arc, Mutex, mpsc};
use std::ffi::c_void;
use wgpu_hal as hal;
use wgpu::GlBackendOptions;

// Platform-specific texture types
#[cfg(target_os = "linux")]
use irondash_texture::{BoxedGLTexture, GLTextureProvider, GLTexture};
#[cfg(any(target_os = "macos", target_os = "ios"))]
use irondash_texture::{BoxedIOSurface, IOSurfaceProvider, io_surface::IOSurface};
#[cfg(target_os = "windows")]
use irondash_texture::{BoxedTextureDescriptor, TextureDescriptorProvider, TextureDescriptor, ID3D11Texture2D, PixelFormat};

/// Shared GPU context between GStreamer and wgpu
pub struct SharedGpuContext {
    wgpu_device: wgpu::Device,
    wgpu_queue: wgpu::Queue,
    gl_context: Option<gst_gl::GLContext>,
}

impl SharedGpuContext {
    /// Create a shared GPU context from GStreamer's OpenGL context
    pub fn new_from_gstreamer_context(gl_context: gst_gl::GLContext) -> Result<Self> {
        info!("Creating shared GPU context from GStreamer OpenGL context");

        // Create wgpu instance first
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::GL,
            ..Default::default()
        });

        // This is the magic - create wgpu adapter from GStreamer's OpenGL context
        let exposed = unsafe {
            <hal::api::Gles as hal::Api>::Adapter::new_external(
                |name| {
                    // Get OpenGL function pointers directly from GStreamer!
                    gl_context.proc_address(name) as *mut c_void
                },
GlBackendOptions::default()
            )
        }
        .ok_or_else(|| anyhow!("Failed to create wgpu adapter from GStreamer context"))?;

        // Convert to high-level wgpu adapter
        let adapter = unsafe { 
            instance.create_adapter_from_hal(exposed) 
        };

        // Create device and queue
        let (device, queue) = pollster::block_on(async {
            adapter
                .request_device(&wgpu::DeviceDescriptor {
                    label: Some("GStreamer Shared Device"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::default(),
                    memory_hints: Default::default(),
                    trace: wgpu::Trace::Off,
                })
                .await
        })
        .map_err(|e| anyhow!("Failed to create wgpu device: {}", e))?;

        info!("Successfully created shared GPU context with wgpu device");

        Ok(Self {
            wgpu_device: device,
            wgpu_queue: queue,
            gl_context: Some(gl_context),
        })
    }

    /// Get the wgpu device
    pub fn device(&self) -> &wgpu::Device {
        &self.wgpu_device
    }

    /// Get the wgpu queue
    pub fn queue(&self) -> &wgpu::Queue {
        &self.wgpu_queue
    }

    /// Get the OpenGL context
    pub fn gl_context(&self) -> Option<&gst_gl::GLContext> {
        self.gl_context.as_ref()
    }
}

/// GPU texture that shares memory between GStreamer and Flutter
pub struct WgpuTexture {
    wgpu_texture: wgpu::Texture,
    width: u32,
    height: u32,
    shared_context: Arc<SharedGpuContext>,
}

impl WgpuTexture {
    /// Create a new GPU texture from shared context
    pub fn new(
        shared_context: Arc<SharedGpuContext>,
        width: u32,
        height: u32,
    ) -> Result<Self> {
        let device = shared_context.device();

        let texture_desc = wgpu::TextureDescriptor {
            label: Some("GStreamer Shared Texture"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::RENDER_ATTACHMENT,
            view_formats: &[],
        };

        let wgpu_texture = device.create_texture(&texture_desc);

        info!("Created wgpu texture {}x{}", width, height);

        Ok(Self {
            wgpu_texture,
            width,
            height,
            shared_context,
        })
    }

    /// Get the underlying wgpu texture
    pub fn wgpu_texture(&self) -> &wgpu::Texture {
        &self.wgpu_texture
    }

    /// Extract platform-specific texture handle for IronDash
    #[cfg(target_os = "linux")]
    pub fn get_gl_texture_id(&self) -> Result<u32> {
        // Extract OpenGL texture ID from wgpu texture using wgpu 26.x API
        unsafe {
            match self.wgpu_texture.as_hal::<wgpu_hal::gles::Api>() {
                Some(hal_texture) => {
                    match &hal_texture.inner {
                        wgpu_hal::gles::TextureInner::Texture { raw, target: _ } => {
                            let gl_texture_id = raw.0.get();
                            info!("Extracted GL texture ID: {}", gl_texture_id);
                            Ok(gl_texture_id)
                        }
                        _ => Err(anyhow!("Texture is not a regular GL texture (might be renderbuffer)"))
                    }
                }
                None => Err(anyhow!("Texture is not from OpenGL backend or backend mismatch"))
            }
        }
    }

    #[cfg(any(target_os = "macos", target_os = "ios"))]
    pub fn get_metal_texture(&self) -> Result<*mut c_void> {
        // Extract Metal texture from wgpu texture using wgpu 26.x API
        unsafe {
            match self.wgpu_texture.as_hal::<wgpu_hal::metal::Api>() {
                Some(hal_texture) => {
                    let metal_texture_ptr = hal_texture.raw.as_ptr() as *mut c_void;
                    info!("Extracted Metal texture pointer: {:?}", metal_texture_ptr);
                    Ok(metal_texture_ptr)
                }
                None => Err(anyhow!("Texture is not from Metal backend or backend mismatch"))
            }
        }
    }

    #[cfg(target_os = "windows")]
    pub fn get_d3d11_texture(&self) -> Result<*mut c_void> {
        // Extract D3D11 texture from wgpu texture using wgpu 26.x API
        unsafe {
            match self.wgpu_texture.as_hal::<wgpu_hal::dx11::Api>() {
                Some(hal_texture) => {
                    let d3d_texture_ptr = hal_texture.raw.as_ptr() as *mut c_void;
                    info!("Extracted D3D11 texture pointer: {:?}", d3d_texture_ptr);
                    Ok(d3d_texture_ptr)
                }
                None => Err(anyhow!("Texture is not from D3D11 backend or backend mismatch"))
            }
        }
    }
}

// GPU-only providers - no CPU fallbacks!

#[cfg(target_os = "linux")]
pub struct LinuxGpuProvider {
    wgpu_texture: Arc<WgpuTexture>,
}

#[cfg(target_os = "linux")]
impl LinuxGpuProvider {
    pub fn new(wgpu_texture: Arc<WgpuTexture>) -> Self {
        Self { wgpu_texture }
    }
}

#[cfg(target_os = "linux")]
struct LinuxGLTextureProvider {
    texture_id: u32,
    width: u32,
    height: u32,
}

#[cfg(target_os = "linux")]
impl GLTextureProvider for LinuxGLTextureProvider {
    fn get(&self) -> GLTexture {
        GLTexture {
            target: 0x0DE1, // GL_TEXTURE_2D
            name: &self.texture_id,
            width: self.width as i32,
            height: self.height as i32,
        }
    }
}

#[cfg(target_os = "linux")]
impl PayloadProvider<BoxedGLTexture> for LinuxGpuProvider {
    fn get_payload(&self) -> BoxedGLTexture {
        let texture_id = self.wgpu_texture.get_gl_texture_id()
            .expect("Failed to get GL texture ID from wgpu texture");
        debug!("🚀 Providing REAL GL texture ID {} to Flutter (zero-copy GPU)", texture_id);
        Box::new(LinuxGLTextureProvider {
            texture_id,
            width: self.wgpu_texture.width,
            height: self.wgpu_texture.height,
        })
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub struct DarwinGpuProvider {
    wgpu_texture: Arc<WgpuTexture>,
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
impl DarwinGpuProvider {
    pub fn new(wgpu_texture: Arc<WgpuTexture>) -> Self {
        Self { wgpu_texture }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
struct DarwinIOSurfaceProvider {
    metal_texture_ptr: *mut c_void,
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
impl IOSurfaceProvider for DarwinIOSurfaceProvider {
    fn get(&self) -> &IOSurface {
        // Extract IOSurface from Metal texture
        unsafe { &*(self.metal_texture_ptr as *const IOSurface) }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
impl PayloadProvider<BoxedIOSurface> for DarwinGpuProvider {
    fn get_payload(&self) -> BoxedIOSurface {
        let metal_texture_ptr = self.wgpu_texture.get_metal_texture()
            .expect("Failed to get Metal texture from wgpu texture");
        debug!("🚀 Providing REAL Metal texture to Flutter (zero-copy GPU)");
        Box::new(DarwinIOSurfaceProvider { metal_texture_ptr })
    }
}

#[cfg(target_os = "windows")]
pub struct WindowsGpuProvider {
    wgpu_texture: Arc<WgpuTexture>,
}

#[cfg(target_os = "windows")]
impl WindowsGpuProvider {
    pub fn new(wgpu_texture: Arc<WgpuTexture>) -> Self {
        Self { wgpu_texture }
    }
}

#[cfg(target_os = "windows")]
struct WindowsTextureProvider {
    d3d_texture_ptr: *mut c_void,
    width: u32,
    height: u32,
}

#[cfg(target_os = "windows")]
impl TextureDescriptorProvider<ID3D11Texture2D> for WindowsTextureProvider {
    fn get(&self) -> TextureDescriptor<ID3D11Texture2D> {
        TextureDescriptor {
            handle: unsafe { &*(self.d3d_texture_ptr as *const ID3D11Texture2D) },
            width: self.width as i32,
            height: self.height as i32,
            visible_width: self.width as i32,
            visible_height: self.height as i32,
            pixel_format: PixelFormat::RGBA,
        }
    }
}

#[cfg(target_os = "windows")]
impl PayloadProvider<BoxedTextureDescriptor<ID3D11Texture2D>> for WindowsGpuProvider {
    fn get_payload(&self) -> BoxedTextureDescriptor<ID3D11Texture2D> {
        let d3d_texture_ptr = self.wgpu_texture.get_d3d11_texture()
            .expect("Failed to get D3D11 texture from wgpu texture");
        debug!("🚀 Providing REAL D3D11 texture to Flutter (zero-copy GPU)");
        Box::new(WindowsTextureProvider {
            d3d_texture_ptr,
            width: self.wgpu_texture.width,
            height: self.wgpu_texture.height,
        })
    }
}


/// Create a GPU-only video texture that shares context with GStreamer
pub fn create_gpu_video_texture(
    gl_context: gst_gl::GLContext,
    width: u32,
    height: u32,
    engine_handle: i64,
) -> Result<(i64, Arc<WgpuTexture>)> {
    info!("Creating GPU-only video texture {}x{}", width, height);

    let (tx, rx) = mpsc::channel();

    // Must create texture on main thread for IronDash
    EngineContext::perform_on_main_thread(move || {
        let result: Result<(i64, Arc<WgpuTexture>)> = (|| {
            // Create shared GPU context
            let shared_context = Arc::new(SharedGpuContext::new_from_gstreamer_context(gl_context)?);

            // Create wgpu texture
            let wgpu_texture = Arc::new(WgpuTexture::new(shared_context, width, height)?);

            // Create platform-specific GPU payload provider - pure GPU only!
            #[cfg(target_os = "linux")]
            let provider = Arc::new(LinuxGpuProvider::new(wgpu_texture.clone()));
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            let provider = Arc::new(DarwinGpuProvider::new(wgpu_texture.clone()));
            #[cfg(target_os = "windows")]
            let provider = Arc::new(WindowsGpuProvider::new(wgpu_texture.clone()));

            // Create IronDash texture with GPU payload provider
            let texture = Texture::new_with_provider(engine_handle, provider)
                .map_err(|e| anyhow!("Failed to create IronDash texture: {}", e))?;

            let texture_id = texture.id();

            // Create a simple mark available function
            let mark_available_fn = {
                let sendable_texture = texture.into_sendable_texture();
                Box::new(move || {
                    sendable_texture.mark_frame_available();
                }) as Box<dyn Fn() + Send + Sync>
            };

            // Store mark available function for frame updates
            register_gpu_texture(texture_id, mark_available_fn);

            info!("Created GPU texture with ID: {}", texture_id);
            Ok((texture_id, wgpu_texture))
        })();

        let _ = tx.send(result);
    })?;

    rx.recv().unwrap_or_else(|_| {
        Err(anyhow!("Failed to receive GPU texture creation result"))
    })
}

// Global registry for GPU textures - use dynamic type since we have multiple platform types
lazy_static::lazy_static! {
    static ref GPU_TEXTURES: Arc<Mutex<std::collections::HashMap<i64, Box<dyn Fn() + Send + Sync>>>> = 
        Arc::new(Mutex::new(std::collections::HashMap::new()));
}

/// Register a GPU texture for frame updates - simplified approach
fn register_gpu_texture(texture_id: i64, mark_available_fn: Box<dyn Fn() + Send + Sync>) {
    if let Ok(mut textures) = GPU_TEXTURES.lock() {
        textures.insert(texture_id, mark_available_fn);
        info!("Registered GPU texture {}", texture_id);
    }
}

/// Update all GPU textures - call this when GStreamer produces a new frame
pub fn mark_gpu_textures_available() -> Result<()> {
    if let Ok(textures) = GPU_TEXTURES.lock() {
        for (texture_id, mark_fn) in textures.iter() {
            mark_fn();
            debug!("Marked GPU texture {} frame available", texture_id);
        }
    }
    Ok(())
}

/// Unregister a GPU texture
pub fn unregister_gpu_texture(texture_id: i64) {
    let _ = EngineContext::perform_on_main_thread(move || {
        if let Ok(mut textures) = GPU_TEXTURES.lock() {
            textures.remove(&texture_id);
            info!("Unregistered GPU texture {}", texture_id);
        }
    });
}

/// Get the number of active GPU textures
pub fn get_gpu_texture_count() -> usize {
    if let Ok(textures) = GPU_TEXTURES.lock() {
        textures.len()
    } else {
        0
    }
}

// Global registry for engine handle -> texture ID mapping
lazy_static::lazy_static! {
    static ref ENGINE_TEXTURE_MAP: Arc<Mutex<std::collections::HashMap<i64, i64>>> = 
        Arc::new(Mutex::new(std::collections::HashMap::new()));
}

/// Store texture ID for a specific engine handle
pub fn store_texture_id_for_engine(engine_handle: i64, texture_id: i64) {
    if let Ok(mut map) = ENGINE_TEXTURE_MAP.lock() {
        map.insert(engine_handle, texture_id);
        info!("Stored texture ID {} for engine handle {}", texture_id, engine_handle);
    }
}

/// Get texture ID for a specific engine handle
pub fn get_texture_id_for_engine(engine_handle: i64) -> Option<i64> {
    if let Ok(map) = ENGINE_TEXTURE_MAP.lock() {
        map.get(&engine_handle).copied()
    } else {
        None
    }
}