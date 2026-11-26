import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/home_pin.dart';
import '../app/platform_bridge.dart';
import '../app/settings.dart';
import 'retro.dart';
import 'retro_text_field.dart';

/// Wrong-PIN counter for the whole app (resets when the app restarts).
final PinLock _lock = PinLock();

/// Prefs section: make AIM the phone's home screen, so the Home key and
/// turning the phone on open AIM. Leaving takes the PIN chosen when it was
/// turned on. Android only.
class HomeScreenSection extends StatefulWidget {
  const HomeScreenSection({super.key});

  @override
  State<HomeScreenSection> createState() => _HomeScreenSectionState();
}

class _HomeScreenSectionState extends State<HomeScreenSection> {
  bool? _isHome;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // Coming back from Android's "pick a Home app" screen: show the result.
    _life = AppLifecycleListener(onResume: _check);
    _check();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final v = await PlatformBridge.isDefaultHome();
    if (mounted) setState(() => _isHome = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    const small = TextStyle(fontSize: 12);
    if (!s.homeMode) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Turn a phone into an AIM-only phone: the Home key and turning the phone on open AIM, '
            'and the phone\'s usual home screen and apps are out of the way. Leaving needs a PIN you choose now.',
            style: small),
        const SizedBox(height: 4),
        const Text('Tip: tick Auto-login on the sign-on screen so AIM signs straight on when the phone starts.',
            style: small),
        const SizedBox(height: 6),
        RetroButton(onPressed: () => turnOnHomeMode(context), child: const Text('Make AIM the Home Screen…')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        _isHome == null
            ? 'Home screen mode is on.'
            : _isHome!
                ? 'Home screen mode is on. The Home key opens AIM.'
                : 'Home screen mode is on, but Android still uses another home screen. '
                    'Tap "Pick AIM as Home", choose AIM, and pick "Always" or "Set as default" if asked.',
      ),
      const SizedBox(height: 6),
      if (_isHome == false) ...[
        RetroButton(onPressed: PlatformBridge.chooseHome, child: const Text('Pick AIM as Home')),
        const SizedBox(height: 4),
      ],
      RetroButton(onPressed: PlatformBridge.openWifi, child: const Text('Wi-Fi…')),
      const SizedBox(height: 4),
      RetroButton(
        onPressed: () async {
          if (await askHomePin(context, 'Android Settings', 'Enter the PIN to open Android\'s settings.')) {
            PlatformBridge.openSystemSettings();
          }
        },
        child: const Text('Android Settings… (PIN)'),
      ),
      const SizedBox(height: 4),
      RetroButton(onPressed: () => turnOffHomeMode(context), child: const Text('Leave Home Screen Mode… (PIN)')),
      const SizedBox(height: 4),
      const Text('Wi-Fi works without the PIN so whoever has the phone can join their own network.', style: small),
    ]);
  }
}

/// Choose a PIN (twice), then ask Android to use AIM as the home screen.
Future<void> turnOnHomeMode(BuildContext context) async {
  final s = context.read<AppSettings>();
  final a = TextEditingController();
  final b = TextEditingController();
  final ok = await showRetroDialog<bool>(context, title: 'Make AIM the Home Screen', builder: (ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('Choose a PIN (${HomePin.minLength} to ${HomePin.maxLength} numbers). '
          'You\'ll need it to leave home screen mode or open Android\'s settings.'),
      const SizedBox(height: 6),
      RetroTextField(controller: a, hint: 'PIN', obscure: true, digits: true, autofocus: true),
      const SizedBox(height: 4),
      RetroTextField(controller: b, hint: 'PIN again', obscure: true, digits: true,
          onSubmitted: (_) => Navigator.pop(ctx, true)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        RetroButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        const SizedBox(width: 6),
        RetroButton(isDefault: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
      ]),
    ]);
  });
  final pin = a.text.trim();
  final again = b.text.trim();
  a.dispose();
  b.dispose();
  if (ok != true || !context.mounted) return;
  if (!HomePin.valid(pin)) {
    return showRetroMessage(context, 'Home Screen',
        'The PIN needs ${HomePin.minLength} to ${HomePin.maxLength} numbers. Nothing was changed.');
  }
  if (pin != again) {
    return showRetroMessage(context, 'Home Screen', 'The two PINs didn\'t match. Nothing was changed.');
  }
  s.homePinHash = HomePin.hash(pin);
  s.homeMode = true;
  await PlatformBridge.setHomeScreenAllowed(true);
  if (!context.mounted) return;
  await showRetroMessage(context, 'Home Screen',
      'Android will now ask which home screen to use. Choose AIM, and pick "Always" or "Set as default" if asked.');
  await PlatformBridge.chooseHome();
}

/// Enter the PIN, then hand the phone back to its usual home screen.
Future<void> turnOffHomeMode(BuildContext context) async {
  final s = context.read<AppSettings>();
  if (!await askHomePin(context, 'Leave Home Screen Mode', 'Enter the PIN to turn off home screen mode.')) return;
  s.homeMode = false;
  s.homePinHash = '';
  await PlatformBridge.setHomeScreenAllowed(false);
  await PlatformBridge.goHome();
}

/// True if the right PIN was entered. Three wrong tries in a row mean a wait.
Future<bool> askHomePin(BuildContext context, String title, String message) async {
  final s = context.read<AppSettings>();
  final left = _lock.waitLeft;
  if (left > Duration.zero) {
    await showRetroMessage(context, title, 'Too many wrong PINs. Try again in ${left.inSeconds + 1} seconds.');
    return false;
  }
  final c = TextEditingController();
  final ok = await showRetroDialog<bool>(context, title: title, builder: (ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(message),
      const SizedBox(height: 6),
      RetroTextField(controller: c, hint: 'PIN', obscure: true, digits: true, autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, true)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        RetroButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        const SizedBox(width: 6),
        RetroButton(isDefault: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
      ]),
    ]);
  });
  final pin = c.text.trim();
  c.dispose();
  if (ok != true) return false;
  if (HomePin.matches(pin, s.homePinHash)) {
    _lock.right();
    return true;
  }
  _lock.wrong();
  if (context.mounted) {
    final wait = _lock.waitLeft;
    await showRetroMessage(context, title,
        wait > Duration.zero ? 'Wrong PIN. Try again in ${wait.inSeconds} seconds.' : 'Wrong PIN.');
  }
  return false;
}
