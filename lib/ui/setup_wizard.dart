import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../app/platform_bridge.dart';
import '../importer/aim_installer.dart';
import 'retro.dart';
import 'retro_text_field.dart';

/// First-run setup: load the classic sounds from the user's own AIM 5.1
/// installer (or archive.org), then the server address.
class SetupWizard extends StatefulWidget {
  /// If true, only the sounds step is shown (opened from Settings).
  final bool soundsOnly;
  const SetupWizard({super.key, this.soundsOnly = false});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _step = 0;
  String? _status;
  double? _progress;
  bool _busy = false;
  int _imported = 0;
  late final TextEditingController _server;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: context.read<AppState>().settings.server);
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _importInstallerBytes(Uint8List bytes) async {
    setState(() {
      _status = 'Unpacking sounds…';
      _progress = null;
    });
    final sounds = await extractSoundsInBackground(bytes);
    final engine = context.read<AppState>().sounds;
    for (final e in sounds.entries) {
      await engine.saveSound(e.key, e.value);
    }
    setState(() {
      _imported = sounds.length;
      _status = 'Imported ${sounds.length} classic sounds.';
    });
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on FormatException catch (e) {
      setState(() => _status = e.message);
    } catch (e) {
      setState(() => _status = 'Something went wrong: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _pickInstaller() => _run(() async {
        final r = await FilePicker.platform.pickFiles(
          dialogTitle: 'Choose aim513036.exe',
          type: Platform.isAndroid ? FileType.any : FileType.custom,
          allowedExtensions: Platform.isAndroid ? null : const ['exe'],
          withData: true,
        );
        final f = r?.files.firstOrNull;
        if (f == null) return;
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null) return;
        await _importInstallerBytes(bytes);
      });

  Future<void> _download() => _run(() async {
        setState(() {
          _status = 'Downloading from archive.org…';
          _progress = 0;
        });
        final client = http.Client();
        try {
          final resp = await client.send(http.Request('GET', Uri.parse(AimInstallerImporter.archiveOrgUrl)));
          if (resp.statusCode != 200) throw Exception('archive.org returned ${resp.statusCode}');
          final total = resp.contentLength ?? 2598120;
          final buf = BytesBuilder(copy: false);
          await for (final chunk in resp.stream) {
            buf.add(chunk);
            if (mounted) setState(() => _progress = (buf.length / total).clamp(0, 1).toDouble());
          }
          await _importInstallerBytes(buf.toBytes());
        } finally {
          client.close();
        }
      });

  Future<void> _pickWavs() => _run(() async {
        final r = await FilePicker.platform.pickFiles(
          dialogTitle: 'Choose .wav sound files',
          allowMultiple: true,
          type: Platform.isAndroid ? FileType.audio : FileType.custom,
          allowedExtensions: Platform.isAndroid ? null : const ['wav'],
          withData: true,
        );
        if (r == null) return;
        final engine = context.read<AppState>().sounds;
        var n = 0;
        for (final f in r.files) {
          final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
          if (bytes == null || !f.name.toLowerCase().endsWith('.wav')) continue;
          await engine.saveSound(f.name, bytes);
          n++;
        }
        setState(() {
          _imported += n;
          _status = 'Imported $n sound file${n == 1 ? '' : 's'}.';
        });
      });

  void _finish() {
    final app = context.read<AppState>();
    if (!widget.soundsOnly) {
      app.settings.server = _server.text;
      app.settings.setupDone = true;
      PlatformBridge.requestNotificationPermission();
    }
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final soundsStep = _step == 0;
    return Scaffold(
      body: SafeArea(
        child: Desktop(
          maxWidth: 520,
          child: SingleChildScrollView(
            child: RetroWindow(
              title: soundsStep ? 'Setup: Classic Sounds' : 'Setup: Server',
              child: soundsStep ? _sounds() : _serverStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sounds() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(6),
          child: Text(
            'This app doesn\'t include AOL\'s sounds. It can load the door creak, '
            'IM chimes and the rest from your own copy of the AIM 5.1 installer '
            '(aim513036.exe), download that installer from archive.org, or use any .wav files you have.\n\n'
            'Sounds only play while the app is open.',
          ),
        ),
        const SizedBox(height: 8),
        RetroButton(autofocus: true, onPressed: _busy ? null : _pickInstaller, child: const Text('Choose my AIM installer…')),
        const SizedBox(height: 6),
        RetroButton(onPressed: _busy ? null : _download, child: const Text('Download installer from archive.org')),
        const SizedBox(height: 6),
        RetroButton(onPressed: _busy ? null : _pickWavs, child: const Text('Import .wav files…')),
        const SizedBox(height: 10),
        if (_progress != null || _busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Sunken(
              padding: const EdgeInsets.all(2),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 14,
                backgroundColor: Colors.white,
                valueColor: const AlwaysStoppedAnimation(Retro.navy),
              ),
            ),
          ),
        if (_status != null) Padding(padding: const EdgeInsets.all(6), child: Text(_status!)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          RetroButton(
            onPressed: _busy
                ? null
                : () {
                    if (widget.soundsOnly) {
                      _finish();
                    } else {
                      setState(() => _step = 1);
                    }
                  },
            isDefault: _imported > 0,
            child: Text(widget.soundsOnly ? 'Done' : (_imported > 0 ? 'Next >' : 'Skip >')),
          ),
        ]),
      ],
    );
  }

  Widget _serverStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(6),
          child: Text('Enter the address of the AIM server (Open OSCAR Server) you connect to, for example '
              'aim.example.com:5190. You can change it later from the sign-on screen.'),
        ),
        RetroTextField(controller: _server, hint: 'server:5190', autofocus: true, onSubmitted: (_) => _finish()),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.all(6),
            child: Text('To stay signed on with the screen off, allow the app to run in the background.'),
          ),
          RetroButton(onPressed: PlatformBridge.requestBackgroundRunning, child: const Text('Allow background running')),
        ],
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          RetroButton(onPressed: () => setState(() => _step = 0), child: const Text('< Back')),
          RetroButton(isDefault: true, onPressed: _finish, child: const Text('Finish')),
        ]),
      ],
    );
  }
}

/// Unpacks the installer on a background thread. This must be a top-level
/// function: a closure made inside a widget method would drag the whole app
/// state along to the background thread, which Dart refuses ("object is unsendable").
Future<Map<String, Uint8List>> extractSoundsInBackground(Uint8List bytes) =>
    Isolate.run(() => AimInstallerImporter.extractSounds(bytes));
