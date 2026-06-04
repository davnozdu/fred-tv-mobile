import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks the project's GitHub Releases for a newer version on startup and,
/// if found, offers to download and install the APK.
class Updater {
  static const String repo = "davnozdu/fred-tv-mobile";

  static Future<void> checkAndPrompt(GlobalKey<NavigatorState> navKey) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;
      final resp = await http
          .get(
            Uri.parse("https://api.github.com/repos/$repo/releases/latest"),
            headers: {"Accept": "application/vnd.github+json"},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final latest = (data["tag_name"] ?? "")
          .toString()
          .replaceAll(RegExp(r'^v'), '')
          .trim();
      if (latest.isEmpty || !_isNewer(latest, current)) return;

      final assets = (data["assets"] as List?) ?? [];
      final apkUrl = _pickApk(assets);
      if (apkUrl == null) return;

      final ctx = navKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final notes = (data["body"] ?? "").toString().trim();
      final accepted = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: Text("Update available ($latest)"),
          content: SingleChildScrollView(
            child: Text(
              notes.isNotEmpty
                  ? notes
                  : "A new version is available. Update now?",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text("Later"),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(c, true),
              child: const Text("Update"),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await _downloadAndInstall(navKey, apkUrl, latest);
    } catch (_) {
      // Best-effort: never let an update check crash startup.
    }
  }

  static String? _pickApk(List assets) {
    // Prefer the 32-bit build (runs on all ARM devices).
    for (final a in assets) {
      final name = (a["name"] ?? "").toString();
      if (name.contains("armeabi-v7a") && name.endsWith(".apk")) {
        return a["browser_download_url"]?.toString();
      }
    }
    for (final a in assets) {
      final name = (a["name"] ?? "").toString();
      if (name.endsWith(".apk")) {
        return a["browser_download_url"]?.toString();
      }
    }
    return null;
  }

  static bool _isNewer(String latest, String current) {
    List<int> parse(String v) => v
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final a = parse(latest);
    final b = parse(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static Future<void> _downloadAndInstall(
    GlobalKey<NavigatorState> navKey,
    String url,
    String version,
  ) async {
    final progress = ValueNotifier<double>(0);
    final ctx = navKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Downloading update…"),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value > 0 ? value : null),
              const SizedBox(height: 12),
              Text("${(value * 100).toStringAsFixed(0)}%"),
            ],
          ),
        ),
      ),
    );
    try {
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/update-$version.apk");
      final client = http.Client();
      final resp = await client.send(http.Request("GET", Uri.parse(url)));
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.close();
      client.close();
      _closeDialog(navKey);
      await OpenFilex.open(
        file.path,
        type: "application/vnd.android.package-archive",
      );
    } catch (_) {
      _closeDialog(navKey);
    }
  }

  static void _closeDialog(GlobalKey<NavigatorState> navKey) {
    final nav = navKey.currentState;
    if (nav != null && nav.canPop()) nav.pop();
  }
}
