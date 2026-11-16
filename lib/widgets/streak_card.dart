import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/sound_service.dart';
import '../services/tts_service.dart';

const _milestones = [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 365, 500, 1000];
const _fire = [Color(0xFFFFB03A), Color(0xFFFF6B2C), Color(0xFFE53935)];

int _nextMilestone(int streak) =>
    _milestones.firstWhere((m) => m > streak, orElse: () => streak + 100);
int _prevMilestone(int streak) =>
    _milestones.lastWhere((m) => m <= streak, orElse: () => 0);

/// The streak hero on the Today tab: animated flame, count-up number, the last
/// seven days, progress to the next milestone — and a confetti celebration the
/// moment today's routine is completed.
class StreakCard extends StatefulWidget {
  const StreakCard({super.key});

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool? _wasPerfect;
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// Fires the celebration on the false -> true transition of "today is
  /// perfect". If another screen (e.g. the ringing alarm) is on top, wait for
  /// it to close so its own `pop` can't dismiss our dialog.
  void _track(AppState app) {
    final perfect = app.isPerfectDay(DateTime.now());
    final was = _wasPerfect;
    _wasPerfect = perfect;
    if (was != false || !perfect || _pending != null) return;
    _pending = Timer.periodic(const Duration(milliseconds: 400), (t) {
      if (!mounted) return t.cancel();
      if (ModalRoute.of(context)?.isCurrent != true) return;
      t.cancel();
      _pending = null;
      if (app.isPerfectDay(DateTime.now())) showStreakCelebration(context, app.streak);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    _track(app);

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final streak = app.streak;
    final todayDone = app.isPerfectDay(DateTime.now());
    final habits = app.enabledHabits.length;
    final done = app.doneCount();
    final alive = streak > 0;
    final fg = alive ? Colors.white : cs.onSurface;
    final fgDim = alive ? Colors.white70 : cs.onSurfaceVariant;

    // The flame only breathes while there is a streak to protect.
    if (alive && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!alive && _pulse.isAnimating) {
      _pulse.stop();
    }

    final next = _nextMilestone(streak);
    final prev = _prevMilestone(streak);
    final String message;
    if (todayDone) {
      message = 'Today is done. See you tomorrow!';
    } else if (alive) {
      message = 'Finish today to reach day ${streak + 1}';
    } else {
      message = 'Complete every habit today to light the flame';
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: alive
            ? const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _fire)
            : null,
        color: alive ? null : cs.surfaceContainerHighest,
        boxShadow: alive
            ? [
                BoxShadow(
                    color: _fire[1].withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ]
            : null,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.14)
                .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Opacity(
              opacity: alive ? 1 : 0.35,
              child: const Text('🔥', style: TextStyle(fontSize: 56)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: streak.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Text('${v.round()}',
                      style: tt.displayMedium
                          ?.copyWith(color: fg, fontWeight: FontWeight.w800, height: 1)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('day streak',
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(color: fgDim)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(message, style: tt.bodyMedium?.copyWith(color: fgDim)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        _WeekRow(days: app.lastDaysPerfect(7), alive: alive),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: habits == 0 ? 0 : done / habits),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 10,
              color: alive ? Colors.white : cs.primary,
              backgroundColor: alive ? Colors.white24 : cs.surfaceContainerLow,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text('$done of $habits done today',
                style: tt.labelLarge?.copyWith(color: fg)),
          ),
          Text('🏆 Best ${app.bestStreak}', style: tt.labelLarge?.copyWith(color: fg)),
        ]),
        const SizedBox(height: 4),
        Text(
          '${next - streak} ${next - streak == 1 ? 'day' : 'days'} to the $next-day milestone'
          '${prev > 0 ? '  ·  $prev-day badge earned' : ''}',
          style: tt.bodySmall?.copyWith(color: fgDim),
        ),
      ]),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.days, required this.alive});
  final List<bool> days;
  final bool alive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final on = alive ? Colors.white : cs.primary;
    final onIcon = alive ? _fire[2] : cs.onPrimary;
    final off = alive ? Colors.white24 : cs.surfaceContainerLow;
    final text = alive ? Colors.white70 : cs.onSurfaceVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < days.length; i++)
          Column(children: [
            Text(
              letters[DateTime(now.year, now.month, now.day - (days.length - 1 - i)).weekday - 1],
              style: tt.labelSmall?.copyWith(color: text),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: days[i] ? on : off,
                border: i == days.length - 1 && !days[i]
                    ? Border.all(color: on, width: 2)
                    : null,
              ),
              child: days[i] ? Icon(Icons.check_rounded, size: 20, color: onIcon) : null,
            ),
          ]),
      ],
    );
  }
}

/// Full-screen "you kept the streak" moment: confetti, a bouncing flame,
/// haptics, the success jingle and a spoken line.
Future<void> showStreakCelebration(BuildContext context, int streak) {
  HapticFeedback.heavyImpact();
  SoundService.instance.success();
  final milestone = _milestones.contains(streak);
  TtsService.instance.speak(milestone
      ? '$streak day streak! Milestone unlocked!'
      : streak == 1
          ? 'Routine complete. Your streak has started!'
          : 'Routine complete. $streak day streak!');
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) => _Celebration(streak: streak, milestone: milestone),
  );
}

class _Celebration extends StatefulWidget {
  const _Celebration({required this.streak, required this.milestone});
  final int streak;
  final bool milestone;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
        ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pop = CurvedAnimation(
        parent: _c, curve: const Interval(0, 0.35, curve: Curves.elasticOut));
    final next = _nextMilestone(widget.streak);
    return Stack(fit: StackFit.expand, children: [
      IgnorePointer(
        child: CustomPaint(painter: _ConfettiPainter(_c, widget.milestone ? 160 : 90)),
      ),
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Material(
            type: MaterialType.transparency,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ScaleTransition(
                scale: pop,
                child: Container(
                  width: 190,
                  height: 190,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(colors: _fire),
                    boxShadow: [
                      BoxShadow(color: _fire[1].withValues(alpha: 0.7), blurRadius: 60, spreadRadius: 8)
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🔥', style: TextStyle(fontSize: 54, height: 1.1)),
                    Text('${widget.streak}',
                        style: tt.displayMedium?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w900, height: 1)),
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                widget.milestone
                    ? '${widget.streak}-day milestone!'
                    : widget.streak == 1
                        ? 'Streak started!'
                        : '${widget.streak}-day streak!',
                textAlign: TextAlign.center,
                style: tt.headlineMedium
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Morning routine complete. '
                '${next - widget.streak} more ${next - widget.streak == 1 ? 'day' : 'days'} '
                'to the $next-day milestone.',
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: _fire[2]),
                onPressed: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('Keep it going'),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.count) : super(repaint: t);
  final Animation<double> t;
  final int count;

  static const _colors = [
    Color(0xFFFFD54F), Color(0xFFFF8A3D), Color(0xFFE53935),
    Color(0xFF4FC3F7), Color(0xFF81C784), Color(0xFFBA68C8), Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Deterministic per-particle parameters: same seed every frame.
    final rnd = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final x0 = rnd.nextDouble();
      final delay = rnd.nextDouble() * 0.35;
      final speed = 0.7 + rnd.nextDouble() * 0.7;
      final sway = 12 + rnd.nextDouble() * 28;
      final phase = rnd.nextDouble() * math.pi * 2;
      final w = 6 + rnd.nextDouble() * 6;
      final spin = 4 + rnd.nextDouble() * 10;
      final color = _colors[rnd.nextInt(_colors.length)];
      final p = ((t.value - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = -20 + p * speed * (size.height + 60);
      final x = x0 * size.width + math.sin(phase + p * 9) * sway;
      paint.color = color.withValues(alpha: p > 0.85 ? (1 - p) / 0.15 : 1);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(phase + p * spin)
        // Squash one axis over time so pieces look like they tumble.
        ..scale(1, math.cos(phase + p * spin * 1.7).abs().clamp(0.2, 1.0));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: w, height: w * 1.6),
              const Radius.circular(1.5)),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
