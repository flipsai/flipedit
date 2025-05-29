#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rust_lib_flipedit.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rust_lib_flipedit'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../rust rust_lib_flipedit',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${BUILT_PRODUCTS_DIR}/librust_lib_flipedit.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # Ensure we only build for supported architectures
    'ONLY_ACTIVE_ARCH' => 'NO',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/librust_lib_flipedit.a -F/Library/Frameworks -framework GStreamer -framework CoreAudio -framework AudioToolbox -framework AudioUnit -L/Library/Frameworks/GStreamer.framework/Versions/1.0/lib -lges-1.0 -lglib-2.0 -lgobject-2.0 -lgio-2.0 -lgthread-2.0 -lgmodule-2.0',
    'HEADER_SEARCH_PATHS' => '"/Library/Frameworks/GStreamer.framework/Headers"',
    'LD_RUNPATH_SEARCH_PATHS' => ['"/Library/Frameworks"','"/Library/Frameworks/GStreamer.framework/Versions/1.0/lib"'],
    'FRAMEWORK_SEARCH_PATHS' => '/Library/Frameworks',
    'LIBRARY_SEARCH_PATHS' => '/Library/Frameworks/GStreamer.framework/Versions/1.0/lib',
  }
end