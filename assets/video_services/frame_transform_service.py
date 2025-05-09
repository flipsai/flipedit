#!/usr/bin/env python3
import cv2
import numpy as np
import logging
from typing import Dict, Any, Tuple, Optional

logger = logging.getLogger(__name__)

class FrameTransformService:
    """
    Service responsible for applying transformations to individual frames,
    such as resizing, flipping, and eventually other effects.
    """
    def __init__(self):
        # Configuration for transformations, e.g., default interpolation
        self.resize_interpolation = cv2.INTER_NEAREST # Fast, from original FrameGenerator
        logger.info("FrameTransformService initialized.")

    def transform_frame(
        self,
        frame: np.ndarray,
        clip_info: Dict[str, Any], # Contains metadata like previewRect, flip
        canvas_width: int,
        canvas_height: int
    ) -> Tuple[Optional[np.ndarray], int, int, int, int]:
        """
        Processes a single frame based on clip_info metadata (resize, flip, etc.)
        and positions it relative to the canvas.

        Args:
            frame: The raw input frame (NumPy array).
            clip_info: Dictionary containing metadata for the clip, including 'previewRect'
                       and 'flip' instructions.
            canvas_width: Width of the target canvas.
            canvas_height: Height of the target canvas.

        Returns:
            A tuple containing:
            - processed_frame: The transformed frame (NumPy array), or None if error.
            - x: The calculated X position of the top-left corner of the processed frame
                 relative to the canvas.
            - y: The calculated Y position.
            - width: The final width of the processed frame.
            - height: The final height of the processed frame.
        """
        if not isinstance(frame, np.ndarray) or frame.size == 0:
            logger.warning("Transform_frame called with invalid or empty frame.")
            return None, 0, 0, 0, 0

        metadata = clip_info.get('metadata', {})
        preview_rect_data = metadata.get('previewRect') # Expected: {'left': l, 'top': t, 'width': w, 'height': h}
        
        frame_height_orig, frame_width_orig = frame.shape[:2]

        # --- Determine default positioning and sizing (fit and center) ---
        default_width, default_height = frame_width_orig, frame_height_orig
        if frame_width_orig == 0 or frame_height_orig == 0:
            logger.warning("Original frame has zero dimension, using canvas size as default.")
            default_width = canvas_width
            default_height = canvas_height
        elif frame_width_orig > canvas_width or frame_height_orig > canvas_height:
            # Scale down to fit canvas while maintaining aspect ratio
            width_ratio = canvas_width / frame_width_orig
            height_ratio = canvas_height / frame_height_orig
            scale_ratio = min(width_ratio, height_ratio)
            default_width = int(frame_width_orig * scale_ratio)
            default_height = int(frame_height_orig * scale_ratio)
        
        default_left = (canvas_width - default_width) / 2
        default_top = (canvas_height - default_height) / 2
        
        default_rect_params = {
            'left': default_left, 'top': default_top,
            'width': float(default_width), 'height': float(default_height)
        }
        # --- End Default Positioning ---

        target_x, target_y, target_width, target_height = 0, 0, 0, 0

        if isinstance(preview_rect_data, dict):
            target_x = int(preview_rect_data.get('left', default_rect_params['left']))
            target_y = int(preview_rect_data.get('top', default_rect_params['top']))
            target_width = max(1, int(preview_rect_data.get('width', default_rect_params['width'])))
            target_height = max(1, int(preview_rect_data.get('height', default_rect_params['height'])))
            logger.debug(f"Using previewRect from metadata: x={target_x}, y={target_y}, w={target_width}, h={target_height}")
        else:
            target_x = int(default_rect_params['left'])
            target_y = int(default_rect_params['top'])
            target_width = int(default_rect_params['width'])
            target_height = int(default_rect_params['height'])
            logger.debug(f"Using default previewRect (centered): x={target_x}, y={target_y}, w={target_width}, h={target_height}")

        # Ensure width and height for resize are at least 1
        resize_width = max(1, target_width)
        resize_height = max(1, target_height)
        processed_frame = frame

        # --- Resize ---
        try:
            if frame_width_orig > 0 and frame_height_orig > 0:
                # Skip resize if dimensions are already very close (e.g., within 1 pixel)
                if abs(frame_width_orig - resize_width) > 1 or abs(frame_height_orig - resize_height) > 1:
                    processed_frame = cv2.resize(frame, (resize_width, resize_height),
                                                 interpolation=self.resize_interpolation)
                # Else, frame is already the target size or close enough
            else:
                logger.warning(f"Original frame has zero dimension: {frame_width_orig}x{frame_height_orig}. Skipping resize.")
        except cv2.error as e:
            logger.error(f"OpenCV Error resizing frame to {resize_width}x{resize_height}: {e}. Original: {frame_width_orig}x{frame_height_orig}")
            return None, int(default_rect_params['left']), int(default_rect_params['top']), frame_width_orig, frame_height_orig
        except Exception as e:
            logger.error(f"Generic error resizing frame: {e}")
            return None, int(default_rect_params['left']), int(default_rect_params['top']), frame_width_orig, frame_height_orig
        
        # --- Flip ---
        # Flip instruction expected in metadata, e.g., metadata={'flip': 'vertical'} or {'flip': 'horizontal'}
        flip_instruction = metadata.get('flip') # Could be 'vertical', 'horizontal', 'both', or None
        if flip_instruction == 'vertical':
            processed_frame = cv2.flip(processed_frame, 0)
        elif flip_instruction == 'horizontal':
            processed_frame = cv2.flip(processed_frame, 1)
        elif flip_instruction == 'both':
            processed_frame = cv2.flip(processed_frame, -1)

        # --- Other transformations (e.g., effects) would go here ---

        return processed_frame, target_x, target_y, target_width, target_height

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    transform_service = FrameTransformService()

    # Create a dummy frame
    dummy_frame_orig = np.zeros((200, 300, 3), dtype=np.uint8) # H=200, W=300
    cv2.putText(dummy_frame_orig, "ORIG", (50, 100), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)

    canvas_w, canvas_h = 1280, 720

    # Test 1: Default transform (fit and center)
    clip_info1 = {"metadata": {}}
    processed1, x1, y1, w1, h1 = transform_service.transform_frame(dummy_frame_orig.copy(), clip_info1, canvas_w, canvas_h)
    if processed1 is not None:
        logger.info(f"Test 1 (default): Pos=({x1},{y1}), Size=({w1}x{h1}), FrameShape={processed1.shape}")
        # Expected: scaled to fit 720p (e.g. 300x200 -> 1080x720 if aspect matches, or letterboxed)
        # For 300x200 into 1280x720, height ratio = 3.6, width ratio = 4.26. So scale by 3.6
        # New H = 200*3.6 = 720. New W = 300*3.6 = 1080.
        # X = (1280-1080)/2 = 100. Y = (720-720)/2 = 0.
        assert h1 == 720 and w1 == 1080
        assert x1 == 100 and y1 == 0

    # Test 2: Specific previewRect
    clip_info2 = {
        "metadata": {
            "previewRect": {"left": 10.0, "top": 20.0, "width": 150.0, "height": 100.0}
        }
    }
    processed2, x2, y2, w2, h2 = transform_service.transform_frame(dummy_frame_orig.copy(), clip_info2, canvas_w, canvas_h)
    if processed2 is not None:
        logger.info(f"Test 2 (previewRect): Pos=({x2},{y2}), Size=({w2}x{h2}), FrameShape={processed2.shape}")
        assert x2 == 10 and y2 == 20 and w2 == 150 and h2 == 100
        assert processed2.shape == (100, 150, 3)

    # Test 3: previewRect and vertical flip
    clip_info3 = {
        "metadata": {
            "previewRect": {"left": 0.0, "top": 0.0, "width": 300.0, "height": 200.0}, # Original size
            "flip": "vertical"
        }
    }
    processed3, x3, y3, w3, h3 = transform_service.transform_frame(dummy_frame_orig.copy(), clip_info3, canvas_w, canvas_h)
    if processed3 is not None:
        logger.info(f"Test 3 (flip): Pos=({x3},{y3}), Size=({w3}x{h3}), FrameShape={processed3.shape}")
        assert x3 == 0 and y3 == 0 and w3 == 300 and h3 == 200
        # Visual check would be needed for flip, or compare with cv2.flip(dummy_frame_orig, 0)

    logger.info("FrameTransformService test complete.")