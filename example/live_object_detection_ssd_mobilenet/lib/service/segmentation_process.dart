import 'dart:math';

import 'package:live_object_detection_ssd_mobilenet/models/recognition.dart';

class SegmentationProcess {
  List<List<List<num>>> rawMask; // 160 160 32
  List<double> coEfficients; // 32
  Recognition recognition;

  SegmentationProcess({
    required this.rawMask,
    required this.coEfficients,
    required this.recognition,
  });

  num sigmoid(num x) {
    return 1 / (1 + exp(-x));
  }

  List<List<num>> get processedMask {
    List<List<num>> mask = [];
    for (var y = 0; y < rawMask.length; y++) {
      List<num> row = [];
      for (var x = 0; x < rawMask[y].length; x++) {
        // Apply coefficients to each pixel value
        double value = 0;
        for (var i = 0; i < coEfficients.length; i++) {
          value += rawMask[y][x][i] * coEfficients[i];
        }
        row.add(value);
      }
      mask.add(row);
    }
    var xMin = recognition.location.left * 40;
    var xMax = recognition.location.right * 40;
    var yMin = recognition.location.top * 40;
    var yMax = recognition.location.bottom * 40;
    // Crop the mask to the bounding box of the recognition
    mask = mask.sublist(yMin.toInt(), yMax.toInt()).map((row) {
      return row.sublist(xMin.toInt(), xMax.toInt());
    }).toList();

    // Apply sigmoid to the mask values
    for (var y = 0; y < mask.length; y++) {
      for (var x = 0; x < mask[y].length; x++) {
        mask[y][x] = sigmoid(mask[y][x]);
      }
    }

    return mask;
  }
}
