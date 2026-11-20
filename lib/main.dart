import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'app/input_mode.dart';
import 'app/numpad_t9.dart';
import 'app/settings.dart';
import 'app/updater.dart';
import 'oscar/client.dart';
import 'ui/home.dart';
import 'ui/retro.dart';
import 'ui/setup_wizard.dart';
import 'ui/sign_on.dart';
import 'ui/sign_up.dart';
import 'ui/t9_phone.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  final input = InputMode(settings);
  final app = AppState(settings, input);
  final updates = UpdateChecker(settings)..start();
  final osk = OskController();
  final numpad = NumpadT9(settings, osk);
  HardwareKeyboard.instance.addHandler(numpad.handle);
  HardwareKeyboard.instance.addHandler(input.handleKey);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: input),
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: updates),
        ChangeNotifierProvider.value(value: osk),
        Provider.value(value: numpad),
      ],
      child: const AimApp(),
    ),
  );
  await app.checkForInvite();
  if (settings.setupDone && app.pendingInvite == null) await app.tryAutoLogin();
}

class AimApp extends StatefulWidget {
  const AimApp({super.key});

  @override
  State<AimApp> createState() => _AimAppState();
}

class _AimAppState extends State<AimApp> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _life = AppLifecycleListener(
      // "inactive" is a notification shade or an unfocused desktop window:
      // still on screen, so not away.
      onStateChange: (s) =>
          app.setForeground(s == AppLifecycleState.resumed || s == AppLifecycleState.inactive),
    );
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final app = context.watch<AppState>();
    final input = context.read<InputMode>();
    Widget home;
    final invite = app.pendingInvite;
    if (invite != null && !app.everOnline) {
      home = SignUpScreen(key: ValueKey(invite.code), invite: invite);
    } else if (!settings.setupDone) {
      home = const SetupWizard();
    } else if (app.client == null || app.link == LinkState.stopped || app.link == LinkState.offline) {
      home = const SignOnScreen();
    } else if (!app.everOnline) {
      home = const SignOnScreen();
    } else {
      home = const HomeShell();
    }
    return MaterialApp(
      title: 'AIM',
      debugShowCheckedModeBanner: false,
      theme: Retro.theme(),
      navigatorKey: navigatorKey,
      builder: (ctx, child) => Listener(
        // Touching the T9 phone itself shouldn't leave controller mode.
        onPointerDown: (_) {
          if (ctx.read<OskController>().current == null) input.noteTouchOrKeyboard();
        },
        child: OskHost(child: child ?? const SizedBox.shrink()),
      ),
      home: home,
    );
  }
}
