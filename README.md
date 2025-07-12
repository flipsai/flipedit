# flipedit

A new Flutter project.

## Command to run in debug mode
GST_DEBUG=3 RUST_LOG=debug RUST_BACKTRACE=full flutter run -d linux --enable-impeller

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# MdkPlayerService & Helper Classes Documentation

## Table of Contents
1. [Overview](#overview)
2. [Class Responsibilities](#class-responsibilities)
   - [MdkPlayerService](#mdkplayerservice)
   - [MdkPlayerErrorHandler](#mdkplayererrorhandler)
   - [MdkTextureManager](#mdktexturemanager)
   - [MdkMediaStatusMonitor](#mdkmediastatusmonitor)
3. [API Documentation](#api-documentation)
4. [Usage Examples](#usage-examples)
5. [Integration Guide](#integration-guide)
6. [Troubleshooting](#troubleshooting)
7. [Architecture Overview](#architecture-overview)

---

## Overview

The `MdkPlayerService` and its helper classes provide a robust, MVVM-compliant abstraction for managing video playback using the MDK player in Flutter. The service handles player lifecycle, error recovery, texture management, and media status monitoring, exposing state via `ValueNotifier`s for seamless ViewModel integration.

---

## Class Responsibilities

### MdkPlayerService

- **Purpose:** Central service for managing the MDK player instance.
- **Responsibilities:**
  - Player lifecycle (creation, disposal, re-initialization)
  - Exposes playback state via `ValueNotifier`s (`currentFrameMatNotifier`, `isPlaying`, `isPlayerReady`)
  - Delegates error handling, texture management, and status monitoring to helper classes
  - Integrates with ViewModels in MVVM architecture

### MdkPlayerErrorHandler

- **Purpose:** Handles player initialization errors and recovery.
- **Responsibilities:**
  - Tracks consecutive errors and manages backoff/retry logic
  - Resets error state on successful recovery
  - Triggers player re-initialization after failures

### MdkTextureManager

- **Purpose:** Manages video surface and texture updates.
- **Responsibilities:**
  - Sets video surface size
  - Updates texture and notifies listeners
  - Handles player events related to texture changes

### MdkMediaStatusMonitor

- **Purpose:** Monitors and reacts to player media status changes.
- **Responsibilities:**
  - Updates readiness state based on media status
  - Provides async waiting for "prepared" status
  - Handles invalid/no-media transitions

---

## API Documentation

### MdkPlayerService

```dart
class MdkPlayerService {
  mdk.Player? get player;
  ValueNotifier<cv.Mat?> currentFrameMatNotifier;
  int get textureId;
  ValueNotifier<bool> isPlayingNotifier;
  ValueNotifier<bool> isPlayerReadyNotifier;

  MdkPlayerService();
  // ...other public methods
}
```

- **player**: The underlying MDK player instance.
- **currentFrameMatNotifier**: Notifies listeners of the current video frame as a `cv.Mat`.
- **isPlayingNotifier**: Notifies listeners of playback state.
- **isPlayerReadyNotifier**: Notifies listeners when the player is ready.

#### Key Methods

- `MdkPlayerService()`: Initializes the player and helper classes.
- `_initPlayer()`: (private) Handles player creation, disposal, and state reset.

### MdkPlayerErrorHandler

```dart
class MdkPlayerErrorHandler {
  bool get isRecovering;
  void resetErrorState();
  void handlePlayerCreationError();
}
```

- **isRecovering**: Indicates if the handler is in recovery/backoff mode.
- **resetErrorState()**: Resets error counters and recovery state.
- **handlePlayerCreationError()**: Tracks errors, manages retry/backoff, and triggers recovery.

### MdkTextureManager

```dart
class MdkTextureManager {
  bool setVideoSurfaceSize(int width, int height);
  Future<int> updateTexture({required int width, required int height});
  void onPlayerEvent(dynamic event);
}
```

- **setVideoSurfaceSize**: Sets the video output surface size.
- **updateTexture**: Updates the video texture and returns the new texture ID.
- **onPlayerEvent**: Handles player events, updating texture as needed.

### MdkMediaStatusMonitor

```dart
class MdkMediaStatusMonitor {
  bool onMediaStatusChanged(mdk.MediaStatus oldStatus, mdk.MediaStatus newStatus);
  Future<bool> waitForPreparedStatus({int timeoutMs = 2000});
  void cancelWaits();
}
```

- **onMediaStatusChanged**: Updates readiness and handles status transitions.
- **waitForPreparedStatus**: Waits asynchronously for the player to reach "prepared" status.
- **cancelWaits**: Cancels any pending wait operations.

---

## Usage Examples

```dart
final playerService = MdkPlayerService();

// Listen for player readiness
playerService.isPlayerReadyNotifier.addListener(() {
  if (playerService.isPlayerReadyNotifier.value) {
    // Player is ready for playback
  }
});

// Set video surface size
playerService._textureManager.setVideoSurfaceSize(1920, 1080);

// Update texture
await playerService._textureManager.updateTexture(width: 1920, height: 1080);

// Wait for prepared status
await playerService._mediaStatusMonitor.waitForPreparedStatus();
```

---

## Integration Guide

- Register `MdkPlayerService` as a singleton in your service locator.
- Inject the service into your ViewModel.
- Use the exposed `ValueNotifier`s to drive UI updates in your View.
- Delegate error handling, texture, and status operations to the respective helpers as needed.

---

## Troubleshooting

- **Player fails to initialize repeatedly:** The error handler will back off after 3 consecutive failures and attempt recovery after a delay.
- **Texture not updating:** Ensure the player is in the correct state and surface size is set before calling `updateTexture`.
- **Player not ready:** Use `waitForPreparedStatus` to await readiness, and check for invalid/no-media states.

---

## Architecture Overview

### MVVM Compliance

- **Service Layer:** `MdkPlayerService` and helpers encapsulate all player logic and state, exposing only observable state to ViewModels.
- **ViewModel Layer:** Subscribes to `ValueNotifier`s, reacts to state changes, and issues commands to the service.
- **View Layer:** Binds to ViewModel properties, updates UI in response to state changes.

### Data Flow

```
[View] <-> [ViewModel] <-> [MdkPlayerService] <-> [MDK Player]
```

- State changes in the player are propagated via `ValueNotifier`s.
- ViewModels react to these changes and update the View.
- Commands from the ViewModel invoke service methods, which may trigger helper logic.

### Design Decisions

- **Separation of Concerns:** Error handling, texture management, and status monitoring are delegated to dedicated helper classes.
- **Resilience:** Automatic error recovery and backoff logic for robust playback.
- **Observability:** Use of `ValueNotifier` for reactive UI updates.

---

## Preview Panel

The preview panel allows you to visualize the timeline videos with configurable position and size. Selected clips in the timeline appear in the preview panel with the following features:

- **Position Control**: Set the X and Y coordinates for each clip in the preview panel
- **Size Control**: Adjust width and height of each clip in the preview
- **Presets**: Quick buttons for common aspect ratios (16:9, 1:1, 3:4, 4:3)
- **Flip Control**: Horizontal and vertical flipping options
- **Centering**: Center a clip in the preview panel with a single click

When a clip is selected in the timeline, it will be highlighted in the preview panel with handles for visual identification. The transform controls appear in the Inspector panel.

### Starting the Preview Server

The preview rendering is powered by a Python WebSocket server. To start the preview server:

```
python3 assets/video_stream_server.py
```

The server must be running for the preview panel to display video content.

## Features

### Player ViewModel (`NativePlayerViewModel`)

- Manages native playback state (OpenCV-based).
- Exposes playback state via `ValueNotifier`s (`currentFrameMatNotifier`, `isPlaying`, `isPlayerReady`)
- Handles playback controls (play, pause, seek).

### Player ViewModels

#### `NativePlayerViewModel`
Responsible for managing the state and logic of the native video player (using OpenCV frames).

**Key Responsibilities:**
- Initializes and manages the `TimelineProcessingService` for frame generation.
- Provides `ValueNotifier<cv.Mat?> currentFrameMatNotifier` for the UI to listen to new frames.
- Exposes playback status (isPlaying, isInitialized, status messages).
- Handles playback timing and updates the current frame in `TimelineNavigationViewModel`.

**Key Members:**
- `ValueListenable<cv.Mat?> currentFrameMatNotifier`: Notifies listeners of the current video frame as a `cv.Mat`.
- `ValueListenable<bool> isInitializedNotifier`: Indicates if the player is ready.
- `ValueListenable<bool> isPlayingNotifier`: (Derived from `TimelineNavigationViewModel`) Indicates playback state.
