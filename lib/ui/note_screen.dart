import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/notes.dart';
import '../main.dart';
import '../theme.dart';
import 'common.dart';

/// View/edit one note. [note] null = a new typed note. Saves on leave.
class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, this.note});

  final Note? note;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final _text = TextEditingController(text: widget.note?.text ?? '');
  Note? _note;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_deleted) return;
    final t = _text.text.trim();
    final n = _note;
    if (n == null) {
      if (t.isNotEmpty) _note = await notes.add(t);
    } else {
      await notes.update(n, t);
    }
  }

  Future<void> _delete() async {
    final n = _note;
    _deleted = true;
    if (n != null) await notes.delete(n);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = _note;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(n == null ? 'New note' : 'Note'),
          actions: [
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _text.text));
                if (context.mounted) toast(context, 'Copied');
              },
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share),
              onPressed: _text.text.trim().isEmpty
                  ? null
                  : () => SharePlus.instance.share(ShareParams(text: _text.text.trim())),
            ),
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (n != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${n.source == NoteSource.voice ? '🎙 Voice' : '⌨ Typed'} · ${formatWhen(n.created)}'
                    '${n.updated.difference(n.created).inSeconds > 5 ? ' · edited ${formatWhen(n.updated)}' : ''}',
                    style: const TextStyle(color: Pal.fog, fontSize: 12),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: _text,
                  autofocus: n == null,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 17, height: 1.4),
                  decoration: const InputDecoration(hintText: 'Write something…'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
