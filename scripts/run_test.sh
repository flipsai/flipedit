#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---

# Specify the default test target (e.g., all integration tests or a specific file)
# Use "$1" to allow passing a specific test file as an argument to the script
# Example: ./scripts/run_test.sh integration_test/my_specific_test.dart
DEFAULT_TEST_TARGET="integration_test"
TEST_TARGET=${1:-$DEFAULT_TEST_TARGET}

# Specify the target device (replace with your actual device ID or 'macos', 'chrome', etc.)
# You could also make this an argument: DEVICE_ID=${2:-"macos"}
DEVICE_ID="macos"

# Add any necessary Dart defines
# Since the automatic FLUTTER_TEST detection might be inconsistent in some setups,
# explicitly defining it here ensures the desired behavior for tests run via this script.
DART_DEFINES="--dart-define=TEST_MODE=true"

# Add other flags like coverage if needed
# OTHER_FLAGS="--coverage"
OTHER_FLAGS=""

# --- Execution ---

echo "Running Flutter integration tests..."
echo "Target: $TEST_TARGET"
echo "Device: $DEVICE_ID"
echo "Dart Defines: $DART_DEFINES"
echo "Other Flags: $OTHER_FLAGS"

flutter test $TEST_TARGET -d $DEVICE_ID $DART_DEFINES $OTHER_FLAGS

echo "Tests completed."