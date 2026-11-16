import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Escape hatch for the ring screen. Pops `true` once every problem is solved;
/// a wrong answer restarts from problem 1 with fresh problems.
class MathChallengeScreen extends StatefulWidget {
  const MathChallengeScreen({super.key, required this.problems});
  final int problems;

  @override
  State<MathChallengeScreen> createState() => _MathChallengeScreenState();
}

class _Problem {
  _Problem(this.a, this.b, this.c);
  final int a, b, c;
  int get answer => a * b + c;
  String get text => '$a × $b + $c';
}

class _MathChallengeScreenState extends State<MathChallengeScreen> {
  final _rng = Random();
  final _ctrl = TextEditingController();
  late List<_Problem> _problems;
  int _index = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _problems = _generate();
  }

  List<_Problem> _generate() => List.generate(
        max(1, widget.problems),
        (_) => _Problem(10 + _rng.nextInt(90), 2 + _rng.nextInt(8), 100 + _rng.nextInt(900)),
      );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null) return;
    _ctrl.clear();
    if (v == _problems[_index].answer) {
      if (_index + 1 >= _problems.length) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _index++;
        _error = null;
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _index = 0;
        _problems = _generate();
        _error = 'Wrong! Back to problem 1 with new numbers.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Prove you are awake'),
          leading: BackButton(onPressed: () => Navigator.of(context).pop(false)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Problem ${_index + 1} of ${_problems.length}',
                    textAlign: TextAlign.center, style: tt.titleMedium),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _index / _problems.length),
                const SizedBox(height: 32),
                Text(_problems[_index].text,
                    textAlign: TextAlign.center,
                    style: tt.displayMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: tt.headlineMedium,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Answer',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 24,
                  child: Text(_error ?? '',
                      textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: _submit, child: const Text('Submit')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
