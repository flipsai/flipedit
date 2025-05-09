#!/usr/bin/env python3
import cv2
import numpy as np
import logging
from typing import List, Tuple, Optional

logger = logging.getLogger(__name__)

class CompositingService:
    """
    Service responsible for compositing multiple processed frames onto a
    base canvas.
    """
    def __init__(self):
        logger.info("CompositingService initialized.")

    def create_blank_canvas(self, width: int, height: int, color: Tuple[int, int, int] = (0, 0, 0)) -> np.ndarray:
        """
        Creates a blank canvas of the given dimensions and color.
        Default color is black.
        """
        if width <= 0 or height <= 0:
            logger.error(f"Invalid dimensions for blank canvas: {width}x{height}")
            # Return a minimal 1x1 black pixel array to avoid downstream errors
            return np.zeros((1, 1, 3), dtype=np.uint8) 
        return np.full((height, width, 3), color, dtype=np.uint8)

    def composite_frames(
        self,
        base_canvas: np.ndarray,
        processed_frames_with_positions: List[Tuple[np.ndarray, int, int, int, int]]
    ) -> np.ndarray:
        """
        Composites a list of processed frames onto a base canvas.

        Args:
            base_canvas: The base image (NumPy array) to draw upon.
            processed_frames_with_positions: A list of tuples, where each tuple contains:
                - processed_frame: The frame to overlay (NumPy array).
                - x: Target X position on the canvas for the top-left of the frame.
                - y: Target Y position.
                - width: Width of the processed_frame.
                - height: Height of the processed_frame.
        
        Returns:
            The final composited frame (NumPy array).
        """
        if not isinstance(base_canvas, np.ndarray) or base_canvas.size == 0:
            logger.error("Base canvas is invalid or empty.")
            # Attempt to return a default small black canvas if base is unusable
            return self.create_blank_canvas(1,1) 

        # Work on a copy to avoid modifying the original base_canvas if it's reused
        composite_image = base_canvas.copy()
        canvas_height, canvas_width = composite_image.shape[:2]

        for frame_info in processed_frames_with_positions:
            try:
                processed_frame, x, y, width, height = frame_info
            except ValueError:
                logger.error(f"Invalid data in processed_frames_with_positions: {frame_info}. Skipping this frame.")
                continue

            if not isinstance(processed_frame, np.ndarray) or processed_frame.size == 0:
                logger.warning(f"Skipping invalid or empty processed frame for position ({x},{y}).")
                continue
            
            if width <= 0 or height <= 0:
                logger.warning(f"Skipping frame with invalid dimensions: {width}x{height} at ({x},{y}).")
                continue

            # Determine the visible part of the frame and its corresponding
            # location on the canvas. This handles cases where the frame is
            # partially or fully outside the canvas.

            # Top-left corner of the frame on the canvas
            canvas_x_start = x
            canvas_y_start = y

            # Top-left corner of the source frame slice
            frame_x_start_slice = 0
            frame_y_start_slice = 0

            # Adjust if frame starts off-canvas to the left/top
            if canvas_x_start < 0:
                frame_x_start_slice = -canvas_x_start # Amount of frame to skip from left
                width += canvas_x_start # Reduce effective width
                canvas_x_start = 0
            
            if canvas_y_start < 0:
                frame_y_start_slice = -canvas_y_start # Amount of frame to skip from top
                height += canvas_y_start # Reduce effective height
                canvas_y_start = 0
            
            # Ensure there's still a visible part of the frame
            if width <= 0 or height <= 0:
                logger.debug(f"Frame at original ({x},{y}) is entirely off-canvas after top/left clipping.")
                continue

            # Bottom-right corner of the frame on the canvas
            canvas_x_end = canvas_x_start + width
            canvas_y_end = canvas_y_start + height

            # Bottom-right corner of the source frame slice
            # Initially, it's the full (remaining) width/height of the frame
            frame_x_end_slice = frame_x_start_slice + width
            frame_y_end_slice = frame_y_start_slice + height

            # Adjust if frame ends off-canvas to the right/bottom
            if canvas_x_end > canvas_width:
                # Reduce how much of the frame we take by the overflow
                frame_x_end_slice -= (canvas_x_end - canvas_width)
                canvas_x_end = canvas_width
            
            if canvas_y_end > canvas_height:
                frame_y_end_slice -= (canvas_y_end - canvas_height)
                canvas_y_end = canvas_height

            # Final dimensions of the slice to take from processed_frame
            # and to place on the canvas
            slice_width = canvas_x_end - canvas_x_start
            slice_height = canvas_y_end - canvas_y_start

            if slice_width <= 0 or slice_height <= 0:
                logger.debug(f"Frame at original ({x},{y}) is entirely off-canvas after all clipping.")
                continue
            
            try:
                # Ensure slices are valid for the processed_frame
                if not (0 <= frame_y_start_slice < frame_y_end_slice <= processed_frame.shape[0] and \
                        0 <= frame_x_start_slice < frame_x_end_slice <= processed_frame.shape[1]):
                    logger.error(f"Invalid slice for processed_frame. Frame shape: {processed_frame.shape}, "
                                 f"Slice Y: {frame_y_start_slice}:{frame_y_end_slice}, "
                                 f"Slice X: {frame_x_start_slice}:{frame_x_end_slice}. Skipping.")
                    continue

                frame_slice = processed_frame[
                    frame_y_start_slice:frame_y_end_slice,
                    frame_x_start_slice:frame_x_end_slice
                ]
                
                # Place the slice onto the composite image
                composite_image[
                    canvas_y_start:canvas_y_end,
                    canvas_x_start:canvas_x_end
                ] = frame_slice
                logger.debug(f"Composited frame: src slice ({frame_y_start_slice}:{frame_y_end_slice}, {frame_x_start_slice}:{frame_x_end_slice}) "
                             f"to canvas ({canvas_y_start}:{canvas_y_end}, {canvas_x_start}:{canvas_x_end})")

            except IndexError as e:
                logger.error(f"IndexError during compositing frame at ({x},{y}) with size ({width}x{height}). "
                             f"Frame shape: {processed_frame.shape}, Slice Y: {frame_y_start_slice}:{frame_y_end_slice}, "
                             f"Slice X: {frame_x_start_slice}:{frame_x_end_slice}. Canvas target Y: {canvas_y_start}:{canvas_y_end}, "
                             f"Canvas target X: {canvas_x_start}:{canvas_x_end}. Error: {e}")
            except Exception as e:
                logger.error(f"Generic error during compositing: {e}")
        
        return composite_image

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    comp_service = CompositingService()

    canvas_w, canvas_h = 300, 200
    base = comp_service.create_blank_canvas(canvas_w, canvas_h, color=(50, 50, 50)) # Dark grey

    # Frame 1: Red square
    frame1 = np.full((50, 50, 3), (0, 0, 255), dtype=np.uint8) # BGR: Red
    pos1 = (10, 10, 50, 50) # x, y, w, h

    # Frame 2: Green rectangle, partially overlapping
    frame2 = np.full((60, 80, 3), (0, 255, 0), dtype=np.uint8) # BGR: Green
    pos2 = (40, 30, 80, 60)

    # Frame 3: Blue, partially off-canvas (top-left)
    frame3 = np.full((70, 70, 3), (255, 0, 0), dtype=np.uint8) # BGR: Blue
    pos3 = (-20, -15, 70, 70)
    
    # Frame 4: Yellow, partially off-canvas (bottom-right)
    frame4 = np.full((50, 50, 3), (0, 255, 255), dtype=np.uint8) # BGR: Yellow
    pos4 = (canvas_w - 30, canvas_h - 20, 50, 50)

    frames_to_composite = [
        (frame1, *pos1),
        (frame2, *pos2),
        (frame3, *pos3),
        (frame4, *pos4),
    ]

    result_image = comp_service.composite_frames(base, frames_to_composite)

    if result_image is not None:
        logger.info(f"Compositing test successful. Result image shape: {result_image.shape}")
        # To view the result if running locally with OpenCV UI capabilities:
        # cv2.imshow("Composited Result", result_image)
        # cv2.waitKey(0)
        # cv2.destroyAllWindows()
        
        # Basic checks
        # Check red pixel from frame1
        assert np.array_equal(result_image,), "Frame 1 (Red) not composited correctly"
        # Check green pixel from frame2
        assert np.array_equal(result_image,), "Frame 2 (Green) not composited correctly"
        # Check blue pixel from frame3 (visible part)
        # Original frame3 at (-20, -15). Canvas (0,0) is frame3 (20,15)
        assert np.array_equal(result_image,), "Frame 3 (Blue) not composited correctly at edge"
         # Check yellow pixel from frame4 (visible part)
        # Original frame4 at (270, 180). Canvas (299,199) is frame4 (29,19)
        assert np.array_equal(result_image[canvas_h-1, canvas_w-1],), "Frame 4 (Yellow) not composited correctly at edge"


    logger.info("CompositingService test complete.")