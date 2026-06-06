import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/l10n/strings.dart';

/// A single obscured 4-digit PIN field used by the dialogs below.
class _PinField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  const _PinField({
    required this.controller,
    required this.label,
    this.autofocus = false,
  });

  @override
  State<_PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<_PinField> {
  final FocusNode _node = FocusNode();

  @override
  void initState() {
    super.initState();
    // Re-show the soft keyboard whenever the field regains focus (TV: pressing
    // Back hides it and it would otherwise stay hidden).
    _node.addListener(() {
      if (_node.hasFocus) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _node,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 4,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, letterSpacing: 8),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: widget.label, counterText: ''),
    );
  }
}

bool _valid(String pin) => pin.length == 4 && int.tryParse(pin) != null;

/// Prompts for a 4-digit PIN entered twice. Returns the PIN, or null if
/// cancelled / invalid.
Future<String?> setPinDialog(BuildContext context) async {
  final s = S.of(context);
  final a = TextEditingController();
  final b = TextEditingController();
  String? error;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(s.setPin),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PinField(controller: a, label: s.enterPin, autofocus: true),
            _PinField(controller: b, label: s.repeatPin),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () {
              if (!_valid(a.text)) {
                setState(() => error = s.pinInvalid);
                return;
              }
              if (a.text != b.text) {
                setState(() => error = s.pinMismatch);
                return;
              }
              Navigator.of(ctx).pop(a.text);
            },
            child: Text(s.ok),
          ),
        ],
      ),
    ),
  );
  a.dispose();
  b.dispose();
  return result;
}

/// Prompts for the current PIN and returns true if it matches [expected].
Future<bool> verifyPinDialog(
  BuildContext context,
  String expected, {
  String? title,
}) async {
  final s = S.of(context);
  final a = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title ?? s.enterCurrentPin),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PinField(controller: a, label: s.enterPin, autofocus: true),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () {
              if (a.text != expected) {
                setState(() => error = s.pinWrong);
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: Text(s.ok),
          ),
        ],
      ),
    ),
  );
  a.dispose();
  return ok ?? false;
}
