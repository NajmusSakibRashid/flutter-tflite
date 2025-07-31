// Copyright 2023 The Flutter team. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:live_object_detection_ssd_mobilenet/models/recognition.dart';
import 'package:live_object_detection_ssd_mobilenet/service/segmentation_process.dart';
import 'package:live_object_detection_ssd_mobilenet/utils/image_utils.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

///////////////////////////////////////////////////////////////////////////////
// **WARNING:** This is not production code and is only intended to be used for
// demonstration purposes.
//
// The following Detector example works by spawning a background isolate and
// communicating with it over Dart's SendPort API. It is presented below as a
// demonstration of the feature "Background Isolate Channels" and shows using
// plugins from a background isolate. The [Detector] operates on the root
// isolate and the [_DetectorServer] operates on a background isolate.
//
// Here is an example of the protocol they use to communicate:
//
//  _________________                         ________________________
//  [:Detector]                               [:_DetectorServer]
//  -----------------                         ------------------------
//         |                                              |
//         |<---------------(init)------------------------|
//         |----------------(init)----------------------->|
//         |<---------------(ready)---------------------->|
//         |                                              |
//         |----------------(detect)--------------------->|
//         |<---------------(busy)------------------------|
//         |<---------------(result)----------------------|
//         |                 . . .                        |
//         |----------------(detect)--------------------->|
//         |<---------------(busy)------------------------|
//         |<---------------(result)----------------------|
//
///////////////////////////////////////////////////////////////////////////////

/// All the command codes that can be sent and received between [Detector] and
/// [_DetectorServer].
enum _Codes {
  init,
  busy,
  ready,
  detect,
  result,
}

/// A command sent between [Detector] and [_DetectorServer].
class _Command {
  const _Command(this.code, {this.args});

  final _Codes code;
  final List<Object>? args;
}

/// A Simple Detector that handles object detection via Service
///
/// All the heavy operations like pre-processing, detection, ets,
/// are executed in a background isolate.
/// This class just sends and receives messages to the isolate.
class Detector {
  static const String _modelPath =
      'assets/models/100n_float16_160.tflite'; //change model path here 160X160
  static const String _labelPath = 'assets/models/__labelmap.txt';

  Detector._(this._isolate, this._interpreter, this._labels);

  final Isolate _isolate;
  late final Interpreter _interpreter;
  late final List<String> _labels;

  // To be used by detector (from UI) to send message to our Service ReceivePort
  late final SendPort _sendPort;

  bool _isReady = false;

  // // Similarly, StreamControllers are stored in a queue so they can be handled
  // // asynchronously and serially.
  final StreamController<Map<String, dynamic>> resultsStream =
      StreamController<Map<String, dynamic>>();

  /// Open the database at [path] and launch the server on a background isolate..
  static Future<Detector> start() async {
    final ReceivePort receivePort = ReceivePort();
    // sendPort - To be used by service Isolate to send message to our ReceiverPort
    final Isolate isolate =
        await Isolate.spawn(_DetectorServer._run, receivePort.sendPort);

    final Detector result = Detector._(
      isolate,
      await _loadModel(),
      await _loadLabels(),
    );
    receivePort.listen((message) {
      result._handleCommand(message as _Command);
    });
    return result;
  }

  static Future<Interpreter> _loadModel() async {
    final interpreterOptions = InterpreterOptions();

    // Use XNNPACK Delegate
    if (Platform.isAndroid) {
      interpreterOptions.addDelegate(XNNPackDelegate());
    }

    Interpreter ret;

    try {
      ret = await Interpreter.fromAsset(
        _modelPath,
        options: interpreterOptions..threads = 1,
      );
      // debugPrint('Model loaded successfully');
      // print('Model input size: ${ret.getInputTensor(0).shape}');
      // print('Model output size: ${ret.getOutputTensor(0).shape}');

      return ret;
    } on Exception catch (e) {
      throw Exception('Failed to load model: $e');
    }
  }

  static Future<List<String>> _loadLabels() async {
    return (await rootBundle.loadString(_labelPath)).split('\n');
  }

  /// Starts CameraImage processing
  void processFrame(CameraImage cameraImage) {
    if (_isReady) {
      _sendPort.send(_Command(_Codes.detect, args: [cameraImage]));
    }
  }

  /// Handler invoked when a message is received from the port communicating
  /// with the database server.
  void _handleCommand(_Command command) {
    switch (command.code) {
      case _Codes.init:
        _sendPort = command.args?[0] as SendPort;
        // ----------------------------------------------------------------------
        // Before using platform channels and plugins from background isolates we
        // need to register it with its root isolate. This is achieved by
        // acquiring a [RootIsolateToken] which the background isolate uses to
        // invoke [BackgroundIsolateBinaryMessenger.ensureInitialized].
        // ----------------------------------------------------------------------
        RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;
        _sendPort.send(_Command(_Codes.init, args: [
          rootIsolateToken,
          _interpreter.address,
          _labels,
        ]));
      case _Codes.ready:
        _isReady = true;
      case _Codes.busy:
        _isReady = false;
      case _Codes.result:
        _isReady = true;
        resultsStream.add(command.args?[0] as Map<String, dynamic>);
      default:
        debugPrint('Detector unrecognized command: ${command.code}');
    }
  }

  /// Kills the background isolate and its detector server.
  void stop() {
    _isolate.kill();
  }
}

/// The portion of the [Detector] that runs on the background isolate.
///
/// This is where we use the new feature Background Isolate Channels, which
/// allows us to use plugins from background isolates.
class _DetectorServer {
  /// Input size of image (height = width = 160)
  static const int mlModelInputSize =
      160; // change it to 320 or 640 for larger models

  /// Result confidence threshold
  static const double confidence = 0.5;
  Interpreter? _interpreter;
  List<String>? _labels;

  _DetectorServer(this._sendPort);

  final SendPort _sendPort;

  // ----------------------------------------------------------------------
  // Here the plugin is used from the background isolate.
  // ----------------------------------------------------------------------

  /// The main entrypoint for the background isolate sent to [Isolate.spawn].
  static void _run(SendPort sendPort) {
    ReceivePort receivePort = ReceivePort();
    final _DetectorServer server = _DetectorServer(sendPort);
    receivePort.listen((message) async {
      final _Command command = message as _Command;
      await server._handleCommand(command);
    });
    // receivePort.sendPort - used by UI isolate to send commands to the service receiverPort
    sendPort.send(_Command(_Codes.init, args: [receivePort.sendPort]));
  }

  /// Handle the [command] received from the [ReceivePort].
  Future<void> _handleCommand(_Command command) async {
    switch (command.code) {
      case _Codes.init:
        // ----------------------------------------------------------------------
        // The [RootIsolateToken] is required for
        // [BackgroundIsolateBinaryMessenger.ensureInitialized] and must be
        // obtained on the root isolate and passed into the background isolate via
        // a [SendPort].
        // ----------------------------------------------------------------------
        RootIsolateToken rootIsolateToken =
            command.args?[0] as RootIsolateToken;
        // ----------------------------------------------------------------------
        // [BackgroundIsolateBinaryMessenger.ensureInitialized] for each
        // background isolate that will use plugins. This sets up the
        // [BinaryMessenger] that the Platform Channels will communicate with on
        // the background isolate.
        // ----------------------------------------------------------------------
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
        _interpreter = Interpreter.fromAddress(command.args?[1] as int);
        _labels = command.args?[2] as List<String>;
        _sendPort.send(const _Command(_Codes.ready));
      case _Codes.detect:
        _sendPort.send(const _Command(_Codes.busy));
        _convertCameraImage(command.args?[0] as CameraImage);
      default:
        debugPrint('_DetectorService unrecognized command ${command.code}');
    }
  }

  void _convertCameraImage(CameraImage cameraImage) {
    var preConversionTime = DateTime.now().millisecondsSinceEpoch;

    convertCameraImageToImage(cameraImage).then((image) {
      if (image != null) {
        if (Platform.isAndroid) {
          image = image_lib.copyRotate(image, angle: 90);
        }

        final results = analyseImage(image, preConversionTime);
        _sendPort.send(_Command(_Codes.result, args: [results]));
      }
    });
  }

  Map<String, dynamic> analyseImage(
      image_lib.Image? image, int preConversionTime) {
    var conversionElapsedTime =
        DateTime.now().millisecondsSinceEpoch - preConversionTime;

    var preProcessStart = DateTime.now().millisecondsSinceEpoch;

    /// Pre-process the image
    /// Resizing image for model [300, 300]
    final imageInput = image_lib.copyResize(
      image!,
      width: mlModelInputSize,
      height: mlModelInputSize,
    );

    // Creating matrix representation, [300, 300, 3]
    final imageMatrix = List.generate(
      imageInput.height,
      (y) => List.generate(
        imageInput.width,
        (x) {
          final pixel = imageInput.getPixel(x, y);
          return [
            pixel.r.toDouble() / 255,
            pixel.g.toDouble() / 255,
            pixel.b.toDouble() / 255
          ];
        },
      ),
    );

    var preProcessElapsedTime =
        DateTime.now().millisecondsSinceEpoch - preProcessStart;

    var inferenceTimeStart = DateTime.now().millisecondsSinceEpoch;

    final output = _runInference(imageMatrix);

    var inferenceElapsedTime =
        DateTime.now().millisecondsSinceEpoch - inferenceTimeStart;

    // Boxes
    final boxesRaw = output.elementAt(0).first as List<List<double>>;
    final x = boxesRaw[0];
    final y = boxesRaw[1];
    final width = boxesRaw[2];
    final height = boxesRaw[3];
    final confidences = boxesRaw[4];

    // print('BoxesRaw Shape: ${boxesRaw.length} X ${boxesRaw[0].length}');

    final List<Rect> locations = List.generate(
      x.length,
      (i) => Rect.fromLTWH(
          x[i] - width[i] / 2, y[i] - height[i] / 2, width[i], height[i]),
    );

    // Number of detections
    final numberOfDetections = x.length;

    final List<String> classification = [];
    for (var i = 0; i < numberOfDetections; i++) {
      classification.add(_labels![0]);
    }

    /// Generate recognitions
    List<Recognition> recognitions = [];
    for (int i = 0; i < numberOfDetections; i++) {
      // Prediction score
      var score = confidences[i];
      // Label string
      var label = classification[i];

      if (score > confidence) {
        recognitions.add(
          Recognition(i, label, score, locations[i]),
        );
      }
    }

    recognitions.sort((a, b) => b.score.compareTo(a.score));

    // Apply IOU threshold to filter overlapping recognitions
    const double iouThreshold = 0.5;
    List<Recognition> filteredRecognitions = [];

    for (var rec in recognitions) {
      bool shouldAdd = true;
      for (var filtered in filteredRecognitions) {
        final iou = _iou(rec.location, filtered.location);
        if (iou > iouThreshold) {
          shouldAdd = false;
          break;
        }
      }
      if (shouldAdd) {
        filteredRecognitions.add(rec);
      }
    }
    recognitions = filteredRecognitions;

    // Segmentation mask
    final rawMask = output.elementAt(1).first as List<List<List<num>>>;

    // print(
    //     'RawMask Shape: ${rawMask.length} X ${rawMask[0].length} X ${rawMask[0][0].length}');

    List<SegmentationProcess> segmentationProcesses = [];
    for (var rec in recognitions) {
      // Coefficients for segmentation mask
      final coEfficients = List<double>.generate(
        32,
        (index) => boxesRaw[5 + index][rec.id],
      );

      segmentationProcesses.add(
        SegmentationProcess(
          rawMask: rawMask,
          coEfficients: coEfficients,
          recognition: rec,
        ),
      );
    }

    var totalElapsedTime =
        DateTime.now().millisecondsSinceEpoch - preConversionTime;

    return {
      "segmentation processes": segmentationProcesses,
      "recognitions": recognitions,
      "stats": <String, String>{
        'Conversion time:': conversionElapsedTime.toString(),
        'Pre-processing time:': preProcessElapsedTime.toString(),
        'Inference time:': inferenceElapsedTime.toString(),
        'Total prediction time:': totalElapsedTime.toString(),
        'Frame': '${image.width} X ${image.height}',
      },
    };
  }

  /// Object detection main function
  List<List<Object>> _runInference(
    List<List<List<num>>> imageMatrix,
  ) {
    final input = [imageMatrix];

    /**Uncomment for input size [1, 160, 160, 3] */
    final output = {
      0: [List<List<num>>.filled(37, List<num>.filled(525, 0))],
      1: [
        List<List<List<num>>>.filled(
            40, List<List<num>>.filled(40, List<num>.filled(32, 0)))
      ],
    };

    /**Uncomment for input size [1, 320, 320, 3] */
    // final output = {
    //   0: [List<List<num>>.filled(37, List<num>.filled(2100, 0))],
    //   1: [
    //     List<List<List<num>>>.filled(
    //         80, List<List<num>>.filled(80, List<num>.filled(32, 0)))
    //   ],
    // };

    /**Uncomment for input size [1, 640, 640, 3] */
    // final output = {
    //   0: [List<List<num>>.filled(37, List<num>.filled(8400, 0))],
    //   1: [
    //     List<List<List<num>>>.filled(
    //         160, List<List<num>>.filled(160, List<num>.filled(32, 0)))
    //   ],
    // };

    _interpreter!.runForMultipleInputs([input], output);
    return output.values.toList();
  }

  double area(Rect rect) {
    return rect.width * rect.height;
  }

  double _iou(Rect location, Rect location2) {
    final intersection = location.intersect(location2);
    if (area(intersection) < 1e-6) return 0;

    final union = area(location) + area(location2) - area(intersection);
    return area(intersection) / union;
  }
}
