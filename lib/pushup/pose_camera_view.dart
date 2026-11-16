import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'pushup_counter.dart';

/// Front-camera preview that detects pushups with ML Kit pose detection.
/// Does not play sounds or show the count; the parent does that.
class PushupCameraView extends StatefulWidget {
  const PushupCameraView({
    super.key,
    required this.onRep,
    this.onPhase,
    this.showSkeleton = true,
  });

  /// Called with the new total count each time a rep is completed.
  final ValueChanged<int> onRep;

  /// Called only when the phase changes.
  final ValueChanged<PushupPhase>? onPhase;
  final bool showSkeleton;

  @override
  State<PushupCameraView> createState() => _PushupCameraViewState();
}

class _PushupCameraViewState extends State<PushupCameraView>
    with WidgetsBindingObserver {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _controller;
  CameraDescription? _camera;
  PoseDetector? _detector;
  final PushupCounter _counter = PushupCounter();
  bool _busy = false;
  bool _starting = false;
  bool _disposed = false;
  String? _error;
  bool _permanentlyDenied = false;

  PushupPhase _phase = PushupPhase.noBody;
  Pose? _pose;
  Size? _imageSize; // upright image size of the last processed frame

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable().catchError((_) {});
    _detector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().catchError((_) {});
    final c = _controller;
    _controller = null;
    _stopAndDispose(c);
    _detector?.close().catchError((_) {});
    _detector = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final c = _controller;
      _controller = null;
      if (mounted && c != null) setState(() {});
      _stopAndDispose(c);
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_starting) _init();
    }
  }

  Future<void> _stopAndDispose(CameraController? c) async {
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  Future<void> _init() async {
    if (_starting || _disposed) return;
    _starting = true;
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _fail('Camera access is needed to count your pushups.',
            permanentlyDenied: status.isPermanentlyDenied || status.isRestricted);
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('No camera found on this device.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (_disposed || !mounted) {
        await controller.dispose();
        return;
      }
      _camera = camera;
      _controller = controller;
      await controller.startImageStream(_onImage);
      if (!mounted) return;
      setState(() => _error = null);
    } catch (e) {
      _fail('Could not start the camera ($e).');
    } finally {
      _starting = false;
    }
  }

  void _fail(String message, {bool permanentlyDenied = false}) {
    if (!mounted) return;
    final c = _controller;
    _controller = null;
    _stopAndDispose(c);
    setState(() {
      _error = message;
      _permanentlyDenied = permanentlyDenied;
    });
  }

  InputImage? _toInputImage(CameraImage image, CameraController controller) {
    final camera = _camera;
    if (camera == null) return null;
    final sensor = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else if (Platform.isAndroid) {
      var comp = _orientations[controller.value.deviceOrientation];
      if (comp == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        comp = (sensor + comp) % 360;
      } else {
        comp = (sensor - comp + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(comp);
    }
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    final swap = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    _imageSize = swap
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _onImage(CameraImage image) async {
    if (_busy || _disposed) return;
    final controller = _controller;
    final detector = _detector;
    if (controller == null || detector == null) return;
    _busy = true;
    try {
      final input = _toInputImage(image, controller);
      if (input == null) return;
      final poses = await detector.processImage(input);
      if (!mounted || _disposed) return;
      final pose = poses.isEmpty ? null : poses.first;
      final body = pose == null ? null : _toBodyPose(pose);
      final rep = _counter.update(body);
      final phase = _counter.phase;
      if (rep) widget.onRep(_counter.count);
      if (phase != _phase) {
        _phase = phase;
        widget.onPhase?.call(phase);
      }
      if (widget.showSkeleton) {
        setState(() => _pose = pose);
      } else if (_pose != null) {
        setState(() => _pose = null);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Pose frame failed: $e');
    } finally {
      _busy = false;
    }
  }

  static BodyPose _toBodyPose(Pose p) {
    Pt? g(PoseLandmarkType t) {
      final l = p.landmarks[t];
      return l == null ? null : Pt(l.x, l.y, l.likelihood);
    }

    return BodyPose(
      leftShoulder: g(PoseLandmarkType.leftShoulder),
      rightShoulder: g(PoseLandmarkType.rightShoulder),
      leftElbow: g(PoseLandmarkType.leftElbow),
      rightElbow: g(PoseLandmarkType.rightElbow),
      leftWrist: g(PoseLandmarkType.leftWrist),
      rightWrist: g(PoseLandmarkType.rightWrist),
      leftHip: g(PoseLandmarkType.leftHip),
      rightHip: g(PoseLandmarkType.rightHip),
      leftAnkle: g(PoseLandmarkType.leftAnkle),
      rightAnkle: g(PoseLandmarkType.rightAnkle),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _buildError(context);
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Color(0xFF000000),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // CameraValue.aspectRatio is the sensor's (landscape) ratio; CameraPreview
    // inverts it in portrait, so the box we lay it out in must do the same.
    final ar = c.value.aspectRatio;
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final previewSize = portrait ? Size(1000, ar * 1000) : Size(ar * 1000, 1000);
    final mirror = _camera?.lensDirection == CameraLensDirection.front;
    return ClipRect(
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: previewSize.width,
              height: previewSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(c),
                  if (widget.showSkeleton && _pose != null && _imageSize != null)
                    CustomPaint(
                      painter: _SkeletonPainter(
                        pose: _pose!,
                        imageSize: _imageSize!,
                        mirror: mirror,
                        color: _phase == PushupPhase.notInPosition ||
                                _phase == PushupPhase.noBody
                            ? const Color(0xFFFFB300)
                            : const Color(0xFF43A047),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Color(0xFFFFFFFF), size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (_permanentlyDenied) {
                    await openAppSettings();
                  } else {
                    setState(() => _error = null);
                    _init();
                  }
                },
                child: Text(
                    _permanentlyDenied ? 'Open settings' : 'Grant camera access'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter({
    required this.pose,
    required this.imageSize,
    required this.mirror,
    required this.color,
  });

  final Pose pose;
  final Size imageSize;
  final bool mirror;
  final Color color;

  static const _bones = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  Offset _map(PoseLandmark l, Size size) {
    // Landmarks are in upright, unmirrored image coordinates; the front
    // camera preview is mirrored, so flip x. The painter shares the preview's
    // aspect ratio, so a plain scale is the cover transform.
    final nx = l.x / imageSize.width;
    final ny = l.y / imageSize.height;
    return Offset((mirror ? 1 - nx : nx) * size.width, ny * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = const Color(0xFFFFFFFF);
    for (final b in _bones) {
      final a = pose.landmarks[b[0]], c = pose.landmarks[b[1]];
      if (a == null || c == null) continue;
      if (a.likelihood < 0.3 || c.likelihood < 0.3) continue;
      canvas.drawLine(_map(a, size), _map(c, size), line);
    }
    for (final l in pose.landmarks.entries) {
      final t = l.key;
      if (t.index <= PoseLandmarkType.rightMouth.index) continue; // face
      if (l.value.likelihood < 0.3) continue;
      canvas.drawCircle(_map(l.value, size), 8, dot);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => true;
}
