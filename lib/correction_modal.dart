import 'package:flutter/material.dart';
import 'package:open_tv/l10n/strings.dart';

class CorrectionModal extends StatelessWidget {
  const CorrectionModal({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.correctUrlTitle),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.proceedAnyway)),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.correctUrlAuto))
      ],
      content: Text(s.correctUrlBody),
    );
  }
}
