import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zen/focus_lock.dart';
import 'package:zen/main.dart';
import 'package:zen/screens/meditate.dart';
import 'package:zen/store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ZenStore', () {
    test('counts minutes and sessions, and persists them', () async {
      final store = await ZenStore.load();
      store.addSession('meditate', 300);
      store.addSession('breathe', 90);
      expect(store.totalMinutes, 6);
      expect(store.streak, 1);

      final reloaded = await ZenStore.load();
      expect(reloaded.sessions, hasLength(2));
      expect(reloaded.totalMinutes, 6);
    });

    test('streak counts consecutive days up to yesterday', () async {
      final now = DateTime.now();
      DateTime daysAgo(int n) => DateTime(now.year, now.month, now.day - n, 12);
      SharedPreferences.setMockInitialValues({
        'zen.v1':
            '{"sessions":['
            '{"type":"meditate","seconds":60,"at":${daysAgo(1).millisecondsSinceEpoch}},'
            '{"type":"meditate","seconds":60,"at":${daysAgo(2).millisecondsSinceEpoch}},'
            '{"type":"meditate","seconds":60,"at":${daysAgo(4).millisecondsSinceEpoch}}'
            ']}',
      });
      final store = await ZenStore.load();
      expect(store.streak, 2); // today not done yet, yesterday + day before
    });

    test('recovers from corrupt data', () async {
      SharedPreferences.setMockInitialValues({'zen.v1': 'not json'});
      final store = await ZenStore.load();
      expect(store.sessions, isEmpty);
      expect(store.journal, isEmpty);
    });
  });

  test('formatTime rounds up and pads', () {
    expect(formatTime(300), '05:00');
    expect(formatTime(59.2), '01:00');
    expect(formatTime(-3), '00:00');
  });

  testWidgets('navigates tabs and saves and deletes a journal entry', (tester) async {
    final store = await ZenStore.load();
    await tester.pumpWidget(ZenApp(store: store));

    expect(find.text('Take a breath'), findsOneWidget);

    await tester.tap(find.text('Breathe'));
    await tester.pumpAndSettle();
    expect(find.text('Follow the circle'), findsOneWidget);

    await tester.tap(find.text('Meditate'));
    await tester.pumpAndSettle();
    expect(find.text('05:00'), findsOneWidget);
    await tester.tap(find.text('10 min'));
    await tester.pump();
    expect(find.text('10:00'), findsOneWidget);

    await tester.tap(find.text('Journal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.enterText(find.byType(TextField), 'Quiet morning, tea and rain.');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Quiet morning, tea and rain.'), findsOneWidget);
    expect(store.journal.single.mood, 4);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(store.journal, isEmpty);
  });

  group('Focus', () {
    late List<MethodCall> calls;
    var locked = false;

    setUp(() {
      calls = [];
      locked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(FocusLock.channel, (
        call,
      ) async {
        calls.add(call);
        switch (call.method) {
          case 'startLock':
            locked = true;
            return true;
          case 'stopLock':
            locked = false;
            return true;
          case 'isLocked':
            return locked;
          case 'setDnd':
          case 'hasDndAccess':
            return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        FocusLock.channel,
        null,
      );
    });

    testWidgets('locks the phone, cannot be ended early, and unlocks when time is up', (tester) async {
      final store = await ZenStore.load();
      await tester.pumpWidget(ZenApp(store: store));
      await tester.tap(find.text('Focus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.tap(find.text('Silence notifications (Do Not Disturb)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start focus'));
      await tester.pumpAndSettle();
      expect(find.text('Focus for 15 minutes?'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Stay with it'), findsOneWidget);
      expect(locked, isTrue);
      expect(calls.where((c) => c.method == 'setDnd').single.arguments, isTrue);
      expect(store.setting<bool>('dndActive', false), isTrue);

      // No way out: no end button, and the system Back gesture is ignored.
      expect(find.textContaining('end early', findRichText: true), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Stay with it'), findsOneWidget);
      expect(find.text('Phone is locked to Zen'), findsOneWidget);

      await tester.pump(const Duration(minutes: 15));
      await tester.pump();
      expect(find.text('Focus complete'), findsOneWidget);
      expect(locked, isFalse);
      expect(calls.where((c) => c.method == 'setDnd').last.arguments, isFalse);
      expect(store.setting<bool>('dndActive', true), isFalse);
      expect(store.sessions.single.type, 'focus');
      expect(store.sessions.single.seconds, 15 * 60);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Put the phone down'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation does not start a session', (tester) async {
      final store = await ZenStore.load();
      await tester.pumpWidget(ZenApp(store: store));
      await tester.tap(find.text('Focus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start focus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Stay with it'), findsNothing);
      expect(calls.where((c) => c.method == 'startLock'), isEmpty);
    });
  });
}
