#!/usr/bin/env python3
import cv2
import numpy as np
import logging
from typing import Optional, List, Tuple

logger = logging.getLogger(__name__)

class EncodingService:
    """
    Service responsible for encoding a NumPy frame array into a byte stream (e.g., JPEG).
    """
    def __init__(self, default_jpeg_quality: int = 75):
        self.default_jpeg_quality = default_jpeg_quality
        # From original FrameGenerator:
        # int(cv2.IMWRITE_JPEG_OPTIMIZE), 1
        # int(cv2.IMWRITE_JPEG_PROGRESSIVE), 0 # Turn off progressive encoding for speed
        self.default_encode_params = [
            int(cv2.IMWRITE_JPEG_QUALITY), self.default_jpeg_quality,
            int(cv2.IMWRITE_JPEG_OPTIMIZE), 1,
            int(cv2.IMWRITE_JPEG_PROGRESSIVE), 0 
        ]
        logger.info(f"EncodingService initialized with default JPEG quality {default_jpeg_quality}.")

    def encode_frame_to_jpeg(
        self, 
        frame: np.ndarray, 
        quality: Optional[int] = None,
        custom_params: Optional[List[int]] = None
    ) -> Optional[bytes]:
        """
        Encodes a NumPy frame array to JPEG byte stream.

        Args:
            frame: The NumPy array representing the image.
            quality: Optional JPEG quality (0-100). If None, uses default.
            custom_params: Optional list of OpenCV imencode parameters. If provided,
                           quality is ignored and these params are used directly.

        Returns:
            JPEG encoded bytes if successful, None otherwise.
        """
        if not isinstance(frame, np.ndarray) or frame.size == 0:
            logger.error("Cannot encode invalid or empty frame.")
            return None

        encode_params = self.default_encode_params
        if custom_params is not None:
            encode_params = custom_params
        elif quality is not None:
            if 0 <= quality <= 100:
                # Find and update quality in default params, or append if not found (though it should be)
                try:
                    quality_idx = encode_params.index(cv2.IMWRITE_JPEG_QUALITY)
                    encode_params[quality_idx + 1] = quality
                except ValueError: # Should not happen with default_encode_params
                    encode_params.extend([int(cv2.IMWRITE_JPEG_QUALITY), quality])
            else:
                logger.warning(f"Invalid JPEG quality {quality}. Using default {self.default_jpeg_quality}.")
        
        try:
            success, buffer = cv2.imencode('.jpg', frame, encode_params)
            if success:
                return buffer.tobytes()
            else:
                logger.error("cv2.imencode failed for JPEG.")
                return None
        except cv2.error as e:
            logger.error(f"OpenCV error during JPEG encoding: {e}")
            return None
        except Exception as e:
            logger.error(f"Generic error during JPEG encoding: {e}")
            return None

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    encoding_service = EncodingService()

    # Create a dummy frame
    dummy_frame = np.zeros((100, 100, 3), dtype=np.uint8)
    cv2.putText(dummy_frame, "Test", (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)

    # Test encoding with default quality
    jpeg_bytes_default = encoding_service.encode_frame_to_jpeg(dummy_frame)
    if jpeg_bytes_default:
        logger.info(f"Encoded with default quality. Size: {len(jpeg_bytes_default)} bytes.")
        assert len(jpeg_bytes_default) > 0
    else:
        logger.error("Failed to encode with default quality.")

    # Test encoding with specific quality
    jpeg_bytes_custom_q = encoding_service.encode_frame_to_jpeg(dummy_frame, quality=95)
    if jpeg_bytes_custom_q:
        logger.info(f"Encoded with quality 95. Size: {len(jpeg_bytes_custom_q)} bytes.")
        assert len(jpeg_bytes_custom_q) > 0
        if jpeg_bytes_default: # Higher quality should generally mean larger size
             assert len(jpeg_bytes_custom_q) >= len(jpeg_bytes_default) or dummy_frame.size < 1000 # for very small images, size diff might be small/inverted
    else:
        logger.error("Failed to encode with quality 95.")

    # Test encoding with invalid quality
    jpeg_bytes_invalid_q = encoding_service.encode_frame_to_jpeg(dummy_frame, quality=150)
    if jpeg_bytes_invalid_q: # Should use default
        logger.info(f"Encoded with invalid quality (should use default). Size: {len(jpeg_bytes_invalid_q)} bytes.")
        if jpeg_bytes_default:
            assert len(jpeg_bytes_invalid_q) == len(jpeg_bytes_default)

    # Test with empty frame
    empty_frame = np.array([])
    jpeg_bytes_empty = encoding_service.encode_frame_to_jpeg(empty_frame)
    assert jpeg_bytes_empty is None, "Encoding empty frame should fail and return None"
    logger.info("Correctly handled empty frame encoding attempt.")
    
    logger.info("EncodingService test complete.")