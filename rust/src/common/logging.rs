use log::LevelFilter;
use std::sync::Once;

static INIT_LOGGER: Once = Once::new();

pub fn setup_logger() {
    INIT_LOGGER.call_once(|| {
        #[cfg(target_os = "android")]
        android_logger::init_once(android_logger::Config::default().with_max_level(LevelFilter::Trace));

        #[cfg(not(target_os = "android"))]
        {
            let _ = env_logger::Builder::from_default_env()
                .filter_level(LevelFilter::Debug)
                .try_init();
        }
    });
} 