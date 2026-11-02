import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Broadcasts a tiny UDP beacon so a phone on the same Wi-Fi can find the
/// desktop without typing an IP address. No cloud, no mDNS dependency, no
/// multicast DNS resolver quirks across Windows/Linux/Android.
class LanBeacon {
  static const int beaconPort = 5354;
  static const String magic = 'LUMEN1';

  RawDatagramSocket? _socket;
  Timer? _timer;

  bool get isRunning => _socket != null;

  Future<void> start({required int httpPort, String? name}) async {
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      _socket = socket;
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _broadcast(httpPort, name));
      _broadcast(httpPort, name);
    } catch (_) {
      // Broadcast is blocked on some corporate networks; the manual URL still works.
    }
  }

  void _broadcast(int httpPort, String? name) {
    final socket = _socket;
    if (socket == null) return;
    final payload = jsonEncode(<String, Object?>{
      'magic': magic,
      'name': name ?? Platform.localHostname,
      'port': httpPort,
      'os': Platform.operatingSystem,
    });
    try {
      socket.send(
        utf8.encode(payload),
        InternetAddress('255.255.255.255'),
        beaconPort,
      );
    } catch (_) {}
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}
