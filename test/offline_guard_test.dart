import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lumen promises that it never talks to the internet. That promise is worth
/// exactly as much as the test that enforces it, so here it is: any package or
/// API that could reach the open internet fails the build.
void main() {
  test('lib/ contains no outbound network client', () {
    final banned = <String>[
      'package:http/',
      'package:dio/',
      'package:webview_flutter/',
      'package:firebase',
      'HttpClient(',
      'Socket.connect',
      'WebSocket.connect',
      'InternetAddress.lookup',
      'getUrl(',
      'launchUrl(',
    ];

    final offenders = <String>[];
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the package root');

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final needle in banned) {
        if (source.contains(needle)) {
          offenders.add('${entity.path} -> $needle');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Lumen must stay offline. Offending call sites:\n${offenders.join('\n')}',
    );
  });

  test('the only listeners bind to the local network', () {
    // A server is allowed; a client dialling outward is not. This asserts the
    // two socket entry points we do use are the safe ones.
    final server = File('lib/core/lan/lan_server.dart').readAsStringSync();
    expect(server.contains('HttpServer.bind'), isTrue);
    expect(server.contains('Socket.connect'), isFalse);

    final beacon = File('lib/core/lan/lan_beacon.dart').readAsStringSync();
    expect(beacon.contains('RawDatagramSocket.bind'), isTrue);
    expect(beacon.contains('Socket.connect'), isFalse);
  });
}
