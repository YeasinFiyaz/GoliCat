import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golicat/update/updater.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('golicat/update');
  final apk = List<int>.generate(300000, (i) => i % 251);
  final good = sha256.convert(apk).toString();
  var abis = <String>['arm64-v8a', 'armeabi-v7a'];
  var canInstall = true;
  final installed = <String>[];

  String latest({int build = 20, String sha = '', int? size}) => jsonEncode({
        'version': '1.0.9',
        'build': build,
        'files': {
          'arm64': {'file': 'golicat-1.0.9-arm64.apk', 'sha256': sha.isEmpty ? good : sha, 'size': size ?? apk.length},
          'armv7': {'file': 'golicat-1.0.9-armv7.apk', 'sha256': good, 'size': apk.length},
        },
      });

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('golicat_upd');
    abis = ['arm64-v8a', 'armeabi-v7a'];
    canInstall = true;
    installed.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
      switch (call.method) {
        case 'abis':
          return abis;
        case 'canInstall':
          return canInstall;
        case 'sha256':
          return sha256.convert(File(call.arguments['path'] as String).readAsBytesSync()).toString();
        case 'install':
          installed.add(call.arguments['path'] as String);
          return true;
      }
      return null;
    });
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Updater make(String json, {int current = 13}) => Updater(
        client: MockClient.streaming((req, _) async {
          if (req.url.path == '/get/latest.json') {
            return http.StreamedResponse(Stream.value(utf8.encode(json)), 200);
          }
          if (req.url.path.endsWith('.apk')) {
            return http.StreamedResponse(Stream.fromIterable([apk.sublist(0, 100000), apk.sublist(100000)]), 200);
          }
          return http.StreamedResponse(const Stream.empty(), 404);
        }),
        baseUrl: 'https://example.test',
        tempDir: () async => tmp,
        currentBuild: current,
      );

  test('offers only a newer build', () async {
    expect(await make(latest(build: 20)).check(), isNotNull);
    expect(await make(latest(build: 13)).check(), isNull);
    expect(await make(latest(build: 12)).check(), isNull);
    expect(await make('not json').check(), isNull);
    expect(await make('{"version":"1","build":99,"files":{"arm64":{"file":"https://evil/x.apk","sha256":"a","size":1}}}').check(), isNull,
        reason: 'file names outside /get/ are ignored');
  });

  test('picks the right file for the phone', () async {
    final u = make(latest());
    final info = (await u.check())!;
    expect((await u.fileFor(info))!.file, 'golicat-1.0.9-arm64.apk');
    abis = ['armeabi-v7a'];
    expect((await u.fileFor(info))!.file, 'golicat-1.0.9-armv7.apk');
    abis = ['x86_64'];
    expect(await u.fileFor(info), isNull);
  });

  test('downloads, verifies and opens the installer', () async {
    final u = make(latest());
    final info = (await u.check())!;
    final steps = <double>[];
    final f = await u.download((await u.fileFor(info))!, steps.add);
    expect(f.lengthSync(), apk.length);
    expect(steps.last, 1.0);
    expect(await u.install(f), InstallStart.started);
    expect(installed, [f.path]);
  });

  test('a damaged or short download is never installed', () async {
    var u = make(latest(sha: 'deadbeef' * 8));
    var info = (await u.check())!;
    await expectLater(u.download((await u.fileFor(info))!, (_) {}), throwsA(isA<FileSystemException>()));
    u = make(latest(size: apk.length + 10));
    info = (await u.check())!;
    await expectLater(u.download((await u.fileFor(info))!, (_) {}), throwsA(isA<FileSystemException>()));
    expect(installed, isEmpty);
  });

  test('asks for the install permission when Android needs it', () async {
    final u = make(latest());
    final info = (await u.check())!;
    final f = await u.download((await u.fileFor(info))!, (_) {});
    canInstall = false;
    expect(await u.install(f), InstallStart.needsPermission);
    expect(installed, isEmpty);
  });
}
