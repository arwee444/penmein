import 'package:flutter/material.dart';

import '../data/notes.dart';
import '../main.dart';
import '../theme.dart';
import '../services/listen_service.dart';
import 'arwee.dart';
import 'common.dart';
import 'dictate_sheet.dart';
import 'note_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (on) {
        await turnListeningOn(context);
      } else {
        await listen.stop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(Note? n) => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteScreen(note: n)));

  Future<void> _delete(Note n) async {
    await notes.delete(n);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Note deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: () => notes.restore(n)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pen Me In', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          const ArweeCorner(),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: _listenCard()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search notes',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListenableBuilder(
              listenable: notes,
              builder: (context, _) {
                final list = notes.search(_search.text);
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        notes.notes.isEmpty
                            ? 'No notes yet.\nTurn on listening and say "pen me in", or tap + to type one.'
                            : 'No notes match.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Pal.fog),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 160),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                  itemBuilder: (context, i) => i == list.length ? const _ArweeSignature() : _tile(list[i]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'mic',
            tooltip: 'Dictate a note',
            backgroundColor: Pal.voice,
            foregroundColor: Pal.background,
            onPressed: () => showDictateSheet(context),
            child: const Icon(Icons.mic),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new',
            onPressed: () => _open(null),
            icon: const Icon(Icons.add),
            label: const Text('New note'),
          ),
        ],
      ),
    );
  }

  Widget _listenCard() => !ListenController.isSupported ? const _SiriCard() : ListenableBuilder(
    listenable: listen,
    builder: (context, _) {
      final on = listen.isRunning;
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: on ? Pal.coral : Pal.smoke, width: on ? 1.5 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(on ? Icons.graphic_eq : Icons.mic_off, color: on ? Pal.coral : Pal.fog),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      on ? 'Listening' : 'Listening is off',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: on ? Pal.coral : Pal.paper),
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    Transform.scale(
                      scale: 1.25,
                      child: Switch(
                        value: on,
                        activeThumbColor: Pal.background,
                        activeTrackColor: Pal.coral,
                        onChanged: _toggle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  on
                      ? 'Say "pen me in", wait for the buzz, then speak. Works with the screen locked. '
                            'Uses some battery while on.'
                      : 'Turn on to take notes hands-free, even with the phone locked.',
                  style: const TextStyle(color: Pal.fog, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _tile(Note n) {
    final voice = n.source == NoteSource.voice;
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Pal.coral.withValues(alpha: 0.2),
        child: const Icon(Icons.delete_outline, color: Pal.coral),
      ),
      onDismissed: (_) => _delete(n),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: Text(
          n.text.isEmpty ? '(empty)' : n.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(height: 1.3),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(voice ? Icons.mic : Icons.keyboard, size: 14, color: voice ? Pal.voice : Pal.gold),
              const SizedBox(width: 6),
              Text(formatWhen(n.created), style: const TextStyle(color: Pal.fog, fontSize: 12)),
            ],
          ),
        ),
        onTap: () => _open(n),
      ),
    );
  }
}

/// "an arwee app", shown after the last note (same as Save This Spot).
class _ArweeSignature extends StatelessWidget {
  const _ArweeSignature();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 20),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('an ', style: TextStyle(color: Pal.muted, fontSize: 13)),
        ArweeWordmark(height: 18, opacity: 0.85),
        Text(' app', style: TextStyle(color: Pal.muted, fontSize: 13)),
      ],
    ),
  );
}

/// iPhone: no background listening, so point to Siri instead of the switch.
class _SiriCard extends StatelessWidget {
  const _SiriCard();

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Pal.smoke)),
    child: const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over, color: Pal.gold),
              SizedBox(width: 10),
              Text('Hands-free with Siri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: 6),
          Text(
            'Say "Hey Siri, Pen Me In", then your note. Works from the lock screen. '
            'Or set it on the Action Button: Settings › Action Button › Shortcut › Pen me in.',
            style: TextStyle(color: Pal.fog, height: 1.3),
          ),
        ],
      ),
    ),
  );
}
