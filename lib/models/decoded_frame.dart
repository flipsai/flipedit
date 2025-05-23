import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

class DecodedFrame {
  final int frameNumber;
  final Pointer<Uint8> dataPtr;
  final int dataSize;
  final int width;
  final int height;
  final int timestamp;

  DecodedFrame({
    required this.frameNumber,
    required this.dataPtr,
    required this.dataSize,
    required this.width,
    required this.height,
    required this.timestamp,
  });

  Uint8List get data => dataPtr.asTypedList(dataSize);

  void dispose() {
    malloc.free(dataPtr);
  }
}
