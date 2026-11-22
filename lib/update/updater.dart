import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/app_build.dart';
import '../config/share_config.dart';

/// One downloadable APK of a release.
class UpdateFile {
  const UpdateFile(this.file, this.sha256, this.size);
  final String file, sha256;
  final int size;
}

/// What the download page currently offers (`/get/latest.json`, written by publish.sh).
class UpdateInfo {
  const UpdateInfo(this.version, this.build, this.files);
  final String version;
  final int build;

  /// By ABI: 'arm64', 'armv7'.
  final Map<String, UpdateFile> files;

  static UpdateInfo? parse(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return null;
      final v = j['version'], b = j['build'], f = j['files'];
      if (v is! String || b is! num || f is! Map) return null;
      final files = <String, UpdateFile>{};
      f.forEach((abi, e) {
        if (abi is String && e is Map && e['file'] is String && e['sha256'] is String && e['size'] is num) {
          final name = e['file'] as String;
          // Only plain file names under /get/: never a link elsewhere.
          if (RegExp(r'^golicat-[0-9.]+-(arm64|armv7)\.apk$').hasMatch(name)) {
            files[abi] = UpdateFile(name, (e['sha256'] as String).toLowerCase(), (e['size'] as num).toInt());
          }
        }
      });
      return UpdateInfo(v, b.toInt(), files);
    } catch (_) {
      return null;
    }
  }
}

enum InstallStart { started, needsPermission, failed }

/// Checks GoliCat's own download page for a newer version, downloads it on
/// request, verifies it and hands it to Android's installer. Nothing is
/// downloaded unless the user says yes.
class Updater {
  Updater({
    http.Client? client,
    String? baseUrl,
    MethodChannel? channel,
    Future<Directory> Function()? tempDir,
    this.currentBuild = appBuild,
  })  : _client = client ?? http.Client(),
        _tempDir = tempDir ?? getTemporaryDirectory,
        baseUrl = baseUrl ?? shareBaseUrl,
        _ch = channel ?? const MethodChannel('golicat/update');

  final http.Client _client;
  final String baseUrl;
  final MethodChannel _ch;
  final int currentBuild;
  final Future<Directory> Function() _tempDir;

  /// Only the Android app updates itself (the web viewer is always current).
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// The newer release, or null (none, offline, or anything unexpected).
  Future<UpdateInfo?> check() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/get/latest.json?b=$currentBuild'), headers: {'cache-control': 'no-cache'})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final info = UpdateInfo.parse(r.body);
      if (info == null || info.build <= currentBuild || info.files.isEmpty) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  /// The APK that fits this phone's processor.
  Future<UpdateFile?> fileFor(UpdateInfo info) async {
    final abis = ((await _ch.invokeListMethod<String>('abis')) ?? const <String>[]);
    for (final a in abis) {
      if (a == 'arm64-v8a' && info.files['arm64'] != null) return info.files['arm64'];
      if (a == 'armeabi-v7a' && info.files['armv7'] != null) return info.files['armv7'];
    }
    return null;
  }

  /// Downloads and verifies [f]; [progress] gets 0..1. Throws on any failure.
  Future<File> download(UpdateFile f, void Function(double) progress) async {
    final dir = Directory('${(await _tempDir()).path}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true); // old, half or finished downloads
    dir.createSync(recursive: true);
    final out = File('${dir.path}/${f.file}');
    final req = http.Request('GET', Uri.parse('$baseUrl/get/${f.file}'));
    final res = await _client.send(req).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw HttpException('download failed (${res.statusCode})');
    final sink = out.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        progress(f.size > 0 ? (got / f.size).clamp(0.0, 1.0) : 0);
      }
    } finally {
      await sink.close();
    }
    if (got != f.size) throw const FileSystemException('download incomplete');
    final sha = await _ch.invokeMethod<String>('sha256', {'path': out.path});
    if (sha != f.sha256) {
      out.deleteSync();
      throw const FileSystemException('download damaged');
    }
    return out;
  }

  /// Removes a finished download (called once nothing newer is on offer,
  /// i.e. after the update went in), so it doesn't sit in storage.
  Future<void> cleanup() async {
    try {
      final dir = Directory('${(await _tempDir()).path}/updates');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  Future<bool> canInstall() async => (await _ch.invokeMethod<bool>('canInstall')) ?? false;
  Future<void> openInstallSettings() => _ch.invokeMethod('openInstallSettings');

  /// Opens Android's "Install this update?" screen.
  Future<InstallStart> install(File apk) async {
    try {
      if (!await canInstall()) return InstallStart.needsPermission;
      await _ch.invokeMethod('install', {'path': apk.path});
      return InstallStart.started;
    } catch (_) {
      return InstallStart.failed;
    }
  }

  void dispose() => _client.close();
}
