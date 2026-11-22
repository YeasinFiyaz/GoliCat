import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'updater.dart';

/// "A newer version is available": Not now does nothing; Update downloads it
/// (with progress), checks it, and opens Android's install screen.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.updater, required this.info});
  final Updater updater;
  final UpdateInfo info;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Step { ask, downloading, permission, installing, failed }

class _UpdateDialogState extends State<UpdateDialog> with WidgetsBindingObserver {
  _Step _step = _Step.ask;
  double _progress = 0;
  File? _apk;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from "Allow from this source", or from the installer after Cancel.
    if (state == AppLifecycleState.resumed && _apk != null) {
      if (_step == _Step.permission) _install();
      if (_step == _Step.installing) setState(() => _step = _Step.installing);
    }
  }

  Future<void> _update() async {
    setState(() {
      _step = _Step.downloading;
      _progress = 0;
    });
    try {
      final f = await widget.updater.fileFor(widget.info);
      if (f == null) throw const FileSystemException('no download for this phone');
      _apk = await widget.updater.download(f, (p) {
        if (mounted && (p - _progress >= 0.01 || p == 1)) setState(() => _progress = p);
      });
      if (!mounted) return;
      await _install();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.failed;
        _error = e is FileSystemException && e.message == 'no download for this phone'
            ? 'This version isn\'t made for this phone\'s processor.'
            : 'The download didn\'t finish. Check your internet and try again.';
      });
    }
  }

  Future<void> _install() async {
    final r = await widget.updater.install(_apk!);
    if (!mounted) return;
    setState(() {
      switch (r) {
        case InstallStart.started:
          _step = _Step.installing;
        case InstallStart.needsPermission:
          _step = _Step.permission;
        case InstallStart.failed:
          _step = _Step.failed;
          _error = 'Android couldn\'t open the installer. Try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.info.version;
    return PopScope(
      canPop: _step != _Step.downloading,
      child: AlertDialog(
        title: Text(switch (_step) {
          _Step.ask => 'New version available',
          _Step.downloading => 'Downloading $v…',
          _Step.permission => 'One more step',
          _Step.installing => 'Install the update',
          _Step.failed => 'Update didn\'t finish',
        }),
        content: switch (_step) {
          _Step.ask => Text('GoliCat $v is ready. Do you want to update now?\n\n'
              'Your places, avatar and trips stay as they are.'),
          _Step.downloading => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 10),
              Text('${(_progress * 100).round()}%'),
            ]),
          _Step.permission => const Text('Android asks once before GoliCat can install its own updates.\n\n'
              'Tap Allow, turn on "Allow from this source", then come back here.'),
          _Step.installing => const Text('Tap Update (or Install) on Android\'s screen. '
              'GoliCat closes and opens again as the new version.'),
          _Step.failed => Text(_error),
        },
        actions: switch (_step) {
          _Step.ask => [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
              FilledButton(onPressed: _update, child: const Text('Update')),
            ],
          _Step.downloading => const <Widget>[],
          _Step.permission => [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
              FilledButton(onPressed: widget.updater.openInstallSettings, child: const Text('Allow')),
            ],
          _Step.installing => [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
              FilledButton(onPressed: _install, child: const Text('Install')),
            ],
          _Step.failed => [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              FilledButton(onPressed: _apk != null ? _install : _update, child: const Text('Try again')),
            ],
        },
      ),
    );
  }
}
