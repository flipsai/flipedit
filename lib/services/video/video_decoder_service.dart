import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:ffi/ffi.dart';
import '../../models/decoded_frame.dart';

class VideoDecoderService {
  static const int bufferSize = 10; // Decode 10 frames ahead
  static const int batchSize = 3; // Decode 3 frames at once
  
  static Future<void> decoderEntryPoint(DecoderParams params) async {
    print('VideoDecoderService.decoderEntryPoint started');
    final sendPort = params.sendPort;
    final videoPath = params.videoPath;
    
    print('Opening video: $videoPath');
    // Open video capture
    final cap = cv.VideoCapture.fromFile(videoPath);
    if (!cap.isOpened) {
      print('Failed to open video');
      sendPort.send(DecoderError('Failed to open video: $videoPath'));
      return;
    }
    print('Video opened successfully');
    
    // Send initial info
    final frameCount = cap.get(cv.CAP_PROP_FRAME_COUNT).toInt();
    final fps = cap.get(cv.CAP_PROP_FPS);
    final width = cap.get(cv.CAP_PROP_FRAME_WIDTH).toInt();
    final height = cap.get(cv.CAP_PROP_FRAME_HEIGHT).toInt();
    
    print('Video info: ${width}x${height}, $frameCount frames @ $fps fps');
    
    sendPort.send(VideoInfo(
      frameCount: frameCount,
      fps: fps,
      width: width,
      height: height,
    ));
    
    // Create receive port for control messages
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    bool isRunning = true;
    int targetFrame = 0;
    
    // Listen for control messages
    receivePort.listen((message) {
      if (message is SeekCommand) {
        targetFrame = message.frame;
        if (cap.isOpened) {
          print('VideoDecoderService: SeekCommand to frame $targetFrame');
          cap.set(cv.CAP_PROP_POS_FRAMES, targetFrame.toDouble());
        } else {
          print('VideoDecoderService: SeekCommand received, but VideoCapture is not open.');
        }
      } else if (message is StopCommand) {
        print('VideoDecoderService: StopCommand received. Initiating shutdown sequence.');
        isRunning = false;
        if (cap.isOpened) {
            cap.release();
            print('VideoDecoderService: VideoCapture released in StopCommand handler.');
        }
        receivePort.close();
      }
    });
    
    // Decoding loop
    while (isRunning) {
      try {
        if (!cap.isOpened) {
          if (isRunning) {
            print('VideoDecoderService: VideoCapture became closed unexpectedly during loop. Stopping.');
            sendPort.send(DecoderError('VideoCapture closed unexpectedly during decoding.'));
          }
          isRunning = false;
          break; 
        }

        // Decode frames in batches
        final frames = <DecodedFrame>[];
        
        for (int i = 0; i < batchSize && isRunning; i++) {
          final currentFrame = cap.get(cv.CAP_PROP_POS_FRAMES).toInt();
          
          if (currentFrame >= frameCount) {
            // Loop back to beginning
            cap.set(cv.CAP_PROP_POS_FRAMES, 0);
            continue;
          }
          
          final (success, mat) = cap.read();
          if (success && !mat.isEmpty) {
            // Convert to RGBA
            final pic = cv.cvtColor(mat, cv.COLOR_RGB2RGBA);
            
            // Allocate memory and copy data
            final dataSize = pic.total * pic.elemSize;
            final dataPtr = malloc.allocate<Uint8>(dataSize).cast<Uint8>();
            final dataList = dataPtr.asTypedList(dataSize);
            dataList.setAll(0, pic.data);
            
            frames.add(DecodedFrame(
              frameNumber: currentFrame,
              dataPtr: dataPtr,
              dataSize: dataSize,
              width: pic.width,
              height: pic.height,
              timestamp: DateTime.now().microsecondsSinceEpoch,
            ));
            
            mat.dispose();
            pic.dispose();
          }
        }
        
        // Send batch of frames
        if (frames.isNotEmpty) {
          sendPort.send(frames);
        }
        
        // Small delay to prevent overwhelming the main thread
        await Future.delayed(const Duration(microseconds: 100));
        
      } catch (e) {
        sendPort.send(DecoderError('Decoder error: $e'));
      }
    }
    
    // Cleanup
    print('VideoDecoderService: Exited decoding loop.');
    if (cap.isOpened) {
        print('VideoDecoderService: Releasing VideoCapture in final cleanup sequence.');
        cap.release();
    }
    sendPort.send(DecoderStopped());
    print('VideoDecoderService: DecoderStopped sent. Exiting decoderEntryPoint.');
  }
}

// Communication classes
class DecoderParams {
  final String videoPath;
  final SendPort sendPort;
  
  DecoderParams(this.videoPath, this.sendPort);
}

class VideoInfo {
  final int frameCount;
  final double fps;
  final int width;
  final int height;
  
  VideoInfo({
    required this.frameCount,
    required this.fps,
    required this.width,
    required this.height,
  });
}

class SeekCommand {
  final int frame;
  SeekCommand(this.frame);
}

class StopCommand {}

class DecoderError {
  final String message;
  DecoderError(this.message);
}

class DecoderStopped {}
