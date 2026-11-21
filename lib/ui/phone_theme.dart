import 'dart:math';

import 'package:flutter/material.dart';

/// Cartoon early-2000s phone looks (original designs, no real brands).
/// Values come from the design canvas (aim-t9-handover/generators/cartoon.py).
enum BodyPattern { plain, dots, leopard }

/// What kind of gadget it is. [phone]s use the T9 keypad or slide-out QWERTY
/// (per the keyboard setting); [wideFlip] is a keypad phone that opens the long
/// way to a keyboard; the rest always use their own keys (a T9 keypad for the
/// [PhoneTheme.t9Gadget]s, letter by letter for the others).
enum Device {
  phone,
  wideFlip,
  dashboard,
  pocketMail,
  musicPlayer,
  pocketBrick,
  swivel,
  popTilt,
  compact,
  taco,
  lipstick,
  pager,
  cordless,
  watch,
  rotator,
  jelly,
  eggPet,
  wideT9,
}

const _t9Gadgets = {
  Device.swivel,
  Device.compact,
  Device.taco,
  Device.cordless,
  Device.watch,
  Device.rotator,
  Device.jelly,
  Device.wideT9,
};

class PhoneTheme {
  final String id;
  final String name;
  final String blurb;
  final bool flip;
  final Color ink; // outlines
  final Color body; // candybar body / flip base
  final BodyPattern pattern;
  final Color lid; // flip: inside of the lid
  final Color shell; // flip: outside of the lid
  final BodyPattern shellPattern;
  final Color hinge;
  final Color screenOn, screenOff, screenInk, screenDim;
  final Color me, them;
  final bool mono; // pixel-style screen font
  final bool glow; // backlit text
  final Color keyBg, keyInk, keySub;
  final BorderRadius keyRadius;
  final Color? keyInset;
  final Color softBg, softInk;
  final Color focus;
  final String splash;
  final Device device;

  /// Hint under the chat on the little screen.
  final String sendHint;
  // decorations
  final Color? antennaBall; // plain antenna
  final bool bow, heartAntenna, rhinestones, bubbles;
  final List<Color>? strap;

  const PhoneTheme({
    required this.id,
    required this.name,
    required this.blurb,
    this.flip = false,
    required this.ink,
    required this.body,
    this.pattern = BodyPattern.plain,
    Color? lid,
    Color? shell,
    this.shellPattern = BodyPattern.plain,
    Color? hinge,
    required this.screenOn,
    required this.screenOff,
    required this.screenInk,
    required this.screenDim,
    required this.me,
    required this.them,
    this.mono = false,
    this.glow = false,
    required this.keyBg,
    required this.keyInk,
    required this.keySub,
    this.keyRadius = const BorderRadius.all(Radius.circular(16)),
    this.keyInset,
    required this.softBg,
    required this.softInk,
    required this.focus,
    this.splash = 'aim',
    this.device = Device.phone,
    this.sendHint = 'Send ▸ green key',
    this.antennaBall,
    this.bow = false,
    this.heartAntenna = false,
    this.rhinestones = false,
    this.bubbles = false,
    this.strap,
  })  : lid = lid ?? body,
        shell = shell ?? body,
        hinge = hinge ?? body;

  String? get fontFamily => mono ? 'monospace' : null;

  /// True when typing is letter-by-letter (a keyboard), false for the T9 keypad.
  /// [qwertyKind] is the user's keyboard setting (or the full-screen choice).
  bool letters(bool qwertyKind) => switch (device) {
        Device.phone || Device.wideFlip => qwertyKind,
        _ => !t9Gadget,
      };

  /// Gadgets that always type on their own T9 keypad.
  bool get t9Gadget => _t9Gadgets.contains(device);

  /// Gadgets that always use their own keyboard (the keyboard setting does nothing).
  bool get ownKeyboard => device != Device.phone && device != Device.wideFlip;
}

const kSendGreen = Color(0xFF3CCF6E);
const kEndRed = Color(0xFFFF5A5F);

const kPhoneThemes = <PhoneTheme>[
  PhoneTheme(
    id: 'brick',
    name: 'Brick',
    blurb: 'Chunky blue candybar',
    ink: Color(0xFF141A2B),
    body: Color(0xFF4A6FB0),
    screenOn: Color(0xFFB5CC7A),
    screenOff: Color(0xFF5D6B48),
    screenInk: Color(0xFF1F2A14),
    screenDim: Color(0xFF46552F),
    me: Color(0xFF1F2A14),
    them: Color(0xFF1F2A14),
    mono: true,
    keyBg: Color(0xFFEEF1F6),
    keyInk: Color(0xFF141A2B),
    keySub: Color(0xFF3F4B66),
    keyRadius: BorderRadius.only(
        topLeft: Radius.circular(20), topRight: Radius.circular(20),
        bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
    softBg: Color(0xFFFFD23F),
    softInk: Color(0xFF141A2B),
    focus: Color(0xFFFF5A5F),
    antennaBall: Color(0xFFFF5A5F),
  ),
  PhoneTheme(
    id: 'ice',
    name: 'Ice',
    blurb: 'See-through purple',
    ink: Color(0xFF2A1866),
    body: Color(0xB89676F0),
    screenOn: Color(0xFFF6F3FF),
    screenOff: Color(0xFF8D7CC8),
    screenInk: Color(0xFF2A1866),
    screenDim: Color(0xFF6D5BB0),
    me: Color(0xFFC2185B),
    them: Color(0xFF3B2AA8),
    keyBg: Color(0xB8FFFFFF),
    keyInk: Color(0xFF2A1866),
    keySub: Color(0xFF4E3A9A),
    keyRadius: BorderRadius.all(Radius.circular(999)),
    softBg: Color(0xFF7EE8FA),
    softInk: Color(0xFF2A1866),
    focus: Color(0xFFFF7AC6),
    antennaBall: Color(0xFF7EE8FA),
    bubbles: true,
  ),
  PhoneTheme(
    id: 'nightglow',
    name: 'Night Glow',
    blurb: 'Backlit orange keys',
    ink: Color(0xFF000000),
    body: Color(0xFF232329),
    screenOn: Color(0xFF1F1200),
    screenOff: Color(0xFF0B0700),
    screenInk: Color(0xFFFFB347),
    screenDim: Color(0xFFC98A3A),
    me: Color(0xFFFFD28A),
    them: Color(0xFFFFB347),
    mono: true,
    glow: true,
    keyBg: Color(0xFF2E2E36),
    keyInk: Color(0xFFFFB347),
    keySub: Color(0xFFE0A65A),
    keyInset: Color(0x73FFB347),
    softBg: Color(0xFFFFB347),
    softInk: Color(0xFF000000),
    focus: Color(0xFFFFFFFF),
    antennaBall: Color(0xFFFFB347),
  ),
  PhoneTheme(
    id: 'clamshell',
    name: 'Clamshell',
    blurb: 'Silver-blue flip',
    flip: true,
    ink: Color(0xFF1C2A44),
    body: Color(0xFFC9D3E3),
    lid: Color(0xFFC9D3E3),
    shell: Color(0xFF9FB4D6),
    hinge: Color(0xFF8EA3C6),
    screenOn: Color(0xFF071631),
    screenOff: Color(0xFF02060F),
    screenInk: Color(0xFF8FD3FF),
    screenDim: Color(0xFF4F86B8),
    me: Color(0xFFFFD166),
    them: Color(0xFF8FD3FF),
    keyBg: Color(0xFFFFFFFF),
    keyInk: Color(0xFF0E3A7A),
    keySub: Color(0xFF3D5F8F),
    softBg: Color(0xFF8FD3FF),
    softInk: Color(0xFF1C2A44),
    focus: Color(0xFFFF5A5F),
    antennaBall: Color(0xFF8FD3FF),
  ),
  PhoneTheme(
    id: 'girlypop',
    name: 'Girly Pop',
    blurb: 'Pink polka-dot flip with a bow',
    flip: true,
    ink: Color(0xFF7A1F52),
    body: Color(0xFFFF9CCF),
    pattern: BodyPattern.dots,
    lid: Color(0xFFFFB8DC),
    shell: Color(0xFFFF7FBF),
    shellPattern: BodyPattern.dots,
    hinge: Color(0xFFC7A6FF),
    screenOn: Color(0xFFFFF0F7),
    screenOff: Color(0xFFE7A3C4),
    screenInk: Color(0xFFB0125E),
    screenDim: Color(0xFFC95B94),
    me: Color(0xFFD6247A),
    them: Color(0xFF7B4AE2),
    keyBg: Color(0xFFFFF6FB),
    keyInk: Color(0xFFD6247A),
    keySub: Color(0xFF9C3F77),
    keyRadius: BorderRadius.all(Radius.circular(26)),
    softBg: Color(0xFFC7A6FF),
    softInk: Color(0xFF7A1F52),
    focus: Color(0xFF7B4AE2),
    splash: '♥ hi cutie',
    bow: true,
    strap: [Color(0xFFFFFFFF), Color(0xFFFF4FA3), Color(0xFFC7A6FF), Color(0xFFFFF176)],
  ),
  PhoneTheme(
    id: 'gyaru',
    name: 'Gyaru',
    blurb: 'Gold leopard decoden flip',
    flip: true,
    ink: Color(0xFF1A0A12),
    body: Color(0xFFE3A948),
    pattern: BodyPattern.leopard,
    lid: Color(0xFFFF2E93),
    shell: Color(0xFFE3A948),
    shellPattern: BodyPattern.leopard,
    hinge: Color(0xFFFFD76A),
    screenOn: Color(0xFF12030B),
    screenOff: Color(0xFF050104),
    screenInk: Color(0xFFFF7CC8),
    screenDim: Color(0xFFC96AA1),
    me: Color(0xFFFFD76A),
    them: Color(0xFFFF7CC8),
    keyBg: Color(0xFF1A0A12),
    keyInk: Color(0xFFFFD76A),
    keySub: Color(0xFFFF8FD0),
    keyRadius: BorderRadius.all(Radius.circular(18)),
    keyInset: Color(0xFFFF2E93),
    softBg: Color(0xFFFFD76A),
    softInk: Color(0xFF1A0A12),
    focus: Color(0xFFFFFFFF),
    splash: 'gal mode ✦',
    heartAntenna: true,
    rhinestones: true,
    strap: [Color(0xFFFF2E93), Color(0xFFFFD76A), Color(0xFFFFFFFF), Color(0xFF1A0A12)],
  ),
  PhoneTheme(
    id: 'wideflip',
    name: 'Wide Flip',
    blurb: 'Keypad phone that opens the long way to a keyboard',
    device: Device.wideFlip,
    ink: Color(0xFF0E1116),
    body: Color(0xFF3B414B),
    lid: Color(0xFF3B414B),
    shell: Color(0xFF2A2E35),
    hinge: Color(0xFF9AA3AF),
    screenOn: Color(0xFFE8F1FF),
    screenOff: Color(0xFF3E4A5C),
    screenInk: Color(0xFF0B1B33),
    screenDim: Color(0xFF3A5478),
    me: Color(0xFF0B5CD6),
    them: Color(0xFFC0392B),
    keyBg: Color(0xFF1C2027),
    keyInk: Color(0xFFFFFFFF),
    keySub: Color(0xFF9FB3C8),
    keyRadius: BorderRadius.all(Radius.circular(12)),
    softBg: Color(0xFF7FB6FF),
    softInk: Color(0xFF0E1116),
    focus: Color(0xFFFFC233),
  ),
  PhoneTheme(
    id: 'dashboard',
    name: 'Console TV',
    blurb: 'Glowing green console keyboard under a tube TV',
    device: Device.dashboard,
    ink: Color(0xFF041004),
    body: Color(0xFF2A2A2E),
    screenOn: Color(0xFF031003),
    screenOff: Color(0xFF000000),
    screenInk: Color(0xFF8CFF5A),
    screenDim: Color(0xFF4CB832),
    me: Color(0xFFE8FFD0),
    them: Color(0xFF8CFF5A),
    mono: true,
    glow: true,
    keyBg: Color(0xFF3FA51F),
    keyInk: Color(0xFFFFFFFF),
    keySub: Color(0xFFB8F58F),
    softBg: Color(0xFF8CFF5A),
    softInk: Color(0xFF041004),
    focus: Color(0xFFD8FF7A),
    splash: 'AIM',
    sendHint: 'DONE sends · X deletes',
  ),
  PhoneTheme(
    id: 'pocketmail',
    name: 'Pocket Mail',
    blurb: 'Thumb keyboard and a trackball',
    device: Device.pocketMail,
    ink: Color(0xFF0B0C0F),
    body: Color(0xFF2D3038),
    screenOn: Color(0xFFF2F6FA),
    screenOff: Color(0xFF39414D),
    screenInk: Color(0xFF14202E),
    screenDim: Color(0xFF5A6B80),
    me: Color(0xFF1565C0),
    them: Color(0xFF2E7D32),
    keyBg: Color(0xFF15161A),
    keyInk: Color(0xFFFFFFFF),
    keySub: Color(0xFF8FA3B8),
    keyRadius: BorderRadius.all(Radius.circular(10)),
    softBg: Color(0xFFB8BEC8),
    softInk: Color(0xFF0B0C0F),
    focus: Color(0xFF5AB2FF),
    splash: 'aim mail',
    sendHint: 'Send ▸ green key or ⏎',
  ),
  PhoneTheme(
    id: 'musicplayer',
    name: 'Music Player',
    blurb: 'Click-wheel player; a white keyboard slides up',
    device: Device.musicPlayer,
    ink: Color(0xFF8E929A),
    body: Color(0xFFF7F7F5),
    screenOn: Color(0xFFDDE7EF),
    screenOff: Color(0xFF6B7682),
    screenInk: Color(0xFF1B2733),
    screenDim: Color(0xFF5B6F82),
    me: Color(0xFF1F6FD1),
    them: Color(0xFF1B2733),
    keyBg: Color(0xFFFFFFFF),
    keyInk: Color(0xFF3A3C42),
    keySub: Color(0xFF8E929A),
    softBg: Color(0xFFE6E7EA),
    softInk: Color(0xFF3A3C42),
    focus: Color(0xFF3B82F6),
    splash: 'aim',
    sendHint: 'return ⏎ sends',
  ),
  PhoneTheme(
    id: 'pocketbrick',
    name: 'Pocket Brick',
    blurb: 'Chunky green-screen handheld',
    device: Device.pocketBrick,
    ink: Color(0xFF2B2A2E),
    body: Color(0xFFCBC7BD),
    screenOn: Color(0xFF9BBC0F),
    screenOff: Color(0xFF7B8650),
    screenInk: Color(0xFF0F380F),
    screenDim: Color(0xFF306230),
    me: Color(0xFF0F380F),
    them: Color(0xFF306230),
    mono: true,
    keyBg: Color(0xFFC4CFA1),
    keyInk: Color(0xFF0F380F),
    keySub: Color(0xFF306230),
    softBg: Color(0xFF9A2257),
    softInk: Color(0xFFFFFFFF),
    focus: Color(0xFF0F380F),
    splash: 'AIM',
    sendHint: 'START or ED sends',
  ),

  // ---------------------------------------------------------- second batch
  PhoneTheme(
    id: 'swivel',
    name: 'Swivel',
    blurb: 'Orange music phone; the top spins round to show the keys',
    device: Device.swivel,
    ink: Color(0xFF101418),
    body: Color(0xFFFF7A1A),
    screenOn: Color(0xFFE9F6FF),
    screenOff: Color(0xFF26313B),
    screenInk: Color(0xFF0E2233),
    screenDim: Color(0xFF4E6A84),
    me: Color(0xFFE5484D),
    them: Color(0xFF0B6BCB),
    keyBg: Color(0xFFF4F6F8),
    keyInk: Color(0xFF101418),
    keySub: Color(0xFF5A6672),
    keyRadius: BorderRadius.all(Radius.circular(12)),
    softBg: Color(0xFFFFD9B8),
    softInk: Color(0xFF101418),
    focus: Color(0xFF0B6BCB),
    splash: 'aim ♪',
    strap: [Color(0xFFFF7A1A), Color(0xFFFFFFFF), Color(0xFF101418), Color(0xFFFFC08A)],
  ),
  PhoneTheme(
    id: 'poptilt',
    name: 'Pop-Tilt',
    blurb: 'Messenger whose screen pops up over a thumb keyboard',
    device: Device.popTilt,
    ink: Color(0xFF121418),
    body: Color(0xFF3FB8A8),
    screenOn: Color(0xFFEAF7FF),
    screenOff: Color(0xFF1E3340),
    screenInk: Color(0xFF0F2437),
    screenDim: Color(0xFF4B6A86),
    me: Color(0xFF0B6BCB),
    them: Color(0xFFC2185B),
    keyBg: Color(0xFF2A2E35),
    keyInk: Color(0xFFFFFFFF),
    keySub: Color(0xFF9FB3C8),
    keyRadius: BorderRadius.all(Radius.circular(10)),
    softBg: Color(0xFF7CE0D2),
    softInk: Color(0xFF121418),
    focus: Color(0xFFFFC233),
    splash: 'aim',
    sendHint: 'Send ▸ green key or ⏎',
  ),
  PhoneTheme(
    id: 'compact',
    name: 'Compact',
    blurb: 'Round mirror compact; keys in a ring round a big 5',
    flip: true,
    device: Device.compact,
    ink: Color(0xFF5A1E3C),
    body: Color(0xFFE9C25A),
    lid: Color(0xFFE8A3BC),
    shell: Color(0xFFE9C25A),
    hinge: Color(0xFFE9C25A),
    screenOn: Color(0xFFFFF6FA),
    screenOff: Color(0xFFC995AE),
    screenInk: Color(0xFF8A2752),
    screenDim: Color(0xFFC27A98),
    me: Color(0xFFD6247A),
    them: Color(0xFF6B4BD6),
    keyBg: Color(0xFFFFF8E8),
    keyInk: Color(0xFF8A2752),
    keySub: Color(0xFFB0657F),
    keyRadius: BorderRadius.all(Radius.circular(999)),
    softBg: Color(0xFFF4D27A),
    softInk: Color(0xFF5A1E3C),
    focus: Color(0xFF6B4BD6),
    splash: '✿ hey gorgeous',
    strap: [Color(0xFFFFFFFF), Color(0xFFE9C25A), Color(0xFFF7C6D6)],
  ),
  PhoneTheme(
    id: 'taco',
    name: 'Taco',
    blurb: 'Sideways game phone: D-pad left, keys right',
    device: Device.taco,
    ink: Color(0xFF0E1A12),
    body: Color(0xFF3B6B44),
    screenOn: Color(0xFFC9E4A8),
    screenOff: Color(0xFF3F5434),
    screenInk: Color(0xFF163018),
    screenDim: Color(0xFF3E6B42),
    me: Color(0xFF163018),
    them: Color(0xFF163018),
    mono: true,
    keyBg: Color(0xFFDDE7D6),
    keyInk: Color(0xFF0E1A12),
    keySub: Color(0xFF46604F),
    keyRadius: BorderRadius.all(Radius.circular(12)),
    softBg: Color(0xFFB8F04A),
    softInk: Color(0xFF0E1A12),
    focus: Color(0xFFFFE066),
    splash: 'GAME ON',
  ),
  PhoneTheme(
    id: 'lipstick',
    name: 'Lipstick',
    blurb: 'Mirror stick; spin the wheel to pick letters',
    device: Device.lipstick,
    ink: Color(0xFF1A0710),
    body: Color(0xFFC21845),
    screenOn: Color(0xFF2A0812),
    screenOff: Color(0xFF0E0206),
    screenInk: Color(0xFFFF3B6B),
    screenDim: Color(0xFFC9506F),
    me: Color(0xFFFFB3C6),
    them: Color(0xFFFF3B6B),
    mono: true,
    glow: true,
    keyBg: Color(0xFFF6DC8A),
    keyInk: Color(0xFF1A0710),
    keySub: Color(0xFF7A5A14),
    keyRadius: BorderRadius.all(Radius.circular(14)),
    softBg: Color(0xFFFFE1E9),
    softInk: Color(0xFF1A0710),
    focus: Color(0xFFFFFFFF),
    splash: 'rouge ♥',
    sendHint: 'spin · OK types · Send',
  ),
  PhoneTheme(
    id: 'pager',
    name: 'Two-Way Pager',
    blurb: 'Belt-clip pager; the lid opens over a tiny keyboard',
    device: Device.pager,
    ink: Color(0xFF0B0D10),
    body: Color(0xFF454C57),
    screenOn: Color(0xFFB9C8A6),
    screenOff: Color(0xFF4A5640),
    screenInk: Color(0xFF16210F),
    screenDim: Color(0xFF47573A),
    me: Color(0xFF16210F),
    them: Color(0xFF16210F),
    mono: true,
    keyBg: Color(0xFF2B2F36),
    keyInk: Color(0xFFE6F0FF),
    keySub: Color(0xFF8FA3B8),
    keyRadius: BorderRadius.all(Radius.circular(8)),
    softBg: Color(0xFF5AA9FF),
    softInk: Color(0xFF0B0D10),
    focus: Color(0xFF5AA9FF),
    splash: '2-WAY',
    sendHint: 'Send ▸ green key or ⏎',
  ),
  PhoneTheme(
    id: 'cordless',
    name: 'Clear Cordless',
    blurb: 'See-through house phone with neon guts',
    device: Device.cordless,
    ink: Color(0xFF141B2E),
    body: Color(0xFF7FE8C8),
    screenOn: Color(0xFFFFE39A),
    screenOff: Color(0xFF5E5230),
    screenInk: Color(0xFF3A2600),
    screenDim: Color(0xFF8A6A20),
    me: Color(0xFF3A2600),
    them: Color(0xFF3A2600),
    mono: true,
    keyBg: Color(0xB3FFFFFF),
    keyInk: Color(0xFF0C3B2E),
    keySub: Color(0xFF2F6F57),
    keyRadius: BorderRadius.only(
        topLeft: Radius.circular(14), topRight: Radius.circular(14),
        bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
    keyInset: Color(0xFF7CFFB2),
    softBg: Color(0xFF7CFFB2),
    softInk: Color(0xFF141B2E),
    focus: Color(0xFFFF4FA3),
    splash: 'ring ring',
    sendHint: 'TALK sends',
  ),
  PhoneTheme(
    id: 'watch',
    name: 'Calculator Watch',
    blurb: 'Databank watch; T9 on calculator keys',
    device: Device.watch,
    ink: Color(0xFF0E0F12),
    body: Color(0xFF9EA2AA),
    screenOn: Color(0xFFB8C2A2),
    screenOff: Color(0xFF4C5440),
    screenInk: Color(0xFF1A1F12),
    screenDim: Color(0xFF4D5640),
    me: Color(0xFF1A1F12),
    them: Color(0xFF1A1F12),
    mono: true,
    keyBg: Color(0xFF2A2C31),
    keyInk: Color(0xFFF2F2F2),
    keySub: Color(0xFFF5A623),
    keyRadius: BorderRadius.all(Radius.circular(8)),
    softBg: Color(0xFFF5A623),
    softInk: Color(0xFF0E0F12),
    focus: Color(0xFFF5A623),
    splash: 'DATA BANK',
    sendHint: 'SEND key sends',
  ),
  PhoneTheme(
    id: 'rotator',
    name: 'Rotator',
    blurb: 'Candybar whose screen twists sideways',
    device: Device.rotator,
    ink: Color(0xFF121621),
    body: Color(0xFF9C86F0),
    screenOn: Color(0xFF0C1A33),
    screenOff: Color(0xFF050A14),
    screenInk: Color(0xFF9AD8FF),
    screenDim: Color(0xFF4D7FB0),
    me: Color(0xFFFFD166),
    them: Color(0xFF9AD8FF),
    keyBg: Color(0xFFF7F9FC),
    keyInk: Color(0xFF18315A),
    keySub: Color(0xFF5A6F8E),
    keyRadius: BorderRadius.all(Radius.circular(16)),
    softBg: Color(0xFF9AD8FF),
    softInk: Color(0xFF121621),
    focus: Color(0xFFFFD166),
    splash: 'wide ↻',
  ),
  PhoneTheme(
    id: 'jelly',
    name: 'Jelly Slider',
    blurb: 'Squishy see-through gummy slider',
    device: Device.jelly,
    ink: Color(0xFF0F5B4A),
    body: Color(0xFF5FE0B8),
    screenOn: Color(0xFFF2FFF9),
    screenOff: Color(0xFF7FB8A6),
    screenInk: Color(0xFF0F5B4A),
    screenDim: Color(0xFF4FA88E),
    me: Color(0xFFE0407A),
    them: Color(0xFF0F7F68),
    keyBg: Color(0xB3FFFFFF),
    keyInk: Color(0xFF0F5B4A),
    keySub: Color(0xFF2E8A72),
    keyRadius: BorderRadius.all(Radius.circular(999)),
    softBg: Color(0xFFFFE066),
    softInk: Color(0xFF0F5B4A),
    focus: Color(0xFFE0407A),
    splash: 'squish!',
    strap: [Color(0xFFFF7AB6), Color(0xFFFFE066), Color(0xFF7CE0FF), Color(0xFFB8FF7A)],
  ),
  PhoneTheme(
    id: 'eggpet',
    name: 'Egg Pet',
    blurb: 'Keychain pet egg; three buttons pick letters',
    device: Device.eggPet,
    ink: Color(0xFF3A1F5C),
    body: Color(0xFFC79BFF),
    pattern: BodyPattern.dots,
    screenOn: Color(0xFFC8D8A8),
    screenOff: Color(0xFF7E8A68),
    screenInk: Color(0xFF2A3A1A),
    screenDim: Color(0xFF55663F),
    me: Color(0xFF2A3A1A),
    them: Color(0xFF2A3A1A),
    mono: true,
    keyBg: Color(0xFFF4E6FF),
    keyInk: Color(0xFF3A1F5C),
    keySub: Color(0xFF7A5A9C),
    keyRadius: BorderRadius.all(Radius.circular(20)),
    softBg: Color(0xFF7CE0FF),
    softInk: Color(0xFF3A1F5C),
    focus: Color(0xFFFF7AB6),
    splash: '(•ᴗ•)',
    sendHint: '◀▶ pick · TYPE · SEND',
  ),
  PhoneTheme(
    id: 'widet9',
    name: 'Wide T9',
    blurb: 'Two rows of eight keys for two thumbs',
    device: Device.wideT9,
    ink: Color(0xFF1B1530),
    body: Color(0xFF5DB4F0),
    screenOn: Color(0xFFDFF3FF),
    screenOff: Color(0xFF4A6A88),
    screenInk: Color(0xFF10243A),
    screenDim: Color(0xFF4A6A88),
    me: Color(0xFFD6247A),
    them: Color(0xFF1F5FC0),
    keyBg: Color(0xFFFFF7E6),
    keyInk: Color(0xFF1B1530),
    keySub: Color(0xFF6A5A8A),
    keyRadius: BorderRadius.all(Radius.circular(16)),
    softBg: Color(0xFFFFC94D),
    softInk: Color(0xFF1B1530),
    focus: Color(0xFFD6247A),
  ),
];

PhoneTheme phoneThemeById(String id) => kPhoneThemes.firstWhere((t) => t.id == id, orElse: () => kPhoneThemes.first);

// ------------------------------------------------------------------ painting

/// A phone shell: fill (+ pattern), thick ink outline, hard offset shadow.
class ShellBox extends StatelessWidget {
  final Color color;
  final BodyPattern pattern;
  final Color ink;
  final BorderRadius radius;
  final Widget? child;
  final EdgeInsets padding;
  final bool shadow;
  final bool shine;
  const ShellBox({
    super.key,
    required this.color,
    required this.ink,
    required this.radius,
    this.pattern = BodyPattern.plain,
    this.child,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
    this.shine = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: Border.all(color: ink, width: 5),
        boxShadow: shadow
            ? const [
                // soft drop shadow so the phone reads as floating over the chat
                BoxShadow(color: Color(0x59000000), blurRadius: 34, spreadRadius: 2, offset: Offset(0, 16)),
                BoxShadow(color: Color(0x38000000), offset: Offset(12, 12)),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(children: [
          if (pattern != BodyPattern.plain)
            Positioned.fill(child: CustomPaint(painter: PatternPainter(pattern, color))),
          if (shine) const Positioned(left: 18, top: 16, child: Shine()),
          Padding(padding: padding, child: child ?? const SizedBox.expand()),
        ]),
      ),
    );
  }
}

class PatternPainter extends CustomPainter {
  final BodyPattern pattern;
  final Color base;
  PatternPainter(this.pattern, this.base);

  @override
  void paint(Canvas c, Size s) {
    switch (pattern) {
      case BodyPattern.dots:
        final p = Paint()..color = const Color(0xD9FFFFFF);
        for (var y = 17.0; y < s.height + 17; y += 34) {
          for (var x = 17.0; x < s.width + 17; x += 34) {
            c.drawCircle(Offset(x, y), 5.5, p);
          }
        }
      case BodyPattern.leopard:
        final rnd = Random(7);
        final n = (s.width * s.height / 2400).clamp(10, 140).toInt();
        for (var i = 0; i < n; i++) {
          final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
          final r = rnd.nextDouble() * 5 + 6;
          final rect = Rect.fromCenter(center: o, width: r * 2.3, height: r * 1.7);
          c.drawOval(rect, Paint()..color = const Color(0xFFB8742A));
          c.drawArc(rect, rnd.nextDouble() * 3, 4.2, false, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF3B2412));
        }
      case BodyPattern.plain:
        break;
    }
  }

  @override
  bool shouldRepaint(PatternPainter old) => old.pattern != pattern || old.base != base;
}

/// White shine marks in the top-left corner of a shell.
class Shine extends StatelessWidget {
  final Color color;
  const Shine({super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 14, height: 52, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7))),
        const SizedBox(width: 6),
        Container(width: 8, height: 22, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      ]),
    );
  }
}

/// Things that stick out of the top of the phone: antenna, bow, heart antenna.
/// Drawn in a box [width] wide and 60 tall, sitting right on the phone's top edge.
class TopDecor extends StatelessWidget {
  final PhoneTheme t;
  final double width;
  final Color stickColor;
  const TopDecor({super.key, required this.t, required this.width, required this.stickColor});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (t.antennaBall != null) {
      children.add(Positioned(
        right: 48,
        bottom: -6,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: t.antennaBall, shape: BoxShape.circle, border: Border.all(color: t.ink, width: 4)),
          ),
          Container(
            width: 18,
            height: 40,
            margin: const EdgeInsets.only(top: 0),
            decoration: BoxDecoration(color: stickColor, borderRadius: BorderRadius.circular(9), border: Border.all(color: t.ink, width: 4)),
          ),
        ]),
      ));
    }
    if (t.heartAntenna) {
      children.add(Positioned(
        right: 46,
        bottom: -6,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CustomPaint(size: const Size(40, 36), painter: HeartPainter(const Color(0xFFFFD76A), t.ink)),
          Container(
            width: 18,
            height: 26,
            decoration: BoxDecoration(
                color: const Color(0xFFFF2E93), borderRadius: BorderRadius.circular(9), border: Border.all(color: t.ink, width: 4)),
          ),
        ]),
      ));
    }
    if (t.bow) {
      children.add(Positioned(
        left: width / 2 - 55,
        bottom: -14,
        child: CustomPaint(size: const Size(110, 60), painter: BowPainter(const Color(0xFFFF4FA3), t.ink)),
      ));
    }
    return SizedBox(width: width, height: 60, child: Stack(clipBehavior: Clip.none, children: children));
  }
}

class HeartPainter extends CustomPainter {
  final Color fill, ink;
  final double stroke;
  HeartPainter(this.fill, this.ink, {this.stroke = 3.5});

  static Path heart(Size s) {
    final w = s.width, h = s.height;
    return Path()
      ..moveTo(w / 2, h * 0.95)
      ..cubicTo(w * 0.1, h * 0.65, -w * 0.05, h * 0.25, w * 0.25, h * 0.08)
      ..cubicTo(w * 0.4, 0, w * 0.5, h * 0.12, w / 2, h * 0.25)
      ..cubicTo(w * 0.5, h * 0.12, w * 0.6, 0, w * 0.75, h * 0.08)
      ..cubicTo(w * 1.05, h * 0.25, w * 0.9, h * 0.65, w / 2, h * 0.95)
      ..close();
  }

  @override
  void paint(Canvas c, Size s) {
    final p = heart(s);
    c.drawPath(p, Paint()..color = fill);
    c.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..color = ink);
  }

  @override
  bool shouldRepaint(HeartPainter old) => old.fill != fill || old.ink != ink;
}

class BowPainter extends CustomPainter {
  final Color fill, ink;
  BowPainter(this.fill, this.ink);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    final fillP = Paint()..color = fill;
    final left = Path()
      ..moveTo(w / 2, h / 2)
      ..quadraticBezierTo(w * 0.15, -h * 0.05, w * 0.04, h * 0.3)
      ..quadraticBezierTo(0, h * 0.75, w / 2, h / 2)
      ..close();
    final right = Path()
      ..moveTo(w / 2, h / 2)
      ..quadraticBezierTo(w * 0.85, -h * 0.05, w * 0.96, h * 0.3)
      ..quadraticBezierTo(w, h * 0.75, w / 2, h / 2)
      ..close();
    for (final p in [left, right]) {
      c.drawPath(p, fillP);
      c.drawPath(p, stroke);
    }
    final knot = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w / 2, h / 2), width: 22, height: 22), const Radius.circular(7));
    c.drawRRect(knot, fillP);
    c.drawRRect(knot, stroke);
  }

  @override
  bool shouldRepaint(BowPainter old) => false;
}

/// Bead phone strap hanging off the side, with a heart charm.
class Strap extends StatelessWidget {
  final List<Color> colors;
  final Color ink;
  const Strap({super.key, required this.colors, required this.ink});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 16, decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(3))),
      for (var i = 0; i < 9; i++)
        Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(top: 0),
          decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle, border: Border.all(color: ink, width: 2)),
        ),
      CustomPaint(size: const Size(40, 36), painter: HeartPainter(colors.length > 1 ? colors[1] : colors[0], ink)),
    ]);
  }
}

/// Rhinestones around the edge of a box.
class RhinestonePainter extends CustomPainter {
  final Color ink;
  RhinestonePainter(this.ink);

  @override
  void paint(Canvas c, Size s) {
    const cols = [Color(0xFFFFFFFF), Color(0xFFFFD76A), Color(0xFFFF9AD5)];
    const step = 17.0;
    var i = 0;
    void stone(Offset o) {
      c.drawCircle(o, 6, Paint()..color = cols[i++ % cols.length]);
      c.drawCircle(o, 6, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink);
    }

    for (var x = 12.0; x < s.width - 8; x += step) {
      stone(Offset(x, 10));
      stone(Offset(x, s.height - 10));
    }
    for (var y = 10 + step; y < s.height - 10 - 4; y += step) {
      stone(Offset(10, y));
      stone(Offset(s.width - 10, y));
    }
  }

  @override
  bool shouldRepaint(RhinestonePainter old) => false;
}

/// See-through bubbles inside the Ice phone.
class BubblesDecor extends StatelessWidget {
  const BubblesDecor({super.key});

  @override
  Widget build(BuildContext context) {
    Widget b(double s) => Container(
          width: s,
          height: s,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xCCFFFFFF), width: 3)),
        );
    return Stack(children: [
      Positioned(right: 24, top: 300, child: b(22)),
      Positioned(right: 14, top: 276, child: b(12)),
      Positioned(left: 10, top: 380, child: b(16)),
      Positioned(right: 20, bottom: 40, child: b(18)),
    ]);
  }
}
