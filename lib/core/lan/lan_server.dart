import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../db/edit_dao.dart';
import '../db/photo_dao.dart';
import '../models/photo.dart';
import 'web_gallery_html.dart';

/// Serves the library to any browser on the same Wi-Fi/LAN.
///
/// Everything here binds to a private interface and answers requests from the
/// local network only; there is no outbound socket anywhere in this class.
class LanServer {
  LanServer(this._dao, this._edits);

  final PhotoDao _dao;
  final EditDao _edits;

  HttpServer? _server;
  int _port = 8421;

  bool get isRunning => _server != null;
  int get port => _port;

  String get libraryName {
    final host = Platform.localHostname;
    return host.isEmpty ? 'Lumen' : 'Lumen · $host';
  }

  Future<int> start({int port = 8421}) async {
    if (_server != null) return _port;
    _port = port;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.autoCompress = true;
    _server!.listen(_handle, onError: (_) {});
    return _port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Best-effort list of private IPv4 addresses to show the user.
  static Future<List<String>> localAddresses() async {
    final out = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (_isPrivate(addr.address)) out.add(addr.address);
        }
      }
    } catch (_) {}
    return out;
  }

  static bool _isPrivate(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length > 1) {
        final second = int.tryParse(parts[1]);
        if (second != null && second >= 16 && second <= 31) return true;
      }
    }
    return false;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/' || path == '/index.html') {
        return _serveHtml(request);
      }
      if (path == '/api/photos') {
        return _servePhotoPage(request);
      }
      if (path == '/api/stats') {
        return _serveStats(request);
      }
      if (path.startsWith('/thumb/')) {
        return _serveThumb(request, path.substring('/thumb/'.length));
      }
      if (path.startsWith('/photo/')) {
        return _serveOriginal(request, path.substring('/photo/'.length));
      }
      if (path == '/health') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}');
        return request.response.close();
      }
      request.response.statusCode = HttpStatus.notFound;
      return request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveHtml(HttpRequest request) async {
    final body = buildGalleryHtml(libraryName: libraryName, port: _port);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..headers.set('Cache-Control', 'no-cache')
      ..write(body);
    await request.response.close();
  }

  Future<void> _servePhotoPage(HttpRequest request) async {
    final q = request.uri.queryParameters;
    final offset = int.tryParse(q['offset'] ?? '0') ?? 0;
    final limit = (int.tryParse(q['limit'] ?? '60') ?? 60).clamp(1, 200);
    final query = (q['q'] ?? '').trim();

    final filter = PhotoFilter(query: query);
    final total = await _dao.count(filter);
    final photos = await _dao.page(offset: offset, limit: limit, filter: filter);
    final recipes = await _edits.recipesFor(photos.map((e) => e.id));

    final payload = <String, Object?>{
      'total': total,
      'offset': offset,
      'photos': photos.map((photo) => _photoJson(photo, recipes[photo.id])).toList(),
    };
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
    await request.response.close();
  }

  Map<String, Object?> _photoJson(Photo photo, Object? recipe) => <String, Object?>{
        'id': photo.id,
        'file_name': photo.fileName,
        'width': photo.width,
        'height': photo.height,
        'camera_model': photo.cameraModel,
        'is_favorite': photo.isFavorite,
        'rating': photo.rating,
        'taken_label': DateFormat('d MMM yyyy').format(photo.takenAt),
        'edited': recipe != null,
      };

  Future<void> _serveStats(HttpRequest request) async {
    final total = await _dao.count();
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(<String, Object?>{
        'photos': total,
        'edited': await _edits.editedCount(),
        'host': Platform.localHostname,
        'platform': Platform.operatingSystem,
      }));
    await request.response.close();
  }

  Future<void> _serveThumb(HttpRequest request, String rawId) async {
    final id = int.tryParse(rawId);
    if (id == null) {
      request.response.statusCode = HttpStatus.badRequest;
      return request.response.close();
    }
    final file = File(AppPaths.thumbPath(id));
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      return request.response.close();
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('image', 'png')
      ..headers.set('Cache-Control', 'public, max-age=86400');
    await file.openRead().pipe(request.response);
  }

  Future<void> _serveOriginal(HttpRequest request, String rawId) async {
    final id = int.tryParse(rawId);
    if (id == null) {
      request.response.statusCode = HttpStatus.badRequest;
      return request.response.close();
    }
    final photo = await _dao.byId(id);
    if (photo == null) {
      request.response.statusCode = HttpStatus.notFound;
      return request.response.close();
    }
    final file = File(photo.path);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      return request.response.close();
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = _contentTypeFor(photo.ext)
      ..headers.set('Cache-Control', 'public, max-age=3600');
    await file.openRead().pipe(request.response);
  }

  ContentType _contentTypeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return ContentType('image', 'png');
      case 'webp':
        return ContentType('image', 'webp');
      case 'gif':
        return ContentType('image', 'gif');
      case 'bmp':
        return ContentType('image', 'bmp');
      default:
        return ContentType('image', 'jpeg');
    }
  }

  String get url => 'http://<your-lan-ip>:$_port';

  String? get exportDirHint => p.basename(AppPaths.exports.path);
}
