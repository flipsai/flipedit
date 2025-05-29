use log::LevelFilter;
use std::sync::Once;

static INIT_LOGGER: Once = Once::new();

pub fn setup_logger() {
    INIT_LOGGER.call_once(|| {
        #[cfg(target_os = "android")]
        android_logger::init_once(android_logger::Config::default().with_max_level(LevelFilter::Trace));

        #[cfg(not(target_os = "android"))]
        {
            // Configure env_logger with better formatting and force initialization
            let env = env_logger::Env::default()
                .filter_or("RUST_LOG", "debug")
                .write_style_or("RUST_LOG_STYLE", "always");
                
            match env_logger::Builder::from_env(env)
                .filter_level(LevelFilter::Debug)
                .format_timestamp_millis()
                .format_module_path(false)
                .try_init() 
            {
                Ok(_) => println!("Rust logger initialized successfully"),
                Err(e) => println!("Failed to initialize Rust logger: {}", e),
            }
        }
    });
} 