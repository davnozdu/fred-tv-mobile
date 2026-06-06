import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_tv/backend/launch_bridge.dart';
import 'package:open_tv/l10n/strings.dart';

/// Downloads and installs (or updates) the companion HLS-PROXY launcher app
/// from its GitHub Releases. Android's package installer handles the actual
/// install/update; this just fetches the latest APK and opens it.
class ProxyInstaller {
  static const String repo = "davnozdu/hls-proxy-android";
  static const String package = "com.hlsproxy.launcher";

  static Future<bool> isInstalled() => LaunchBridge.isPackageInstalled(package);

  static Future<void> installOrUpdate(BuildContext context) async {
    final s = S.of(context);
    final installed = await isInstalled();
    if (!context.mounted) return;
    // If already installed, confirm the user wants to update rather than
    // silently reinstalling.
    if (installed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.proxyUpdate),
          content: Text(s.proxyAlreadyInstalled),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(s.cancel),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(c, true),
              child: Text(s.update),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    String? apkUrl;
    try {
      final resp = await http
          .get(
            Uri.parse("https://api.github.com/repos/$repo/releases/latest"),
            headers: {"Accept": "application/vnd.github+json"},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final assets = (data["assets"] as List?) ?? [];
        for (final a in assets) {
          if ((a["name"] ?? "").toString().toLowerCase().endsWith(".apk")) {
            apkUrl = a["browser_download_url"]?.toString();
            break;
          }
        }
      }
    } catch (_) {}

    if (!context.mounted) return;
    if (apkUrl == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.checkFailed)));
      return;
    }
    await _download(context, apkUrl);
  }

  static Future<void> _download(BuildContext context, String url) async {
    final progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(S.of(c).downloadingUpdate),
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
    final navigator = Navigator.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/hls-proxy.apk");
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
      if (navigator.canPop()) navigator.pop();
      await OpenFilex.open(
        file.path,
        type: "application/vnd.android.package-archive",
      );
    } catch (_) {
      if (navigator.canPop()) navigator.pop();
    }
  }
}
