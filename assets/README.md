# FlipEdit Video Preview Server

This component provides real-time video preview services for the FlipEdit video editor, directly accessing the Flutter app's SQLite database.

## Overview

The FlipEdit video preview server:
- Provides real-time video frame rendering through OpenCV
- Communicates with the Flutter UI via WebSockets
- **Directly accesses the Flutter app's SQLite database** to retrieve timeline and clip information
- Handles playback control (play, pause, seek)
- Manages clip transformations and compositing

## Direct Database Access

Instead of relying on WebSocket messages to receive clip data from Flutter, this server now directly accesses the underlying SQLite database used by the Flutter app's Drift ORM. This offers several advantages:

- **Improved reliability**: Eliminates potential data transfer issues between Flutter and Python
- **Reduced latency**: No need to serialize and transfer clip data over WebSockets
- **Reduced complexity**: Python server gets data directly from the source of truth
- **Better synchronization**: Changes made in Flutter are immediately visible to the preview server

### How It Works

1. The `db_access.py` module provides a SQLAlchemy ORM interface to the Flutter app's SQLite database
2. When the server starts, it automatically connects to the most recent project database
3. The `TimelineManager` refreshes data directly from the database
4. When a clip is resized or moved in Flutter, the database is updated
5. The Python server refreshes from the database on command (via `refresh_from_db` message)

## Installation

To set up the FlipEdit video preview server:

1. Install Python 3.8+ and the required dependencies:
   ```
   pip install -r requirements.txt
   ```

2. Ensure SQLite is properly installed on your system

## Usage

Run the video preview server:

```
python main.py
```

By default, the server will:
- Listen on WebSocket port 8080
- Serve HTTP API on port 8081
- Automatically find and connect to the most recent FlipEdit project database

## API

### WebSocket Commands

- `play`: Start video playback
- `pause`: Pause video playback
- `seek:<frame>`: Seek to a specific frame
- `refresh_from_db`: Refresh timeline data from the database

## Troubleshooting

- If the database connection fails, check that:
  - The database files exist at `~/Documents/flipedit_projects_metadata.sqlite` and in the paths specified within
  - The database files are readable by the Python process
  - The SQLite version is compatible (SQLite 3.31.0+)

## Integration with Flutter

While this server can directly access the database, it still maintains WebSocket communication with the Flutter UI to:
- Provide rendered frames back to the UI
- Receive playback control commands
- Synchronize state between UI and preview server

## License

This software is part of the FlipEdit video editor and is subject to its licensing terms. 