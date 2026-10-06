import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';

const moods = [
  (value: 1, glyph: '😞', label: 'Heavy'),
  (value: 2, glyph: '😕', label: 'Low'),
  (value: 3, glyph: '😐', label: 'Okay'),
  (value: 4, glyph: '🙂', label: 'Good'),
  (value: 5, glyph: '😊', label: 'Bright'),
];

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _when(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.store});

  final ZenStore store;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _text = TextEditingController();
  int _mood = 3;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    widget.store.addEntry(_mood, _text.text.trim());
    _text.clear();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _delete(JournalEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) widget.store.deleteEntry(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c.line),
    );

    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final entries = [...widget.store.journal]..sort((a, b) => b.at.compareTo(a.at));
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const ScreenHeader(eyebrow: 'Journal', title: 'How are you, really?'),
            Row(
              children: [
                for (final (i, m) in moods.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      selected: m.value == _mood,
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _mood = m.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: m.value == _mood ? c.accentSoft : c.surface,
                            border: Border.all(color: m.value == _mood ? c.accent : c.line),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Text(m.glyph, style: const TextStyle(fontSize: 22)),
                              const SizedBox(height: 4),
                              Text(m.label, style: TextStyle(fontSize: 12, color: c.ink)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'A few words about this moment…',
                hintStyle: TextStyle(color: c.muted),
                filled: true,
                fillColor: c.surface,
                border: inputBorder,
                enabledBorder: inputBorder,
                focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.accent, width: 2)),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('Save')),
            const SizedBox(height: 24),
            for (final entry in entries) ...[
              _EntryCard(entry: entry, onDelete: () => _delete(entry)),
              const SizedBox(height: 10),
            ],
            if (entries.isEmpty)
              Text(
                'Your entries stay on this device only.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
          ],
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onDelete});

  final JournalEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final mood = moods.firstWhere((m) => m.value == entry.mood, orElse: () => moods[2]);
    return ZenCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${mood.glyph} ${mood.label} · ${_when(entry.at)}',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Delete'),
              ),
            ],
          ),
          if (entry.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(entry.text, style: TextStyle(fontSize: 16, height: 1.5, color: c.ink)),
            ),
        ],
      ),
    );
  }
}
