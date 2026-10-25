import 'package:flutter/material.dart';

import '../core/phrases.dart';
import '../main.dart';
import '../services/settings.dart';
import '../services/vosk_model.dart';
import '../theme.dart';
import 'common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  VoiceSettings? _s;

  @override
  void initState() {
    super.initState();
    VoiceSettings.load().then((s) => setState(() => _s = s));
    VoskModelManager.instance.check();
  }

  Future<void> _set(VoiceSettings s) async {
    setState(() => _s = s);
    await s.save();
    listen.pushSettings();
  }

  Future<void> _addPhrase(String title, List<String> existing, bool isWake, void Function(List<String>) apply) async {
    final c = TextEditingController();
    String? note;
    var level = PhraseCheck.ok;
    final added = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(
              hintText: isWake ? 'e.g. note this down' : 'e.g. thats all',
              helperText: note,
              helperMaxLines: 3,
              helperStyle: TextStyle(color: level == PhraseCheck.ok ? Pal.fog : Pal.coral),
            ),
            onChanged: (v) => setD(() => (level, note) = checkPhrase(v, existing, isWake: isWake)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: c.text.trim().isEmpty || level == PhraseCheck.invalid
                  ? null
                  : () => Navigator.pop(ctx, normalizeSpeech(c.text)),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    if (added != null && added.isNotEmpty) apply([...existing, added]);
  }

  Widget _phrases({
    required String title,
    required String help,
    required List<String> list,
    required bool isWake,
    required void Function(List<String>) apply,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(help, style: const TextStyle(color: Pal.fog, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in list)
                InputChip(
                  label: Text('"$p"'),
                  onDeleted: isWake && list.length == 1 ? null : () => apply(list.where((e) => e != p).toList()),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () => _addPhrase('Add phrase', list, isWake, apply),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: Pal.teal, fontSize: 12, letterSpacing: 1.2)),
  );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: s == null
          ? const SizedBox()
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _header('Phrases'),
                _phrases(
                  title: 'Wake phrases',
                  help: 'Say one of these to start a note. 2–4 uncommon words work best.',
                  list: s.wakePhrases,
                  isWake: true,
                  apply: (l) => _set(s.copyWith(wakePhrases: l)),
                ),
                _phrases(
                  title: 'Stop phrases',
                  help: 'Say one at the end of a note to save it straight away.',
                  list: s.stopPhrases,
                  isWake: false,
                  apply: (l) => _set(s.copyWith(stopPhrases: l)),
                ),
                _phrases(
                  title: 'Cancel phrases',
                  help: 'Say one at the end to throw the note away.',
                  list: s.cancelPhrases,
                  isWake: false,
                  apply: (l) => _set(s.copyWith(cancelPhrases: l)),
                ),
                _header('Timing'),
                ListTile(
                  title: const Text('Pause that ends a note'),
                  subtitle: Slider(
                    value: s.pauseMs / 1000,
                    min: 1,
                    max: 6,
                    divisions: 10,
                    label: '${(s.pauseMs / 1000).toStringAsFixed(1)} s',
                    onChanged: (v) => setState(() => _s = s.copyWith(pauseMs: (v * 1000).round())),
                    onChangeEnd: (v) => _set(s.copyWith(pauseMs: (v * 1000).round())),
                  ),
                  trailing: Text('${(s.pauseMs / 1000).toStringAsFixed(1)} s'),
                ),
                ListTile(
                  title: const Text('Longest note'),
                  subtitle: Slider(
                    value: s.maxSeconds.toDouble(),
                    min: 30,
                    max: 300,
                    divisions: 9,
                    onChanged: (v) => setState(() => _s = s.copyWith(maxSeconds: v.round())),
                    onChangeEnd: (v) => _set(s.copyWith(maxSeconds: v.round())),
                  ),
                  trailing: Text(s.maxSeconds < 60 ? '${s.maxSeconds} s' : '${(s.maxSeconds / 60).toStringAsFixed(1)} min'),
                ),
                SwitchListTile(
                  title: const Text('Vibrate'),
                  subtitle: const Text('Buzz when a note starts and when it is saved'),
                  value: s.vibrate,
                  onChanged: (v) => _set(s.copyWith(vibrate: v)),
                ),
                _header('Battery'),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Listening keeps the microphone and speech recogniser running, so it uses some battery. '
                    'Turn it off when you don\'t need it.\n\n$samsungTip',
                    style: TextStyle(color: Pal.fog, height: 1.35),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.battery_saver),
                  title: const Text('Allow running in the background'),
                  onTap: askBatteryExemption,
                ),
                _header('Speech model'),
                ListenableBuilder(
                  listenable: VoskModelManager.instance,
                  builder: (context, _) {
                    final m = VoskModelManager.instance;
                    final ready = m.state == VoskModelState.ready;
                    return ListTile(
                      leading: Icon(ready ? Icons.check_circle : Icons.download, color: ready ? Pal.teal : Pal.fog),
                      title: Text(ready ? 'English model installed' : 'Model not installed'),
                      subtitle: const Text('Offline. Your speech never leaves the phone.'),
                      onTap: ready ? null : () => ensureModel(context),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
