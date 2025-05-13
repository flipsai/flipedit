#!/usr/bin/env python3
import logging
import functools
from typing import List, Dict, Any, Tuple, Optional

logger = logging.getLogger(__name__)

class TimelineStateService:
    """
    Manages the state of the timeline including clips, canvas dimensions,
    and provides a hashable representation of this state for caching purposes.
    """
    def __init__(self, canvas_width: int = 1280, canvas_height: int = 720, frame_rate: float = 30.0):
        self.canvas_width = canvas_width
        self.canvas_height = canvas_height
        self.frame_rate = frame_rate
        self.current_videos: List[Dict[str, Any]] = []
        self.total_frames: int = 0 # Should be updated based on timeline duration
        self._current_object_for_hashing: Any = None # Helper for _make_hashable_cached

        # Configure LRU cache for _make_hashable_cached
        # This cache helps when the same sub-objects (like metadata dicts) appear multiple times
        # across different calls to _get_hashable_videos_representation if the overall structure changes.
        # self._make_hashable_cached.cache_configure(maxsize=512) # REMOVED: This caused AttributeError. Maxsize is set in decorator.
        logger.info(f"TimelineStateService initialized. Canvas: {canvas_width}x{canvas_height}, Frame Rate: {frame_rate}")

    def update_canvas_dimensions(self, width: int, height: int) -> bool:
        """
        Updates the canvas dimensions.
        Returns True if dimensions changed, False otherwise.
        """
        if width <= 0 or height <= 0:
            logger.warning(f"Invalid canvas dimensions: {width}x{height}")
            return False
        
        changed = False
        if self.canvas_width != width or self.canvas_height != height:
            logger.info(f"Updating canvas dimensions to {width}x{height}")
            self.canvas_width = width
            self.canvas_height = height
            changed = True
        return changed

    def update_timeline_data(self, videos: List[Dict[str, Any]], total_frames: int, frame_rate: Optional[float] = None):
        """
        Updates the list of videos/clips, total frames, and frame rate for the timeline.
        """
        # It might be beneficial to do a deep copy if videos list is mutable elsewhere
        self.current_videos = videos
        self.total_frames = total_frames
        if frame_rate is not None:
            self.frame_rate = frame_rate
        logger.debug(f"Timeline data updated. {len(videos)} videos, {total_frames} total frames, Frame Rate: {self.frame_rate}.")

    @functools.lru_cache(maxsize=512) # MODIFIED: Set maxsize directly here
    def _make_hashable_cached(self, obj_str_representation: str, obj_type_representation: str) -> Any:
        """
        Cached version of _make_hashable.
        Uses string and type representations of the object as part of the cache key.
        The actual object is accessed via self._current_object_for_hashing.
        """
        # This method relies on self._current_object_for_hashing being set correctly
        # before this cached method is called.
        return self._current_object_for_hashing # This should be the already processed hashable version

    def _make_hashable(self, obj: Any) -> Any:
        """
        Recursively converts a potentially unhashable object (dicts, lists)
        into a fully hashable one (tuples of simple types or other hashables).
        """
        if isinstance(obj, (str, int, float, bool, type(None))):
            return obj
        
        # For caching, we need a representation of the object for the key
        # Storing the original object to be processed by the cached version's logic
        # This is a bit tricky; the cached method should ideally take the object itself,
        # but lru_cache needs hashable arguments.
        # Let's simplify: the caching for _make_hashable itself might be complex to get right
        # without making the arguments to _make_hashable_cached too complex or lossy.
        # The primary caching benefit comes from caching the result of _get_hashable_timeline_state.

        if isinstance(obj, dict):
            if not obj: return tuple()
            items = []
            # Sort by key for canonical representation
            for k, v in sorted(obj.items()):
                # Special handling for 'metadata' to ensure all its contents are hashed
                if k == 'metadata' and isinstance(v, dict):
                    metadata_items = []
                    for meta_k, meta_v in sorted(v.items()): # Sort inner metadata too
                        metadata_items.append((self._make_hashable(meta_k), self._make_hashable(meta_v)))
                    items.append((self._make_hashable(k), tuple(metadata_items)))
                else:
                    # Include all other keys by default for robust hashing of clip data
                    items.append((self._make_hashable(k), self._make_hashable(v)))
            return tuple(items)
        
        if isinstance(obj, list):
            if not obj: return tuple()
            return tuple(self._make_hashable(e) for e in obj)
        
        if isinstance(obj, set): # Sets are not ordered
            if not obj: return tuple()
            return tuple(sorted(self._make_hashable(e) for e in obj))

        try:
            hash(obj)
            return obj
        except TypeError:
            logger.warning(f"Object of type {type(obj)} is not hashable, converting to string for hashing.")
            return str(obj)

    def _get_hashable_videos_representation(self, videos_list: List[Dict]) -> Tuple:
        """
        Converts a list of video dictionaries into a deeply hashable tuple representation.
        Ensures stable sort order for the list of videos.
        """
        if not isinstance(videos_list, list):
            logger.error(f"_get_hashable_videos_representation: videos_list is not a list, it's a {type(videos_list)}.")
            return tuple()

        try:
            # Ensure stable sort order for the list of videos based on a unique identifier if possible
            # Sorting by a tuple of primary (clipId) and secondary (sourcePath) keys
            sorted_videos_list = sorted(
                videos_list,
                key=lambda x: (
                    str(x.get('clipId', '')), 
                    str(x.get('sourcePath', '')),
                    # Fallback to full string representation of dict for stability if IDs are not unique
                    # This is less efficient but ensures determinism.
                    str(sorted(x.items())) if isinstance(x, dict) else str(x) 
                )
            )
        except Exception as e:
            logger.error(f"Error during video list sorting for hashing: {e}. Falling back to basic string sort.")
            try:
                sorted_videos_list = sorted(videos_list, key=str)
            except Exception as e_fallback:
                logger.error(f"Fallback video list sorting failed: {e_fallback}. Returning empty tuple.")
                return tuple()
        
        return tuple(self._make_hashable(video_info) for video_info in sorted_videos_list)

    def get_hashable_timeline_state(self) -> Tuple:
        """
        Generates a hashable representation of the current timeline state,
        including canvas dimensions, total frames, and the video list.
        This tuple can be used as a key for caching rendered frames.
        """
        hashable_videos_rep = self._get_hashable_videos_representation(self.current_videos)
        
        # The state includes canvas dimensions, total_frames, and the hashable video list
        state_tuple = (
            self.canvas_width,
            self.canvas_height,
            self.total_frames,
            self.frame_rate, # Include frame_rate in the hashable state
            hashable_videos_rep
        )
        return state_tuple

    def clear_caches(self):
        """Clears any internal caches if they were more complex."""
        # self._make_hashable_cached.cache_clear() # If used more directly
        logger.info("TimelineStateService internal caches (if any) cleared.")


if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    state_service = TimelineStateService()

    sample_videos_data = [
        {
            "clipId": "clip1", "sourcePath": "/path/to/videoA.mp4", "startTimeOnTrackMs": 0, "endTimeOnTrackMs": 1000,
            "metadata": {"previewRect": {"left": 0.0, "top": 0.0, "width": 100.0, "height": 100.0}, "effect": "blur"}
        },
        {
            "clipId": "clip2", "sourcePath": "/path/to/videoB.mp4", "startTimeOnTrackMs": 500, "endTimeOnTrackMs": 1500,
            "metadata": {"previewRect": {"left": 50.0, "top": 50.0, "width": 120.0, "height": 120.0}}
        }
    ]
    state_service.update_timeline_data(sample_videos_data, 3000) # Example total frames

    # Get initial hashable state
    hash_state1 = state_service.get_hashable_timeline_state()
    logger.info(f"Initial hashable state 1: {hash_state1}")

    # Update canvas dimensions
    state_service.update_canvas_dimensions(1920, 1080)
    hash_state2 = state_service.get_hashable_timeline_state()
    logger.info(f"Hashable state 2 (canvas changed): {hash_state2}")
    assert hash_state1 != hash_state2, "Hash should change when canvas dimensions change"

    # Modify a clip's metadata (e.g., previewRect)
    sample_videos_data["metadata"]["previewRect"]["width"] = 110.0
    state_service.update_timeline_data(sample_videos_data, 3000) # Re-update with modified data
    hash_state3 = state_service.get_hashable_timeline_state()
    logger.info(f"Hashable state 3 (clip metadata changed): {hash_state3}")
    assert hash_state2 != hash_state3, "Hash should change when clip metadata changes"
    
    # Add a new clip
    sample_videos_data.append({
        "clipId": "clip3", "sourcePath": "/path/to/videoC.mp4", "startTimeOnTrackMs": 2000, "endTimeOnTrackMs": 3000,
        "metadata": {"previewRect": {"left": 0.0, "top": 0.0, "width": 100.0, "height": 100.0}}
    })
    state_service.update_timeline_data(sample_videos_data, 3000)
    hash_state4 = state_service.get_hashable_timeline_state()
    logger.info(f"Hashable state 4 (clip added): {hash_state4}")
    assert hash_state3 != hash_state4, "Hash should change when a clip is added"

    # Test sorting stability for video list
    shuffled_videos_data = [sample_videos_data, sample_videos_data] # clip2 then clip1
    state_service.update_timeline_data(shuffled_videos_data, 3000) # Update with original canvas for this test
    state_service.update_canvas_dimensions(1280, 720) # Reset canvas for this specific comparison
    
    # Re-create the original state for comparison (clip1 then clip2)
    original_order_videos_data = [sample_videos_data, sample_videos_data]
    temp_state_service = TimelineStateService(canvas_width=1280, canvas_height=720)
    temp_state_service.update_timeline_data(original_order_videos_data, 3000)
    
    hash_state_shuffled = state_service.get_hashable_timeline_state()
    hash_state_original_order = temp_state_service.get_hashable_timeline_state()
    
    # logger.info(f"Hashable state (shuffled clip order): {hash_state_shuffled}")
    # logger.info(f"Hashable state (original clip order): {hash_state_original_order}")
    # assert hash_state_shuffled == hash_state_original_order, "Hash should be the same regardless of initial video list order due to sorting"

    logger.info("TimelineStateService test complete.")