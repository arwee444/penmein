import 'package:flutter/material.dart';

import '../main.dart';
import '../services/settings.dart';
import '../services/vosk_model.dart';
import '../theme.dart';
import 'common.dart';

/// Install, remove and choose the offline speech models.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  VoiceSettings? _s;
  final _m = SpeechModels.instance;

  @override
  void initState() {
    super.initState();
    _m.check();
    VoiceSettings.load().then((s) => setState(() => _s = s));
  }

  Future<void> _use(SpeechModel model, {bool off = false}) async {
    final s = model.whisper ? _s!.copyWith(whisperId: off ? '' : model.id) : _s!.copyWith(modelId: model.id);
    setState(() => _s = s);
    await s.save();
    listen.pushSettings();
  }

  Future<void> _setLang(String lang) async {
    final s = _s!.copyWith(speakLang: lang);
    setState(() => _s = s);
    await s.save();
    listen.pushSettings();
  }

  Future<void> _delete(SpeechModel model) async {
    if (listen.isRunning) {
      toast(context, 'Turn listening off before removing a model.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${model.label}?'),
        content: Text('Frees about ${model.sizeMb} MB. You can download it again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _m.delete(model);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Speech models')),
      body: s == null
          ? const SizedBox()
          : ListenableBuilder(
              listenable: _m,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Models run offline on your phone. Install the ones you want and pick which one writes your notes. '
                    'If words are misheard, try "English · accurate" first.',
                    style: TextStyle(color: Pal.fog, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  for (final model in speechModels) ...[_card(model, s), const SizedBox(height: 10)],
                  const SizedBox(height: 14),
                  const Text('ACCURACY BOOST · WHISPER', style: TextStyle(color: Pal.gold, fontSize: 12, letterSpacing: 1.2)),
                  const SizedBox(height: 6),
                  const Text(
                    'Optional. The live model still hears "pen me in" and when you stop; Whisper then rewrites the note '
                    'from the recording, much more accurately. Notes are always written in English.',
                    style: TextStyle(color: Pal.fog, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  for (final model in whisperModels) ...[_card(model, s), const SizedBox(height: 10)],
                  _languagePicker(s),
                  const SizedBox(height: 8),
                  const Text(
                    'No offline models exist yet for Tamil, Kannada, UK or Australian English. '
                    '"English · accurate" handles UK and Australian accents best.',
                    style: TextStyle(color: Pal.fog, fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _card(SpeechModel model, VoiceSettings s) {
    final st = _m.state(model);
    final ready = st == ModelState.ready;
    final working = st == ModelState.downloading || st == ModelState.unpacking;
    final inUse = ready && (model.whisper ? s.whisperId == model.id : s.modelId == model.id);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: inUse ? Pal.gold : Pal.smoke),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(model.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
                Text('${model.sizeMb} MB', style: const TextStyle(color: Pal.fog, fontSize: 12)),
                const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(model.detail, style: const TextStyle(color: Pal.fog, fontSize: 13, height: 1.3)),
            ),
            if (working) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: st == ModelState.downloading ? _m.progress(model) : null),
              const SizedBox(height: 4),
              Text(
                st == ModelState.unpacking ? 'Unpacking…' : 'Downloading ${(_m.progress(model) * 100).round()}%',
                style: const TextStyle(color: Pal.fog, fontSize: 12),
              ),
            ],
            if (st == ModelState.failed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_m.error(model) ?? 'Download failed.', style: const TextStyle(color: Pal.coral, fontSize: 12)),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (ready)
                  inUse
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, size: 18, color: Pal.gold),
                              SizedBox(width: 6),
                              Text('In use', style: TextStyle(color: Pal.gold)),
                            ],
                          ),
                        )
                      : FilledButton.tonal(onPressed: () => _use(model), child: Text(model.whisper ? 'Use' : 'Use for notes')),
                if (inUse && model.whisper) TextButton(onPressed: () => _use(model, off: true), child: const Text('Turn off')),
                const Spacer(),
                if (ready)
                  TextButton(onPressed: _m.busy ? null : () => _delete(model), child: const Text('Remove'))
                else if (!working)
                  FilledButton.icon(
                    onPressed: _m.busy ? null : () => downloadModel(context, model),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _languages = {
  'en': 'English',
  'hi': 'Hindi → English',
  'ta': 'Tamil → English',
  'kn': 'Kannada → English',
  'auto': 'Mixed / detect → English',
};

extension on _ModelsScreenState {
  Widget _languagePicker(VoiceSettings s) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Pal.smoke)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('I speak', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Used by Whisper. Hindi, Tamil and Kannada are written as English.',
            style: TextStyle(color: Pal.fog, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _languages.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: s.speakLang == e.key,
                  onSelected: (_) => _setLang(e.key),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
