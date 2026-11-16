import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morning_glory/models/alarm_config.dart';
import 'package:morning_glory/screens/home_shell.dart';
import 'package:morning_glory/screens/math_challenge_screen.dart';
import 'package:morning_glory/services/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _pump(WidgetTester tester, Size size, {Widget? home}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final state = await AppState.load();
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(home: home ?? const HomeShell()),
  ));
  await tester.pump();
  return state;
}

void main() {
  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets('tabs render without layout errors at $size', (tester) async {
      final state = await _pump(tester, size);
      expect(find.text('Do pushups'), findsOneWidget);

      state.upsertAlarm(AlarmConfig(
          id: 1, hour: 7, minute: 0, weekdays: {1, 2, 3, 4, 5}, label: 'Work'));
      await tester.pump();

      await tester.tap(find.text('Alarms').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Work'), findsOneWidget);

      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      // Scroll through the whole settings list so every tile gets laid out.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('alarm editor opens and saves', (tester) async {
    final state = await _pump(tester, const Size(360, 640));
    await tester.tap(find.text('Alarms').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(state.alarms, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('math challenge renders', (tester) async {
    await _pump(tester, const Size(360, 640),
        home: const MathChallengeScreen(problems: 3));
    expect(find.textContaining('1 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
