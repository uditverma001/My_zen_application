import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'focus_config.dart';
import 'focus_lock.dart';
import 'screens/breathe.dart';
import 'screens/focus.dart';
import 'screens/journal.dart';
import 'screens/meditate.dart';
import 'screens/today.dart';
import 'sound.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = await ZenStore.load();
  // If the app was closed mid-focus, don't leave Do Not Disturb on.
  if (store.setting<bool>('dndActive', false)) {
    await FocusLock.setDnd(false);
    store.setSetting('dndActive', false);
  }
  // Keep Android's copy of allowed apps and schedules in step (it ignores this during focus).
  await FocusLock.setConfig(FocusConfig.load(store).toNativeJson());
  await Sound.init();
  runApp(ZenApp(store: store));
}

class ZenApp extends StatelessWidget {
  const ZenApp({super.key, required this.store});

  final ZenStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zen',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeShell(store: store),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final ZenStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _focusWatch;

  void _go(int tab) => setState(() => _tab = tab);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A scheduled session can begin while Zen is open, or Zen can be brought back by the blocker.
    _focusWatch = Timer.periodic(const Duration(seconds: 2), (_) => _checkFocus());
    _checkFocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusWatch?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkFocus();
  }

  Future<void> _checkFocus() async {
    if (focusSessionOpen.value) return;
    final state = await FocusLock.state();
    if (!state.active || !mounted || focusSessionOpen.value) return;
    await openFocusSession(
      context,
      widget.store,
      mode: FocusMode.blocker,
      since: state.since ?? clock.now(),
      until: state.until ?? clock.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      body: SafeArea(
        // IndexedStack keeps a running timer alive while you look at other tabs.
        child: IndexedStack(
          index: _tab,
          children: [
            TodayScreen(store: store, onGo: _go),
            BreatheScreen(store: store),
            MeditateScreen(store: store),
            FocusScreen(store: store),
            JournalScreen(store: store),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.air), label: 'Breathe'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Meditate'),
          NavigationDestination(icon: Icon(Icons.lock_outline), label: 'Focus'),
          NavigationDestination(icon: Icon(Icons.edit_note), label: 'Journal'),
        ],
      ),
    );
  }
}
