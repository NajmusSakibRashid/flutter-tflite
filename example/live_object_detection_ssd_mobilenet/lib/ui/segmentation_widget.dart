import 'package:flutter/material.dart';
import 'package:live_object_detection_ssd_mobilenet/models/screen_params.dart';
import 'package:live_object_detection_ssd_mobilenet/service/segmentation_process.dart';

class SegmentationWidget extends StatelessWidget {
  final SegmentationProcess segmentationProcess;
  const SegmentationWidget({super.key, required this.segmentationProcess});

  @override
  Widget build(BuildContext context) {
    Color color = Colors.primaries[
        (segmentationProcess.recognition.label.length +
                segmentationProcess.recognition.label.codeUnitAt(0) +
                segmentationProcess.recognition.id) %
            Colors.primaries.length];
    List<List<num>> mask = segmentationProcess.processedMask;
    print('Mask size: ${mask.length}x${mask[0].length}');
    final imageWidth = ScreenParams.screenPreviewSize.width;
    final imageHeight = ScreenParams.screenPreviewSize.height;
    final offsetX = segmentationProcess.recognition.location.left * imageWidth;
    final offsetY = segmentationProcess.recognition.location.top * imageHeight;
    return Transform.translate(
      offset: Offset(offsetX, offsetY),
      child: CustomPaint(
        painter: _SegmentationMaskPainter(
            mask: mask,
            color: color.withOpacity(0.5),
            width: imageWidth,
            height: imageHeight),
        child: Container(),
      ),
    );
  }
}

class _SegmentationMaskPainter extends CustomPainter {
  final List<List<num>> mask;
  final Color color;
  final double width;
  final double height;

  _SegmentationMaskPainter(
      {required this.mask,
      required this.color,
      required this.width,
      required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (int y = 0; y < mask.length; y++) {
      for (int x = 0; x < mask[y].length; x++) {
        if (mask[y][x] > 0.5) {
          // Threshold to determine if the pixel is part of the object
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble() * width / 40, y.toDouble() * height / 40,
                width / 40, height / 40),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SegmentationMaskPainter oldDelegate) => true;
}
