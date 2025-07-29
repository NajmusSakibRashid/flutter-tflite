import 'package:flutter/material.dart';
import 'package:live_object_detection_ssd_mobilenet/models/screen_params.dart';
import 'package:live_object_detection_ssd_mobilenet/service/segmentation_process.dart';

class SegmentationWidget extends StatelessWidget {
  final SegmentationProcess segmentationProcess;
  const SegmentationWidget({super.key, required this.segmentationProcess});

  @override
  Widget build(BuildContext context) {
    // Color color = Colors.primaries[
    //     (segmentationProcess.recognition.label.length +
    //             segmentationProcess.recognition.label.codeUnitAt(0) +
    //             segmentationProcess.recognition.id) %
    //         Colors.primaries.length];
    Color color = Colors.primaries[0];
    List<List<num>> mask = segmentationProcess.processedMask;
    final imageWidth = ScreenParams.screenPreviewSize.width;
    final imageHeight = ScreenParams.screenPreviewSize.height;
    final offsetX = segmentationProcess.recognition.location.left * imageWidth;
    final offsetY = segmentationProcess.recognition.location.top * imageHeight;
    // final boxWidth =
    //     segmentationProcess.recognition.location.width * imageWidth;
    // final boxHeight =
    //     segmentationProcess.recognition.location.height * imageHeight;
    var x = getX(mask);
    final area = getArea(mask);
    var y = getY(area, mask[0].length, mask.length, x);

    if (area > .9 * mask.length * mask[0].length) {
      x = 0;
      y = mask.length.toDouble();
    }

    return Transform.translate(
      offset: Offset(offsetX, offsetY),
      child: CustomPaint(
        painter: _SegmentationMaskPainter(
          mask: mask,
          color: color.withOpacity(0.5),
          width: imageWidth,
          height: imageHeight,
          x: x.toDouble() * imageWidth / 40,
          y: y.toDouble() * imageHeight / 40,
        ),
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
  final double x;
  final double y;

  _SegmentationMaskPainter(
      {required this.mask,
      required this.color,
      required this.width,
      required this.height,
      required this.x,
      required this.y});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final a = mask[0].length * width / 40;
    final b = mask.length * height / 40;
    if (x < 0 || y < 0 || x > a || y > b) {
      var tmp = Paint()..color = Colors.black;
      for (int y = 0; y < mask.length; y++) {
        for (int x = 0; x < mask[y].length; x++) {
          if (mask[y][x] > 0.5) {
            // Threshold to determine if the pixel is part of the object
            canvas.drawRect(
              Rect.fromLTWH(x.toDouble() * width / 40,
                  y.toDouble() * height / 40, width / 40, height / 40),
              tmp,
            );
            tmp = paint;
          }
        }
      }
    } else {
      final path = Path()
        ..addPolygon([
          Offset(x, 0),
          Offset(0, y),
          Offset(a - x, b),
          Offset(a, b - y),
        ], true);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SegmentationMaskPainter oldDelegate) => true;
}

int getX(List<List<num>> mask) {
  for (int x = 0; x < mask.length; x++) {
    for (int y = 0; y < mask[x].length; y++) {
      if (mask[x][y] > 0.5) {
        return y;
      }
    }
  }
  return -1; // Return -1 if no object is found
}

int getArea(List<List<num>> mask) {
  int area = 0;
  for (int y = 0; y < mask.length; y++) {
    for (int x = 0; x < mask[y].length; x++) {
      if (mask[y][x] > 0.5) {
        area++;
      }
    }
  }
  return area;
}

double getY(int area, int a, int b, int x) {
  return (area - b * x).toDouble() / (a - 2 * x).toDouble();
}
