import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:morning_glory/pushup/pushup_counter.dart';

/// Elbow at angle [deg] (180 = straight arm) for a shoulder at [s].
BodyPose _pose(double deg, {bool standing = false, bool frontal = false, bool noHips = false}) {
  final r = deg * math.pi / 180;
  Pt arm(Pt s, double dx) {
    final e = Pt(s.x + dx, s.y + 50);
    return Pt(e.x + 50 * math.sin(r), e.y - 50 * math.cos(r));
  }

  if (frontal) {
    const ls = Pt(100, 100), rs = Pt(220, 100);
    const le = Pt(100, 150), re = Pt(220, 150);
    final lw = Pt(100 + 50 * math.sin(r), 150 - 50 * math.cos(r));
    final rw = Pt(220 - 50 * math.sin(r), 150 - 50 * math.cos(r));
    return BodyPose(
      leftShoulder: ls, rightShoulder: rs, leftElbow: le, rightElbow: re,
      leftWrist: lw, rightWrist: rw,
      leftHip: noHips ? null : const Pt(110, 130),
      rightHip: noHips ? null : const Pt(210, 130),
    );
  }
  const s = Pt(100, 100);
  final e = const Pt(100, 150);
  final w = arm(s, 0);
  final hip = standing ? const Pt(105, 300) : const Pt(250, 110);
  return BodyPose(
    leftShoulder: s, rightShoulder: s, leftElbow: e, rightElbow: e,
    leftWrist: w, rightWrist: w, leftHip: hip, rightHip: hip,
  );
}

void main() {
  final t0 = DateTime(2024, 1, 1);
  DateTime t(int ms) => t0.add(Duration(milliseconds: ms));

  /// Runs [reps] full cycles, 100 ms per frame; returns the counter.
  int run(PushupCounter c, List<double> angles, BodyPose Function(double) f) {
    var ms = 0;
    for (final a in angles) {
      c.update(f(a), now: t(ms));
      ms += 100;
    }
    return c.count;
  }

  List<double> cycles(int n, {double low = 40}) => [
        for (var i = 0; i < n; i++) ...[170, 170, 110, low, low, 110, 170, 170, 170],
      ];

  test('counts N reps', () {
    final c = PushupCounter();
    expect(run(c, cycles(5), (a) => _pose(a)), 5);
  });

  test('update returns true on completing frame', () {
    final c = PushupCounter();
    var hits = 0;
    var ms = 0;
    for (final a in cycles(2)) {
      if (c.update(_pose(a), now: t(ms))) hits++;
      ms += 100;
    }
    expect(hits, 2);
  });

  test('standing while bending elbows does not count', () {
    final c = PushupCounter();
    expect(run(c, cycles(4), (a) => _pose(a, standing: true)), 0);
    expect(c.phase, PushupPhase.notInPosition);
  });

  test('partial reps do not count', () {
    final c = PushupCounter();
    expect(run(c, cycles(4, low: 125), (a) => _pose(a)), 0);
  });

  test('jitter around threshold does not double count', () {
    final c = PushupCounter();
    final seq = <double>[170, 170, 50, 50, 50, 170, 170, 120, 170, 120, 170, 130, 170, 170];
    expect(run(c, seq, (a) => _pose(a)), 1);
  });

  test('frontal view counts, standing frontal does not', () {
    final c = PushupCounter();
    expect(run(c, cycles(3), (a) => _pose(a, frontal: true)), 3);
    final c2 = PushupCounter();
    expect(run(c2, cycles(3), (a) => _pose(a, frontal: true, noHips: true)), 3);
  });

  test('brief dropout while down keeps the rep', () {
    final c = PushupCounter();
    var ms = 0;
    for (final a in [170, 140, 110, 40, 40]) {
      c.update(_pose(a.toDouble()), now: t(ms));
      ms += 100;
    }
    expect(c.phase, PushupPhase.down);
    c.update(null, now: t(ms));
    ms += 100;
    c.update(null, now: t(ms));
    ms += 100;
    expect(c.phase, PushupPhase.down);
    for (final a in [170, 170, 170]) {
      c.update(_pose(a.toDouble()), now: t(ms));
      ms += 100;
    }
    expect(c.count, 1);
  });

  test('long dropout resets to noBody', () {
    final c = PushupCounter();
    c.update(_pose(40), now: t(0));
    c.update(_pose(40), now: t(100));
    c.update(null, now: t(200));
    c.update(null, now: t(1000));
    expect(c.phase, PushupPhase.noBody);
  });
}
