import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_tv/backend/fast_downloader.dart';
import 'package:open_tv/l10n/strings.dart';

/// Checks the project's GitHub Releases for a newer version on startup and,
/// if found, offers to download and install the APK.
class Updater {
  static const String repo = "davnozdu/smotrim-player";

  static Future<void> checkAndPrompt(
    GlobalKey<NavigatorState> navKey, {
    bool manual = false,
  }) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;
      final resp = await http
          .get(
            Uri.parse("https://api.github.com/repos/$repo/releases/latest"),
            headers: {"Accept": "application/vnd.github+json"},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        if (manual) _notify(navKey, (s) => s.checkFailed);
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final latest = (data["tag_name"] ?? "")
          .toString()
          .replaceAll(RegExp(r'^v'), '')
          .trim();
      if (latest.isEmpty || !_isNewer(latest, current)) {
        if (manual) _notify(navKey, (s) => s.upToDate);
        return;
      }

      final assets = (data["assets"] as List?) ?? [];
      final apkUrl = _pickApk(assets);
      if (apkUrl == null) {
        if (manual) _notify(navKey, (s) => s.checkFailed);
        return;
      }

      final ctx = navKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final notes = (data["body"] ?? "").toString().trim();
      final s = S.of(ctx);
      final accepted = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: Text(s.updateAvailable(latest)),
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
              child: Text(s.later),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(c, true),
              child: Text(s.update),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await _downloadAndInstall(navKey, apkUrl, latest);
    } catch (_) {
      if (manual) _notify(navKey, (s) => s.checkFailed);
      // Best-effort: never let an update check crash startup.
    }
  }

  static void _notify(
    GlobalKey<NavigatorState> navKey,
    String Function(S) pick,
  ) {
    final ctx = navKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text(pick(S.of(ctx)))));
  }

  static String? _pickApk(List assets) {
    // Prefer the universal APK (all ABIs in one file).
    for (final a in assets) {
      if ((a["name"] ?? "").toString() == "app-release.apk") {
        return a["browser_download_url"]?.toString();
      }
    }
    // Fallback: the 32-bit build (runs on all ARM devices).
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
        title: Text(S.of(ctx).downloadingUpdate),
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
      final ok = await FastDownloader.download(
        url,
        file,
        (p) => progress.value = p,
      );
      _closeDialog(navKey);
      if (ok) {
        await OpenFilex.open(
          file.path,
          type: "application/vnd.android.package-archive",
        );
      }
    } catch (_) {
      _closeDialog(navKey);
    }
  }

  static void _closeDialog(GlobalKey<NavigatorState> navKey) {
    final nav = navKey.currentState;
    if (nav != null && nav.canPop()) nav.pop();
  }
}
