import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:live_object_detection_ssd_mobilenet/models/recognition.dart';
import 'package:live_object_detection_ssd_mobilenet/models/screen_params.dart';
import 'package:live_object_detection_ssd_mobilenet/service/detector_service.dart';
import 'package:live_object_detection_ssd_mobilenet/service/segmentation_process.dart';
import 'package:live_object_detection_ssd_mobilenet/ui/box_widget.dart';
import 'package:live_object_detection_ssd_mobilenet/ui/segmentation_widget.dart';
import 'package:live_object_detection_ssd_mobilenet/ui/stats_widget.dart';

/// [DetectorWidget] sends each frame for inference
class DetectorWidget extends StatefulWidget {
  /// Constructor
  const DetectorWidget({super.key});

  @override
  State<DetectorWidget> createState() => _DetectorWidgetState();
}

class _DetectorWidgetState extends State<DetectorWidget>
    with WidgetsBindingObserver {
  /// List of available cameras
  late List<CameraDescription> cameras;

  /// Controller
  CameraController? _cameraController;

  // use only when initialized, so - not null
  get _controller => _cameraController;

  /// Object Detector is running on a background [Isolate]. This is nullable
  /// because acquiring a [Detector] is an asynchronous operation. This
  /// value is `null` until the detector is initialized.
  Detector? _detector;
  StreamSubscription? _subscription;

  /// Results to draw bounding boxes
  List<Recognition>? results;

  /// Segmentation processes to draw segmentation masks
  List<SegmentationProcess>? segmentationProcesses;

  /// Realtime stats
  Map<String, String>? stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initStateAsync();
  }

  void _initStateAsync() async {
    // initialize preview and CameraImage stream
    _initializeCamera();
    // Spawn a new isolate
    Detector.start().then((instance) {
      setState(() {
        _detector = instance;
        _subscription = instance.resultsStream.stream.listen((values) {
          setState(() {
            segmentationProcesses = values['segmentation processes'];
            results = values['recognitions'];
            stats = values['stats'];
          });
        });
      });
    });
  }

  /// Initializes the camera by setting [_cameraController]
  void _initializeCamera() async {
    cameras = await availableCameras();
    // cameras[0] for back-camera
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    )..initialize().then((_) async {
        await _controller.startImageStream(onLatestImageAvailable);
        setState(() {});

        /// previewSize is size of each image frame captured by controller
        ///
        /// 352x288 on iOS, 240p (320x240) on Android with ResolutionPreset.low
        ScreenParams.previewSize = _controller.value.previewSize!;
      });
  }

  void switchCamera() async {
    // Switch to the next camera
    final nextCameraIndex =
        (cameras.indexOf(_controller.description) + 1) % cameras.length;
    final nextCamera = cameras[nextCameraIndex];

    // Stop the current controller
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    // Create a new controller with the next camera
    _cameraController = CameraController(
      nextCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    // ScreenParams.previewSize = _controller.value.previewSize!;

    // Initialize the new controller
    await _cameraController!.initialize();
    await _cameraController!.startImageStream(onLatestImageAvailable);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Return empty container while the camera is not initialized
    if (_cameraController == null || !_controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    var aspect = 1 / _controller.value.aspectRatio;

    var cameraIndex = cameras.indexOf(_controller.description);

    return Stack(
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: aspect,
              child: CameraPreview(_controller),
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                onPressed: switchCamera,
                child: const Icon(Icons.switch_camera),
              ),
            ),
          ],
        ),
        // Stats
        _statsWidget(),
        // Bounding boxes
        AspectRatio(
          aspectRatio: aspect,
          child: _boundingBoxes(cameraIndex),
        ),
        AspectRatio(
            aspectRatio: aspect, child: _segmentationMasks(cameraIndex)),
      ],
    );
  }

  Widget _statsWidget() => (stats != null)
      ? Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            color: Colors.white.withAlpha(150),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: stats!.entries
                    .map((e) => StatsWidget(e.key, e.value))
                    .toList(),
              ),
            ),
          ),
        )
      : const SizedBox.shrink();

  /// Returns Stack of bounding boxes
  Widget _boundingBoxes(int cameraIndex) {
    if (results == null) {
      return const SizedBox.shrink();
    }
    // Flip horizontally if using the front camera (cameraIndex == 1)
    return Transform(
      alignment: Alignment.center,
      transform: cameraIndex == 1
          ? (Matrix4.identity()..scale(1.0, -1.0, 1.0))
          : Matrix4.identity(),
      child: Stack(
        children: results!.map((box) => BoxWidget(result: box)).toList(),
      ),
    );
  }

  Widget _segmentationMasks(int cameraIndex) {
    if (segmentationProcesses == null) {
      return const SizedBox.shrink();
    }
    // Flip horizontally if using the front camera (cameraIndex == 1)
    return Transform(
      alignment: Alignment.center,
      transform: cameraIndex == 1
          ? (Matrix4.identity()..scale(1.0, -1.0, 1.0))
          : Matrix4.identity(),
      child: Stack(
        children: segmentationProcesses!
            .map((process) => SegmentationWidget(segmentationProcess: process))
            .toList(),
      ),
    );
  }

  /// Callback to receive each frame [CameraImage] perform inference on it
  void onLatestImageAvailable(CameraImage cameraImage) async {
    _detector?.processFrame(cameraImage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
        _cameraController?.stopImageStream();
        _detector?.stop();
        _subscription?.cancel();
        break;
      case AppLifecycleState.resumed:
        _initStateAsync();
        break;
      default:
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _detector?.stop();
    _subscription?.cancel();
    super.dispose();
  }
}
