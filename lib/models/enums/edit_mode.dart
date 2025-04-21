/// Defines the editing modes for timeline tools
enum EditMode {
  /// Default selection/move tool
  select,

  /// Ripple trim: adjust clip edge and ripple downstream clips
  rippleTrim,

  /// Roll edit: move boundary between two adjacent clips
  rollEdit,

  /// Slip edit: slide in/out points within the source media without moving the clip on the timeline
  slip,

  /// Slide edit: move clip on timeline while keeping duration and adjust neighbors
  slide,
}
