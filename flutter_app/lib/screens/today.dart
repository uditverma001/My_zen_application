import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';

const _quotes = [
  ('Before enlightenment, chop wood, carry water.\nAfter enlightenment, chop wood, carry water.', 'Zen proverb'),
  ('Nature does not hurry, yet everything is accomplished.', 'Lao Tzu'),
  ('The obstacle is the path.', 'Zen proverb'),
  ('An old pond.\nA frog jumps in.\nThe sound of water.', 'Matsuo Bashō'),
  ('When walking, walk. When eating, eat.', 'Zen proverb'),
  ('Muddy water is best cleared by leaving it alone.', 'Zen saying'),
  ('A journey of a thousand miles begins beneath one’s feet.', 'Lao Tzu'),
  ('Sitting quietly, doing nothing,\nspring comes, and the grass grows by itself.', 'Zen saying'),
  ('If you are calm, the whole world is calm.', ''),
  ('Let the breath be the anchor. Let thoughts be the weather.', ''),
  ('Fall seven times, stand up eight.', 'Japanese proverb'),
  ('Knowing others is intelligence; knowing yourself is true wisdom.', 'Lao Tzu'),
  ('No snowflake ever falls in the wrong place.', 'Zen saying'),
  ('You do not need to finish anything right now. Just this breath.', ''),
  ('The quieter you become, the more you can hear.', ''),
];

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.store, required this.onGo});

  final ZenStore store;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        final hour = now.hour;
        final greeting = hour < 5
            ? 'A quiet night'
            : hour < 12
            ? 'Good morning'
            : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
        // Same quote all day, a new one each day.
        final dayOfYear = now.difference(DateTime(now.year)).inDays;
        final (quote, author) = _quotes[dayOfYear % _quotes.length];
        final practiced = store.practicedDays;
        final today = dateOnly(now);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            ScreenHeader(
              eyebrow: '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}',
              title: greeting,
            ),
            ZenCard(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quote,
                    style: TextStyle(fontFamily: 'serif', fontSize: 21, height: 1.5, color: c.ink),
                  ),
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('— $author', style: TextStyle(fontSize: 14, color: c.muted)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(value: store.streak, label: 'day streak'),
                const SizedBox(width: 10),
                _Stat(value: store.totalMinutes, label: 'minutes total'),
                const SizedBox(width: 10),
                _Stat(value: store.sessions.length, label: 'sessions'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 6; i >= 0; i--)
                  _Day(
                    date: DateTime(today.year, today.month, today.day - i),
                    done: practiced.contains(DateTime(today.year, today.month, today.day - i)),
                    isToday: i == 0,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(onPressed: () => onGo(1), child: const Text('Take a breath')),
                OutlinedButton(onPressed: () => onGo(2), child: const Text('Sit for a while')),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return Expanded(
      child: ZenCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Text('$value', style: TextStyle(fontSize: 26, color: c.ink)),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.date, required this.done, required this.isToday});

  final DateTime date;
  final bool done;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? c.accent : c.surface,
            border: Border.all(color: done ? c.accent : c.line),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _weekdays[date.weekday - 1][0],
          style: TextStyle(
            fontSize: 12,
            color: isToday ? c.ink : c.muted,
            fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
