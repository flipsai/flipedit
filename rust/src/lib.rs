mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
// This file is necessary for Cargo to recognize this as a library crate.

// Declare the v2 module, which contains all the editor logic.
pub mod v2;

// Flutter Rust Bridge auto-generates code that will look for functions
// marked with `#[frb]` within the modules of this crate.
// No explicit re-exports are usually needed here for FRB to work,
// as long as the `v2` module and its submodules correctly expose
// the API functions (which they do via `pub mod` and `pub fn`).

// If a specific generated bridge file (like a new frb_generated.rs) needs to be
// included at the crate root, it would be done like this:
// #[path = "path/to/your/generated/bridge_code.rs"] // Example if path is unusual
// mod frb_generated_code; // Example
// Or simply:
// mod name_of_generated_file_in_src_dir;

// For now, this simple declaration of the v2 module should suffice
// for `cargo build` to proceed and for `flutter_rust_bridge_codegen`
// to find the relevant API functions within `crate::v2::...`.
