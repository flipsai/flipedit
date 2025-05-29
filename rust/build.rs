fn main() {
    // Force the use of GStreamer framework libraries instead of Homebrew
    let gstreamer_lib_path = "/Library/Frameworks/GStreamer.framework/Versions/1.0/lib";
    
    println!("cargo:rustc-link-search=native={}", gstreamer_lib_path);
    println!("cargo:rustc-link-lib=dylib=glib-2.0");
    println!("cargo:rustc-link-lib=dylib=gobject-2.0");
    println!("cargo:rustc-link-lib=dylib=gio-2.0");
    println!("cargo:rustc-link-lib=dylib=gthread-2.0");
    println!("cargo:rustc-link-lib=dylib=gmodule-2.0");
    
    // Tell cargo to rerun if any of these environment variables change
    println!("cargo:rerun-if-env-changed=PKG_CONFIG_PATH");
    println!("cargo:rerun-if-env-changed=LIBRARY_PATH");
} 