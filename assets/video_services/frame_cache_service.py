#!/usr/bin/env python3
import logging
import collections
import threading
from typing import Optional, Any
import numpy as np

logger = logging.getLogger(__name__)

class FrameCacheService:
    """
    Service responsible for caching processed frames (NumPy arrays).
    Uses an OrderedDict to implement a basic LRU caching strategy.
    """
    def __init__(self, max_cache_entries: int = 240): # Default from original FrameGenerator
        self.max_cache_entries = max_cache_entries
        self._cache = collections.OrderedDict()
        self._lock = threading.RLock() # For thread-safe access to the cache
        logger.info(f"FrameCacheService initialized with max {max_cache_entries} entries.")

    def get_frame(self, cache_key: str) -> Optional[Any]:
        """
        Retrieves an item from the cache.
        Moves the accessed item to the end to mark it as recently used (for LRU).
        """
        with self._lock:
            if cache_key in self._cache:
                frame = self._cache[cache_key]
                self._cache.move_to_end(cache_key) # Mark as recently used
                logger.debug(f"Cache HIT for key: {cache_key}")
                return frame
            logger.debug(f"Cache MISS for key: {cache_key}")
            return None

    def put_frame(self, cache_key: str, item: Any):
        """
        Adds an item to the cache.
        If the cache exceeds its maximum size, the oldest entry is removed.
        """
        # Removed isinstance check to allow caching of generic items (e.g., tuples)
        # if not isinstance(frame, np.ndarray):
        #     logger.warning(f"Attempted to cache non-numpy array for key {cache_key}. Type: {type(frame)}")
        #     return

        with self._lock:
            if cache_key in self._cache:
                # If key exists, remove it first to update its position (move_to_end)
                self._cache.pop(cache_key)
            elif len(self._cache) >= self.max_cache_entries:
                # Cache is full, remove the oldest item (Least Recently Used)
                oldest_key, _ = self._cache.popitem(last=False)
                logger.debug(f"Cache full. Removed oldest entry: {oldest_key}")
            
            self._cache[cache_key] = item
            logger.debug(f"Cached item with key: {cache_key}. Cache size: {len(self._cache)}")

    def clear_cache(self):
        """Clears all items from the cache."""
        with self._lock:
            self._cache.clear()
        logger.info("FrameCacheService cache cleared.")

    def get_cache_size(self) -> int:
        """Returns the current number of items in the cache."""
        with self._lock:
            return len(self._cache)

    def __del__(self):
        self.clear_cache()
        logger.info("FrameCacheService instance deleted and cache cleared.")

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    cache_service = FrameCacheService(max_cache_entries=3)

    # Create some dummy frames (numpy arrays)
    frame1 = np.array([[]], dtype=np.uint8)
    frame2 = np.array([[]], dtype=np.uint8)
    frame3 = np.array([[]], dtype=np.uint8)
    frame4 = np.array([[]], dtype=np.uint8)

    # Test putting frames
    cache_service.put_frame("video1:frame10", frame1)
    cache_service.put_frame("video1:frame11", frame2)
    cache_service.put_frame("video2:frame5", frame3)
    
    logger.info(f"Cache size after 3 puts: {cache_service.get_cache_size()}") # Expected: 3

    # Test getting frames
    ret_frame = cache_service.get_frame("video1:frame10")
    assert ret_frame is not None and np.array_equal(ret_frame, frame1), "Frame 1 retrieval failed"
    logger.info("Frame 1 retrieved successfully.")

    # Test LRU eviction
    cache_service.put_frame("video3:frame1", frame4) # This should evict "video1:frame11"
    logger.info(f"Cache size after 4th put (eviction expected): {cache_service.get_cache_size()}") # Expected: 3

    ret_frame_evicted = cache_service.get_frame("video1:frame11")
    assert ret_frame_evicted is None, "Frame 2 should have been evicted"
    logger.info("Frame 2 (video1:frame11) correctly evicted.")
    
    ret_frame_still_present = cache_service.get_frame("video2:frame5")
    assert ret_frame_still_present is not None, "Frame 3 (video2:frame5) should still be present"
    logger.info("Frame 3 (video2:frame5) still present.")

    # Test clearing cache
    cache_service.clear_cache()
    logger.info(f"Cache size after clear: {cache_service.get_cache_size()}") # Expected: 0
    assert cache_service.get_cache_size() == 0, "Cache clear failed"

    logger.info("FrameCacheService test complete.")