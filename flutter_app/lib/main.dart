import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _go(int tab) => setState(() => _tab = tab);

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
