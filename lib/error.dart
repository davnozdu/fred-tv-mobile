import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:open_tv/l10n/strings.dart';
import 'package:open_tv/models/result.dart';
import 'package:url_launcher/url_launcher.dart';

class Error {
  static Future<void> handleError(BuildContext context, String error) async {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: Colors.red[700],
            content: Text(
              S.of(context).errorTitle,
              style: const TextStyle(color: Colors.white),
            ),
            action: SnackBarAction(
                label: S.of(context).details,
                textColor: Colors.white,
                onPressed: () async => {
                      await showDialog(
                          barrierDismissible: true,
                          context: context,
                          builder: (builder) => AlertDialog(
                                title: const Text('Error'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(S.of(context).errorDetailsBody),
                                    Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(
                                            8.0), // Padding inside the box
                                        decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius:
                                                BorderRadius.circular(8.0)),
                                        child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxHeight: 200),
                                            child: SingleChildScrollView(
                                                child: Text(
                                              error,
                                              style: const TextStyle(
                                                  color: Colors.white),
                                            ))))
                                  ],
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      textStyle: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    child: Text(S.of(context).reportIssue),
                                    onPressed: () async {
                                      final Uri url = Uri.parse(
                                          'https://github.com/davnozdu/smotrim-player/issues/new');
                                      await launchUrl(url,
                                          mode: LaunchMode.externalApplication);
                                    },
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      textStyle: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    child: const Text('Copy'),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(
                                          text: error.toString()));
                                    },
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      textStyle: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    child: const Text('Close'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ],
                              ))
                    })),
      );
    }
  }

  static void showSuccess(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  static Future<Result<T>> tryAsync<T>(
      Future<T?> Function() fn, BuildContext context,
      [String? successMessage,
      bool useLoading = true,
      bool useSuccess = true]) async {
    var success = false;
    T? result;
    if (useLoading && context.mounted) {
      context.loaderOverlay.show();
    }
    try {
      result = await fn();
      if (useSuccess && context.mounted) {
        showSuccess(context, successMessage ?? S.of(context).actionCompleted);
      }
      success = true;
    } catch (e, stackTrace) {
      final error = "${e.toString()}\n${stackTrace.toString()}";
      await handleError(context, error);
    }
    if (useLoading && context.loaderOverlay.visible) {
      context.loaderOverlay.hide();
    }
    return Result(success: success, data: result);
  }

  static Future<Result<T>> tryAsyncNoLoading<T>(
      Future<T?> Function() fn, BuildContext context,
      [bool useSuccess = false, String? successMessage]) async {
    return await tryAsync(fn, context, successMessage, false, useSuccess);
  }
}
