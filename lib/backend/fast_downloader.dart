import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Multi-connection downloader. Splits the file into ranges and fetches them in
/// parallel (GitHub's release CDN supports HTTP Range), which is much faster
/// than a single throttled connection. Falls back to a single stream when the
/// server doesn't support ranges or anything goes wrong.
class FastDownloader {
  /// Downloads [url] into [dest]. [onProgress] gets 0..1 (best-effort).
  /// Returns true on success.
  static Future<bool> download(
    String url,
    File dest,
    void Function(double) onProgress, {
    int segments = 6,
  }) async {
    final client = http.Client();
    try {
      // Probe: request a single byte to learn the total size + range support.
      final probeReq = http.Request('GET', Uri.parse(url))
        ..headers['Range'] = 'bytes=0-0';
      final probe = await client.send(probeReq);

      // No range support: the probe response is the full body — stream it.
      if (probe.statusCode == 200) {
        return await _stream(probe, dest, probe.contentLength ?? 0, onProgress);
      }
      if (probe.statusCode != 206) {
        // Unexpected — fall back to a plain GET.
        await probe.stream.drain<void>();
        return await _single(client, url, dest, onProgress);
      }

      final total = _totalFromContentRange(probe.headers['content-range']);
      await probe.stream.drain<void>(); // discard the 1-byte probe body
      if (total <= 0 || segments <= 1) {
        return await _single(client, url, dest, onProgress);
      }

      try {
        return await _parallel(client, url, dest, total, segments, onProgress);
      } catch (_) {
        // Any failure mid-parallel: clean up and try a single stream.
        return await _single(client, url, dest, onProgress);
      }
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static int _totalFromContentRange(String? header) {
    // Format: "bytes 0-0/123456"
    if (header == null) return 0;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return 0;
    return int.tryParse(header.substring(slash + 1).trim()) ?? 0;
  }

  static Future<bool> _parallel(
    http.Client client,
    String url,
    File dest,
    int total,
    int segments,
    void Function(double) onProgress,
  ) async {
    final segSize = (total / segments).ceil();
    final received = List<int>.filled(segments, 0);
    final parts = <File>[];

    void report() {
      final sum = received.fold<int>(0, (a, b) => a + b);
      onProgress((sum / total).clamp(0.0, 1.0));
    }

    final futures = <Future<void>>[];
    for (var i = 0; i < segments; i++) {
      final start = i * segSize;
      if (start >= total) break;
      final end = min((i + 1) * segSize - 1, total - 1);
      final part = File('${dest.path}.part$i');
      parts.add(part);
      final idx = i;
      futures.add(() async {
        final req = http.Request('GET', Uri.parse(url))
          ..headers['Range'] = 'bytes=$start-$end';
        final resp = await client.send(req);
        // Must be 206 Partial Content. A 200 here means the server ignored the
        // range (returned the whole file) — abort so we fall back to a single
        // stream instead of stitching duplicated data.
        if (resp.statusCode != 206) {
          await resp.stream.drain<void>();
          throw Exception('Range not honored: ${resp.statusCode}');
        }
        final sink = part.openWrite();
        var got = 0;
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          got += chunk.length;
          received[idx] = got;
          report();
        }
        await sink.close();
      }());
    }

    try {
      await Future.wait(futures);
      // Stitch the parts together in order.
      final out = dest.openWrite();
      for (final p in parts) {
        await out.addStream(p.openRead());
      }
      await out.close();
      return true;
    } finally {
      for (final p in parts) {
        try {
          if (await p.exists()) await p.delete();
        } catch (_) {}
      }
    }
  }

  static Future<bool> _single(
    http.Client client,
    String url,
    File dest,
    void Function(double) onProgress,
  ) async {
    final resp = await client.send(http.Request('GET', Uri.parse(url)));
    return await _stream(resp, dest, resp.contentLength ?? 0, onProgress);
  }

  static Future<bool> _stream(
    http.StreamedResponse resp,
    File dest,
    int total,
    void Function(double) onProgress,
  ) async {
    final sink = dest.openWrite();
    var got = 0;
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress((got / total).clamp(0.0, 1.0));
    }
    await sink.close();
    return true;
  }
}
