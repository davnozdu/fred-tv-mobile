import 'package:flutter/material.dart';
import 'package:open_tv/l10n/strings.dart';

class ConfirmDelete extends StatelessWidget {
  const ConfirmDelete(
      {super.key,
      required this.name,
      required this.confirm,
      required this.type});
  final VoidCallback confirm;
  final String type;
  final String name;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.confirmDeletion),
      content: Text("${s.deleteWhat(type, name)}?"),
      actions: [
        TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              confirm();
            },
            child: Text(s.confirm)),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel))
      ],
    );
  }
}
