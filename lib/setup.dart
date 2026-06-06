import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/backend/utils.dart';
import 'package:open_tv/correction_modal.dart';
import 'package:open_tv/home.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/home_manager.dart';
import 'package:open_tv/models/source.dart';
import 'package:open_tv/models/source_type.dart';
import 'package:open_tv/models/steps.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/l10n/strings.dart';

class Setup extends StatefulWidget {
  final bool showAppBar;
  const Setup({super.key, this.showAppBar = false});

  @override
  State<Setup> createState() => _SetupState();
}

class _SetupState extends State<Setup> {
  Steps step = Steps.welcome;
  SourceType selectedSourceType = SourceType.xtream;
  bool isForward = true;
  bool formValid = false;
  final Map<Steps, FocusNode> focusNodes = {
    Steps.name: FocusNode(),
    Steps.url: FocusNode(),
    Steps.username: FocusNode(),
    Steps.password: FocusNode(),
  };
  final formPages = {Steps.name, Steps.url, Steps.username, Steps.password};
  final _formKeys = {
    Steps.name: GlobalKey<FormBuilderState>(),
    Steps.url: GlobalKey<FormBuilderState>(),
    Steps.username: GlobalKey<FormBuilderState>(),
    Steps.password: GlobalKey<FormBuilderState>(),
  };
  final formValues = {
    Steps.name: "",
    Steps.url: "",
    Steps.username: "",
    Steps.password: "",
  };
  final nextButtonFocusNode = FocusNode();
  Set<String> existingSourceNames = {};

  Future<void> finish() async {
    var result = await Error.tryAsync(
      () async {
        await Utils.processSource(
          Source(
            name: formValues[Steps.name]!,
            sourceType: selectedSourceType,
            url: selectedSourceType == SourceType.m3u
                ? formValues[Steps.url]!
                : await fixUrl(formValues[Steps.url]!),
            username: selectedSourceType == SourceType.xtream
                ? formValues[Steps.username]
                : null,
            password: selectedSourceType == SourceType.xtream
                ? formValues[Steps.password]
                : null,
          ),
        );
      },
      context,
      null,
      true,
      false,
    );
    if (!result.success) {
      return;
    }
    setState(() {
      step = Steps.finish;
    });
  }

  Future<String> fixUrl(String url) async {
    var uri = Uri.parse(url);
    if (uri.scheme.isEmpty) {
      uri = Uri.parse("http://$uri");
    }
    if (uri.path == "/" || uri.path.isEmpty) {
      if (await showXtreamCorrectionModal()) {
        uri = uri.resolve("player_api.php");
      }
    }
    return uri.toString();
  }

  Future showXtreamCorrectionModal() async {
    return await showDialog(
      context: context,
      builder: (context) => CorrectionModal(),
    );
  }

  @override
  void initState() {
    nextButtonFocusNode.requestFocus();
    super.initState();
  }

  @override
  void dispose() {
    for (var focus in focusNodes.values) {
      focus.dispose();
    }
    nextButtonFocusNode.dispose();
    super.dispose();
  }

  // When the user confirms a text field with the on-screen keyboard
  // (IME "next"/done), move focus straight to the Next button instead of
  // leaving it stuck in the field. Big help for D-pad / TV remotes.
  void onFieldSubmitted(Steps s) {
    final valid = _formKeys[s]?.currentState?.isValid == true;
    if (!valid) return;
    setState(() => formValid = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) nextButtonFocusNode.requestFocus();
    });
  }

  Future<bool> selectFile() async {
    var path = (await FilePicker.platform.pickFiles())?.files.single.path;
    if (path == null) return false;
    formValues[Steps.url] = path;
    return true;
  }

  void prevStep() {
    isForward = false;
    if (formPages.contains(step)) {
      formValues[step] =
          _formKeys[step]?.currentState?.fields[step.name]?.value;
    }
    setState(() {
      step = Steps.values[step.index - 1];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        formValid = _formKeys[step]?.currentState?.isValid == true;
      });
      if (formPages.contains(step)) focusNodes[step]?.requestFocus();
      if (step == Steps.welcome) {
        nextButtonFocusNode.requestFocus();
      }
    });
  }

  Future<void> handleNext() async {
    isForward = true;
    if (formPages.contains(step)) {
      formValues[step] =
          _formKeys[step]?.currentState?.fields[step.name]?.value;
    }
    if (step == Steps.name) {
      var sourceName = formValues[step]!;
      if (await Sql.sourceNameExists(sourceName)) {
        existingSourceNames.add(sourceName);
        _formKeys[step]?.currentState?.validate();
        return;
      }
    }
    if (step == Steps.name && selectedSourceType == SourceType.m3u) {
      if (!await selectFile()) return;
      finish();
    } else if ((selectedSourceType == SourceType.m3uUrl && step == Steps.url) ||
        step == Steps.password) {
      finish();
    } else if (step == Steps.finish) {
      navigateToHome();
    } else {
      setState(() {
        step = Steps.values[step.index + 1];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          if (formValues[step]?.isNotEmpty == true) {
            _formKeys[step]?.currentState?.validate();
          }
          formValid = _formKeys[step]?.currentState?.isValid == true;
        });
        if (formPages.contains(step)) focusNodes[step]?.requestFocus();
      });
    }
  }

  void navigateToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => Home(
          home: HomeManager(filters: Filters(viewType: ViewType.all)),
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == Steps.welcome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) prevStep();
      },
      child: Scaffold(
        appBar: widget.showAppBar ? AppBar() : null,
        body: SafeArea(
          child: LoaderOverlay(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16,
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: (step.index + 1) / Steps.values.length,
                    ),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: PageTransitionSwitcher(
                    duration: const Duration(milliseconds: 400),
                    reverse: !isForward,
                    transitionBuilder:
                        (child, primaryAnimation, secondaryAnimation) {
                          return SharedAxisTransition(
                            animation: primaryAnimation,
                            secondaryAnimation: secondaryAnimation,
                            transitionType: SharedAxisTransitionType.horizontal,
                            child: child,
                          );
                        },
                    child: currentPage,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AnimatedOpacity(
                          opacity: step != Steps.welcome && step != Steps.finish
                              ? 1
                              : 0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: IgnorePointer(
                            ignoring:
                                step == Steps.welcome || step == Steps.finish,
                            child: FocusTraversalOrder(
                              order: NumericFocusOrder(2.0),
                              child: FilledButton.tonal(
                                onPressed: prevStep,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                ),
                                child: Text(
                                  S.of(context).back,
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                          ),
                        ),
                        FocusTraversalOrder(
                          order: NumericFocusOrder(1.0),
                          child: FilledButton(
                            focusNode: nextButtonFocusNode,
                            onPressed: !formPages.contains(step) || formValid
                                ? handleNext
                                : null,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                            child: Text(
                              step == Steps.name &&
                                      selectedSourceType == SourceType.m3u
                                  ? S.of(context).selectFile
                                  : step == Steps.finish
                                  ? S.of(context).finish
                                  : S.of(context).next,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget get currentPage {
    switch (step) {
      case Steps.welcome:
        return getPage(
          S.of(context).welcomeTitle("Smotrim CZ Player"),
          S.of(context).welcomeSub(!widget.showAppBar),
          null,
        );
      case Steps.sourceType:
        return getPage(
          S.of(context).providerType,
          null,
          List.generate(SourceType.values.length, (i) {
            final isLast = i == SourceType.values.length - 1;
            final card = Card(
              color: selectedSourceType.index == i
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).cardTheme.color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              child: ListTile(
                autofocus: selectedSourceType.index == i,
                title: Text((SourceType.values[i]).label),
                onTap: () {
                  setState(() {
                    formValues[Steps.url] = "";
                    selectedSourceType = SourceType.values[i];
                  });
                },
              ),
            );
            if (isLast) {
              return Focus(
                canRequestFocus: false,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    nextButtonFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: card,
              );
            }
            return card;
          }),
        );
      case Steps.name:
        return getPage(S.of(context).nameQuestion, null, [
          FormBuilder(
            onChanged: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  formValid =
                      _formKeys[Steps.name]!.currentState?.isValid == true;
                });
              });
            },
            initialValue: {Steps.name.name: formValues[Steps.name]},
            key: _formKeys[Steps.name],
            child: FormBuilderTextField(
              autocorrect: false,
              focusNode: focusNodes[Steps.name],
              onSubmitted: (_) => onFieldSubmitted(Steps.name),
              decoration: InputDecoration(
                labelText: S.of(context).name,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: FormBuilderValidators.compose([
                FormBuilderValidators.required(),
                (value) {
                  var trimmed = value?.trim();
                  if (trimmed == null || trimmed.isEmpty) {
                    return null;
                  }
                  if (existingSourceNames.contains(trimmed)) {
                    return S.of(context).nameExists;
                  }
                  return null;
                },
              ]),
              name: 'name',
            ),
          ),
        ]);
      case Steps.url:
        return getPage(S.of(context).urlQuestion, null, [
          FormBuilder(
            onChanged: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  formValid =
                      _formKeys[Steps.url]!.currentState?.isValid == true;
                });
              });
            },
            initialValue: {Steps.url.name: formValues[Steps.url]},
            key: _formKeys[Steps.url],
            child: FormBuilderTextField(
              autocorrect: false,
              focusNode: focusNodes[Steps.url],
              onSubmitted: (_) => onFieldSubmitted(Steps.url),
              decoration: InputDecoration(
                labelText: S.of(context).url,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: FormBuilderValidators.required(),
              name: 'url',
            ),
          ),
        ]);
      case Steps.username:
        return getPage(S.of(context).usernameQuestion, null, [
          FormBuilder(
            onChanged: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  formValid =
                      _formKeys[Steps.username]!.currentState?.isValid == true;
                });
              });
            },
            initialValue: {Steps.username.name: formValues[Steps.username]},
            key: _formKeys[Steps.username],
            child: FormBuilderTextField(
              autocorrect: false,
              focusNode: focusNodes[Steps.username],
              onSubmitted: (_) => onFieldSubmitted(Steps.username),
              decoration: InputDecoration(
                labelText: S.of(context).username,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: FormBuilderValidators.required(),
              name: 'username',
            ),
          ),
        ]);
      case Steps.password:
        return getPage(S.of(context).passwordQuestion, null, [
          FormBuilder(
            initialValue: {Steps.password.name: formValues[Steps.password]},
            onChanged: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  formValid =
                      _formKeys[Steps.password]!.currentState?.isValid == true;
                });
              });
            },
            key: _formKeys[Steps.password],
            child: FormBuilderTextField(
              autocorrect: false,
              focusNode: focusNodes[Steps.password],
              onSubmitted: (_) => onFieldSubmitted(Steps.password),
              decoration: InputDecoration(
                labelText: S.of(context).password,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.password),
              ),
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: FormBuilderValidators.required(),
              name: 'password',
            ),
          ),
        ]);
      case Steps.finish:
        return getPage(S.of(context).doneTitle, S.of(context).doneSub, null);
    }
  }

  Widget getPage(
    final String title,
    final String? subtitle,
    final List<Widget>? content,
  ) {
    return Center(
      key: ValueKey(title),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
            ],
            if (content != null) ...[const SizedBox(height: 24), ...content],
          ],
        ),
      ),
    );
  }
}
