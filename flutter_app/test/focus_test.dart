import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zen/focus_config.dart';
import 'package:zen/focus_lock.dart';
import 'package:zen/main.dart';
import 'package:zen/screens/focus.dart';
import 'package:zen/store.dart';

/// Stands in for MainActivity / FocusGuardService on the "zen/focus" channel.
class FakeAndroid {
  bool guard = false;
  bool pinned = false;
  bool acceptConfig = true;
  Map<String, dynamic>? config;
  DateTime? since;
  DateTime? until;
  final calls = <MethodCall>[];

  static const apps = {
    'com.whatsapp': 'WhatsApp',
    'com.google.android.apps.nbu.paisa.user': 'Google Pay',
    'com.instagram.android': 'Instagram',
    'com.spotify.music': 'Spotify',
    'com.google.android.apps.maps': 'Maps',
    'com.ubercab': 'Uber',
    'com.google.android.youtube': 'YouTube',
  };

  bool get active => until != null && clock.now().isBefore(until!);

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'guardEnabled':
        return guard;
      case 'setConfig':
        if (!acceptConfig || active) return false;
        config = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        return true;
      case 'startManual':
        since = clock.now();
        until = DateTime.fromMillisecondsSinceEpoch(call.arguments as int);
        return true;
      case 'state':
        return {
          'active': active,
          'since': active ? since!.millisecondsSinceEpoch : 0,
          'until': active ? until!.millisecondsSinceEpoch : 0,
        };
      case 'listApps':
        return [
          for (final e in apps.entries) {'package': e.key, 'label': e.value, 'icon': null},
        ];
      case 'startLock':
        pinned = true;
        return true;
      case 'stopLock':
        pinned = false;
        return true;
      case 'isLocked':
        return pinned;
      case 'setDnd':
      case 'hasDndAccess':
      case 'launchApp':
      case 'openDialer':
        return true;
    }
    return null;
  }

  List<MethodCall> named(String method) => calls.where((c) => c.method == method).toList();
}

void main() {
  late FakeAndroid android;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    focusSessionOpen.value = false;
    android = FakeAndroid();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      FocusLock.channel,
      android.handle,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(FocusLock.channel, null);
  });

  /// A phone-sized screen, so the layout matches what people see.
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  /// Scrolls the Focus tab (not another tab kept alive in the IndexedStack) to [finder].
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    // Items not built yet (further down the list) are scrolled to first.
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        100,
        scrollable: find.descendant(of: find.byType(FocusScreen), matching: find.byType(Scrollable)).first,
      );
    }
    // Bring it to the top so the bottom navigation bar can't cover it.
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<ZenStore> openFocusTab(WidgetTester tester) async {
    usePhoneScreen(tester);
    final store = await ZenStore.load();
    await tester.pumpWidget(ZenApp(store: store));
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> startFocus(WidgetTester tester, String duration) async {
    await scrollTo(tester, find.text(duration));
    await tester.tap(find.text(duration));
    await scrollTo(tester, find.text('Start focus'));
    await tester.tap(find.text('Start focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
  }

  group('FocusSchedule', () {
    // 2026-10-05 is a Monday.
    const mornings = FocusSchedule(days: {1, 2, 3, 4, 5}, start: 9 * 60, end: 11 * 60);
    const fridayNight = FocusSchedule(days: {5}, start: 23 * 60, end: 7 * 60);

    test('same-day block is active only inside its hours on chosen days', () {
      expect(mornings.isActiveAt(DateTime(2026, 10, 5, 8, 59)), isFalse);
      expect(mornings.isActiveAt(DateTime(2026, 10, 5, 9)), isTrue);
      expect(mornings.isActiveAt(DateTime(2026, 10, 5, 10, 59)), isTrue);
      expect(mornings.isActiveAt(DateTime(2026, 10, 5, 11)), isFalse);
      expect(mornings.isActiveAt(DateTime(2026, 10, 10, 10)), isFalse); // Saturday
      expect(mornings.copyWith(enabled: false).isActiveAt(DateTime(2026, 10, 5, 10)), isFalse);
    });

    test('overnight block runs past midnight', () {
      expect(fridayNight.isActiveAt(DateTime(2026, 10, 9, 23, 30)), isTrue);
      expect(fridayNight.isActiveAt(DateTime(2026, 10, 10, 6, 59)), isTrue);
      expect(fridayNight.isActiveAt(DateTime(2026, 10, 10, 7)), isFalse);
      expect(fridayNight.isActiveAt(DateTime(2026, 10, 9, 6)), isFalse);
    });

    test('labels and JSON round trip', () {
      expect(mornings.timeLabel, '9:00 AM – 11:00 AM');
      expect(mornings.daysLabel, 'Weekdays');
      expect(fridayNight.timeLabel, '11:00 PM – 7:00 AM (next day)');
      expect(fridayNight.daysLabel, 'Fri');
      final copy = FocusSchedule.fromJson(fridayNight.toJson());
      expect(copy.days, {5});
      expect(copy.start, 23 * 60);
    });
  });

  group('Focus without the app blocker (app pinning)', () {
    testWidgets('locks, cannot be ended early, and unlocks when time is up', (tester) async {
      final store = await openFocusTab(tester);
      expect(find.text('Turn on the app blocker'), findsOneWidget);
      await scrollTo(tester, find.text('Silence notifications (Do Not Disturb)'));
      await tester.tap(find.text('Silence notifications (Do Not Disturb)'));
      await tester.pumpAndSettle();
      await startFocus(tester, '15 min');

      expect(find.text('Stay with it'), findsOneWidget);
      expect(android.pinned, isTrue);
      expect(android.named('setDnd').single.arguments, isTrue);

      // No way out: no end button, and the system Back gesture is ignored.
      expect(find.textContaining('end early', findRichText: true), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Phone is locked to Zen'), findsOneWidget);

      await tester.pump(const Duration(minutes: 15));
      await tester.pump();
      expect(find.text('Focus complete'), findsOneWidget);
      expect(android.pinned, isFalse);
      expect(android.named('setDnd').last.arguments, isFalse);
      expect(store.sessions.single.type, 'focus');
      expect(store.sessions.single.seconds, 15 * 60);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Stay with it'), findsNothing);
      expect(find.text('Start focus'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation does not start a session', (tester) async {
      await openFocusTab(tester);
      await scrollTo(tester, find.text('Start focus'));
      await tester.tap(find.text('Start focus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Stay with it'), findsNothing);
      expect(android.named('startLock'), isEmpty);
    });
  });

  group('Focus with the app blocker', () {
    setUp(() => android.guard = true);

    testWidgets('suggests WhatsApp and Google Pay, and allows at most 5 apps', (tester) async {
      final store = await openFocusTab(tester);
      expect(find.text('App blocker is on'), findsOneWidget);
      expect(android.config!['allowed'], ['com.whatsapp', 'com.google.android.apps.nbu.paisa.user']);
      expect(find.text('2 of 5'), findsOneWidget);

      for (final app in ['Instagram', 'Spotify', 'Maps']) {
        await scrollTo(tester, find.text('Add app'));
        await tester.tap(find.text('Add app'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(app));
        await tester.pumpAndSettle();
      }
      expect(find.text('5 of 5'), findsOneWidget);
      expect(find.text('Add app'), findsNothing);
      expect(android.config!['allowed'], hasLength(5));
      expect(FocusConfig.load(store).allowed, hasLength(5));

      // Removing one makes room again.
      await tester.tap(find.descendant(of: find.widgetWithText(InputChip, 'Maps'), matching: find.byIcon(Icons.clear)));
      await tester.pumpAndSettle();
      expect(find.text('4 of 5'), findsOneWidget);
      expect(find.text('Add app'), findsOneWidget);
    });

    testWidgets('settings are refused while focus is running', (tester) async {
      await openFocusTab(tester);
      android.acceptConfig = false;
      await scrollTo(tester, find.text('Add app'));
      await tester.tap(find.text('Add app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YouTube'));
      await tester.pumpAndSettle();
      expect(find.text('Focus settings can\'t change during a focus session'), findsOneWidget);
      expect(find.text('2 of 5'), findsOneWidget);
    });

    testWidgets('adds a schedule, and warns when it would start right now', (tester) async {
      // Saturday noon: the default weekday 9–11 schedule is not running.
      await withClock(Clock.fixed(DateTime(2026, 10, 10, 12)), () async {
        await openFocusTab(tester);
        await scrollTo(tester, find.text('Add schedule'));
        await tester.tap(find.text('Add schedule'));
        await tester.pumpAndSettle();
        expect(find.text('New schedule'), findsOneWidget);
        await tester.tap(find.text('Save schedule'));
        await tester.pumpAndSettle();
        expect(find.text('9:00 AM – 11:00 AM'), findsOneWidget);
        expect(find.text('Weekdays'), findsOneWidget);
        expect((android.config!['schedules'] as List).single, {
          'days': [1, 2, 3, 4, 5],
          'start': 540,
          'end': 660,
          'enabled': true,
        });
      });

      // Monday 10:00: the same schedule would lock the phone immediately, so it asks first.
      await withClock(Clock.fixed(DateTime(2026, 10, 5, 10)), () async {
        await scrollTo(tester, find.text('Add schedule'));
        await tester.tap(find.text('Add schedule'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save schedule'));
        await tester.pumpAndSettle();
        expect(find.text('This starts right now'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect((android.config!['schedules'] as List), hasLength(1));
      });
    });

    testWidgets('a manual session shows allowed apps and ends when Android says so', (tester) async {
      final store = await openFocusTab(tester);
      await startFocus(tester, '25 min');

      expect(android.named('startManual'), hasLength(1));
      expect(android.named('startLock'), isEmpty); // the blocker replaces pinning
      expect(find.text('Allowed now'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      await tester.tap(find.text('WhatsApp'));
      await tester.tap(find.text('Phone'));
      expect(android.named('launchApp').single.arguments, 'com.whatsapp');
      expect(android.named('openDialer'), hasLength(1));

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(minutes: 10));
      expect(find.text('Stay with it'), findsOneWidget);

      await tester.pump(const Duration(minutes: 15, seconds: 2));
      await tester.pump();
      expect(find.text('Focus complete'), findsOneWidget);
      expect(store.sessions.single.seconds, 25 * 60);
    });

    testWidgets('a scheduled session opens by itself', (tester) async {
      usePhoneScreen(tester);
      final store = await ZenStore.load();
      await tester.pumpWidget(ZenApp(store: store));
      expect(find.text('Stay with it'), findsNothing);

      // A schedule kicks in on the Android side.
      android.since = clock.now();
      android.until = clock.now().add(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Stay with it'), findsOneWidget);
      expect(find.text('FOCUS · 60 MIN'), findsOneWidget);

      await tester.pump(const Duration(hours: 1));
      await tester.pump();
      expect(find.text('Focus complete'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Take a breath'), findsOneWidget);
    });
  });
}
