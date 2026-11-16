import 'dart:math' as math;

/// A 2D image-space point (y grows downward) with a detection likelihood.
class Pt {
  const Pt(this.x, this.y, [this.likelihood = 1]);
  final double x, y, likelihood;
}

/// Landmarks in upright image coordinates. Any field may be null.
class BodyPose {
  const BodyPose({
    this.leftShoulder,
    this.rightShoulder,
    this.leftElbow,
    this.rightElbow,
    this.leftWrist,
    this.rightWrist,
    this.leftHip,
    this.rightHip,
    this.leftAnkle,
    this.rightAnkle,
  });

  final Pt? leftShoulder,
      rightShoulder,
      leftElbow,
      rightElbow,
      leftWrist,
      rightWrist,
      leftHip,
      rightHip,
      leftAnkle,
      rightAnkle;
}

enum PushupPhase { noBody, notInPosition, up, down }

class PushupCounter {
  PushupCounter({
    this.downAngle = 95,
    this.upAngle = 150,
    this.minLikelihood = 0.5,
    this.smoothing = 0.5,
    this.minRepDuration = const Duration(milliseconds: 400),
    this.dropoutTolerance = const Duration(milliseconds: 500),
    this.minTorsoInclinationDeg = 40,
    this.maxFrontalTorsoRatio = 1.2,
  });

  /// Elbow angle (deg) below which the user counts as "down".
  final double downAngle;

  /// Elbow angle (deg) above which the user counts as back "up".
  final double upAngle;

  /// Landmarks below this likelihood are ignored.
  final double minLikelihood;

  /// EMA alpha for the elbow angle (1 = no smoothing).
  final double smoothing;

  /// Minimum time between two counted reps (jitter rejection).
  final Duration minRepDuration;

  /// Landmark dropouts shorter than this keep the current state.
  final Duration dropoutTolerance;

  /// Side view: torso must be tilted at least this many degrees from vertical.
  final double minTorsoInclinationDeg;

  /// Frontal view: shoulder->hip vertical distance must be below this
  /// multiple of the shoulder width (standing gives roughly 1.5-2.5).
  final double maxFrontalTorsoRatio;

  int _count = 0;
  PushupPhase _phase = PushupPhase.noBody;
  double? _angle;
  bool _down = false;
  DateTime? _lastValid;
  DateTime? _lastRep;

  int get count => _count;
  PushupPhase get phase => _phase;

  /// Smoothed elbow angle in degrees, or null when unknown.
  double? get elbowAngle => _angle;

  void reset() {
    _count = 0;
    _phase = PushupPhase.noBody;
    _angle = null;
    _down = false;
    _lastValid = null;
    _lastRep = null;
  }

  bool _ok(Pt? p) => p != null && p.likelihood >= minLikelihood;

  static double _minL(List<Pt?> ps) =>
      ps.map((p) => p?.likelihood ?? 0).reduce(math.min);

  static double _angleAt(Pt a, Pt b, Pt c) {
    final v1x = a.x - b.x, v1y = a.y - b.y;
    final v2x = c.x - b.x, v2y = c.y - b.y;
    final n = math.sqrt(v1x * v1x + v1y * v1y) * math.sqrt(v2x * v2x + v2y * v2y);
    if (n < 1e-9) return 180;
    final cosv = ((v1x * v2x + v1y * v2y) / n).clamp(-1.0, 1.0);
    return math.acos(cosv) * 180 / math.pi;
  }

  double? _rawElbowAngle(BodyPose p) {
    final arms = <({double q, double a, Pt s, Pt w})>[];
    void add(Pt? s, Pt? e, Pt? w) {
      if (_ok(s) && _ok(e) && _ok(w)) {
        arms.add((q: _minL([s, e, w]), a: _angleAt(s!, e!, w!), s: s, w: w));
      }
    }

    add(p.leftShoulder, p.leftElbow, p.leftWrist);
    add(p.rightShoulder, p.rightElbow, p.rightWrist);
    if (arms.isEmpty) return null;
    if (arms.length == 2) return (arms[0].a + arms[1].a) / 2;
    return arms.first.a;
  }

  bool _inPosition(BodyPose p) {
    final shoulders = [p.leftShoulder, p.rightShoulder].where(_ok).cast<Pt>().toList();
    final hips = [p.leftHip, p.rightHip].where(_ok).cast<Pt>().toList();
    final wrists = [p.leftWrist, p.rightWrist].where(_ok).cast<Pt>().toList();
    if (shoulders.isEmpty) return false;
    final sx = shoulders.map((e) => e.x).reduce((a, b) => a + b) / shoulders.length;
    final sy = shoulders.map((e) => e.y).reduce((a, b) => a + b) / shoulders.length;

    double? torsoDx, torsoDy;
    if (hips.isNotEmpty) {
      final hx = hips.map((e) => e.x).reduce((a, b) => a + b) / hips.length;
      final hy = hips.map((e) => e.y).reduce((a, b) => a + b) / hips.length;
      torsoDx = hx - sx;
      torsoDy = hy - sy;
      // Side/plank view: torso closer to horizontal than vertical.
      final incl = math.atan2(torsoDx.abs(), torsoDy.abs()) * 180 / math.pi;
      if (incl > minTorsoInclinationDeg) return true;
    }

    // Frontal view (phone on the floor in front of the user): wrists below
    // shoulders and torso foreshortened (or hips out of frame).
    final wristsBelow = wrists.isNotEmpty && wrists.every((w) => w.y > sy);
    if (!wristsBelow) return false;
    if (torsoDy == null) return true;
    final double width;
    if (shoulders.length == 2) {
      width = (shoulders[0].x - shoulders[1].x).abs();
    } else {
      return false; // cannot judge foreshortening with one shoulder
    }
    if (width < 1e-6) return false;
    return torsoDy.abs() < maxFrontalTorsoRatio * width;
  }

  void _setNoBody(DateTime now) {
    _phase = PushupPhase.noBody;
    _down = false;
    _angle = null;
  }

  /// Feed one frame. Returns true iff this frame completed a rep.
  bool update(BodyPose? pose, {DateTime? now}) {
    now ??= DateTime.now();
    final raw = pose == null ? null : _rawElbowAngle(pose);
    if (pose == null || raw == null) {
      final last = _lastValid;
      if (last != null && now.difference(last) < dropoutTolerance) {
        return false; // brief dropout: keep state
      }
      _setNoBody(now);
      return false;
    }
    _lastValid = now;

    if (!_inPosition(pose)) {
      _phase = PushupPhase.notInPosition;
      _down = false;
      _angle = raw;
      return false;
    }

    _angle = _angle == null ? raw : _angle! + smoothing * (raw - _angle!);
    final a = _angle!;
    var rep = false;
    if (a < downAngle) {
      _down = true;
    } else if (a > upAngle && _down) {
      _down = false;
      final lr = _lastRep;
      if (lr == null || now.difference(lr) >= minRepDuration) {
        _count++;
        _lastRep = now;
        rep = true;
      }
    }
    _phase = _down ? PushupPhase.down : PushupPhase.up;
    return rep;
  }
}
