import 'package:flutter/material.dart';
import 'package:live_object_detection_ssd_mobilenet/models/screen_params.dart';
import 'package:live_object_detection_ssd_mobilenet/service/segmentation_process.dart';

import '../utils/min_area_rectangle.dart';

const int scaleFactor =
    40; // 40 for 160X160 input size, 80 for 320X320 input size, 160 for 640X640 input size

class SegmentationWidget extends StatelessWidget {
  final SegmentationProcess segmentationProcess;
  final int cameraIndex;
  const SegmentationWidget(
      {super.key,
      required this.segmentationProcess,
      required this.cameraIndex});

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
    Rectangle rectangle = minimumAreaRectangle(
        mask, imageWidth / scaleFactor, imageHeight / scaleFactor);
    return Transform.translate(
      offset: Offset(offsetX, offsetY),
      child: CustomPaint(
        painter: _SegmentationMaskPainter(
          mask: mask,
          color: color.withOpacity(0.5),
          width: imageWidth,
          height: imageHeight,
          rectangle: rectangle,
          cameraIndex: cameraIndex,
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
  final Rectangle rectangle;
  final int cameraIndex;

  _SegmentationMaskPainter(
      {required this.mask,
      required this.color,
      required this.width,
      required this.height,
      required this.rectangle,
      required this.cameraIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // for (int y = 0; y < mask.length; y++) {
    //   for (int x = 0; x < mask[y].length; x++) {
    //     if (mask[y][x] > 0.5) {
    //       // Threshold to determine if the pixel is part of the object
    //       canvas.drawRect(
    //         Rect.fromLTWH(x.toDouble() * width / scale_factor, y.toDouble() * height / scale_factor,
    //             width / scale_factor, height / scale_factor),
    //         paint,
    //       );
    //     }
    //   }
    // }
    List<Point> hull = rectangle.corners;
    double rectWidth = rectangle.width;
    double rectHeight = rectangle.height;

    if (isHorizontalOrVerticalRectangle(hull)) {
      List<double> incX = [0, width / scaleFactor, width / scaleFactor, 0];
      List<double> incY = [0, 0, height / scaleFactor, height / scaleFactor];
      hull = hull.asMap().entries.map((entry) {
        int i = entry.key;
        Point point = entry.value;
        return Point(point.x + incX[i], point.y + incY[i]);
      }).toList();
    }
    // print(hull);
    final path = Path()
      ..addPolygon(
          hull.map((point) => Offset(point.x, point.y)).toList(), true);
    canvas.drawPath(path, paint);
    // Draw rectangle width and height on the top right corner
    final textPainter = TextPainter(
      text: TextSpan(
        text:
            'W: ${rectWidth.toStringAsFixed(1)}, H: ${rectHeight.toStringAsFixed(1)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          backgroundColor: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Flip horizontally if cameraIndex == 1
    if (cameraIndex == 1) {
      canvas.save();
      // Flip vertically (mirror)
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
      // Paint text at the top left after flip (so it appears top right visually)
      // Adjust position so text stays within canvas
      textPainter.paint(canvas, Offset(0, size.height - textPainter.height));
      canvas.restore();
    } else {
      textPainter.paint(canvas, const Offset(0, 0));
    }
  }

  @override
  bool shouldRepaint(_SegmentationMaskPainter oldDelegate) => true;
}

Rectangle minimumAreaRectangle(
    List<List<num>> mask, double scaleX, double scaleY) {
  List<List<bool>> binaryMask =
      mask.map((row) => row.map((e) => e > 0.5).toList()).toList();
  return MinimumBoundingRectangle.findMinimumBoundingRectangle(
      binaryMask, scaleX, scaleY);
}

bool isHorizontalOrVerticalRectangle(List<Point> hull) {
  if (hull.length != 4) return false;
  // Calculate the direction of each edge
  List<Offset> edges = [];
  for (int i = 0; i < 4; i++) {
    final p1 = hull[i];
    final p2 = hull[(i + 1) % 4];
    edges.add(Offset(p2.x - p1.x, p2.y - p1.y));
  }
  // Check if all edges are either horizontal or vertical
  bool allHorizontalOrVertical = edges.every((e) =>
      (e.dx.abs() < 1e-3 && e.dy.abs() > 1e-3) ||
      (e.dy.abs() < 1e-3 && e.dx.abs() > 1e-3));
  if (allHorizontalOrVertical) {
    // Rectangle is axis-aligned
    // You can use this info as needed, e.g. print or set a flag
    // print('Rectangle is completely horizontal or vertical');
  }
  return allHorizontalOrVertical;
}
