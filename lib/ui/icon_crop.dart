import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app/icons.dart';
import '../app/input_mode.dart';
import 'retro.dart';

/// Pick a picture with the system picker, then choose how it's cropped into a
/// 48×48 buddy icon. Pops with the encoded icon bytes.
class IconCropScreen extends StatefulWidget {
  const IconCropScreen({super.key});

  @override
  State<IconCropScreen> createState() => _IconCropScreenState();
}

enum _Mode { crop, fit }

class _IconCropScreenState extends State<IconCropScreen> {
  WorkingImage? _img;
  String? _error;
  bool _busy = false;
  _Mode _mode = _Mode.crop;
  int _bg = 0xffffffff;
  final _tc = TransformationController();
  double _viewport = 280;
  Uint8List? _result;
  late final InputMode _input;

  @override
  void initState() {
    super.initState();
    _input = context.read<InputMode>();
    _input.pushHandler(_onPad);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _input.removeHandler(_onPad);
    _tc.dispose();
    super.dispose();
  }

  /// Controller: X/Y zoom, D-pad pans while cropping.
  bool _onPad(PadAction a) {
    if (_img == null || _mode != _Mode.crop || _result != null) return false;
    const step = 12.0;
    switch (a) {
      case PadAction.x:
        _zoom(1.15);
        return true;
      case PadAction.y:
        _zoom(1 / 1.15);
        return true;
      case PadAction.lb:
        _pan(step, 0);
        return true;
      case PadAction.rb:
        _pan(-step, 0);
        return true;
      default:
        return false;
    }
  }

  void _zoom(double f) {
    final m = _tc.value.clone();
    final s = m.getMaxScaleOnAxis();
    final ns = (s * f).clamp(1.0, 8.0).toDouble();
    final c = _viewport / 2;
    final r = ns / s;
    m
      ..translate(c, c)
      ..scale(r, r)
      ..translate(-c, -c);
    _tc.value = m;
    _clampPan();
  }

  void _pan(double dx, double dy) {
    final m = _tc.value.clone()..translate(dx / _tc.value.getMaxScaleOnAxis(), dy / _tc.value.getMaxScaleOnAxis());
    _tc.value = m;
    _clampPan();
  }

  void _clampPan() {
    final img = _img;
    if (img == null) return;
    final m = _tc.value.clone();
    final s = m.getMaxScaleOnAxis();
    final k = _viewport / (img.width < img.height ? img.width : img.height);
    final cw = img.width * k * s, ch = img.height * k * s;
    final t = m.getTranslation();
    final tx = t.x.clamp(_viewport - cw, 0.0).toDouble();
    final ty = t.y.clamp(_viewport - ch, 0.0).toDouble();
    m.setTranslationRaw(tx, ty, 0);
    _tc.value = m;
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) {
        if (_img == null && mounted) Navigator.of(context).pop();
        return;
      }
      final bytes = await file.readAsBytes();
      final w = await loadWorkingImage(bytes);
      _tc.value = Matrix4.identity();
      setState(() {
        _img = w;
        _result = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open that picture: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _make() {
    final img = _img;
    if (img == null) return;
    Uint8List out;
    if (_mode == _Mode.fit) {
      out = makeFittedIcon(img, background: _bg);
    } else {
      final m = _tc.value;
      final s = m.getMaxScaleOnAxis();
      final t = m.getTranslation();
      final k = _viewport / (img.width < img.height ? img.width : img.height);
      final rect = ui.Rect.fromLTWH(-t.x / s / k, -t.y / s / k, _viewport / s / k, _viewport / s / k);
      out = makeCroppedIcon(img, rect);
    }
    setState(() => _result = out);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Desktop(
          maxWidth: 460,
          child: SingleChildScrollView(
            child: RetroWindow(
              title: 'Buddy Icon',
              onClose: () => Navigator.of(context).pop(),
              child: _result != null ? _confirm() : _editor(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor() {
    final img = _img;
    return LayoutBuilder(builder: (ctx, c) {
      _viewport = (c.maxWidth - 8).clamp(160.0, 320.0).toDouble();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (_error != null) Padding(padding: const EdgeInsets.all(6), child: Text(_error!)),
        if (img == null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(child: Text(_busy ? 'Opening picture…' : 'Choose a picture to start.')),
          )
        else ...[
          Row(children: [
            Expanded(
              child: RetroButton(
                autofocus: true,
                onPressed: () => setState(() => _mode = _Mode.crop),
                child: Text('Crop', style: TextStyle(fontWeight: _mode == _Mode.crop ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: RetroButton(
                onPressed: () => setState(() => _mode = _Mode.fit),
                child: Text('Fit whole picture',
                    style: TextStyle(fontWeight: _mode == _Mode.fit ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Center(
            child: Sunken(
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: _viewport,
                height: _viewport,
                child: _mode == _Mode.crop ? _cropView(img) : _fitView(img),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _mode == _Mode.crop
                ? 'Drag and pinch to frame your icon. Controller: X/Y zoom, LB/RB move.'
                : 'The whole picture is shrunk to fit, with a border.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          if (_mode == _Mode.fit)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final (label, color) in const [('White', 0xffffffff), ('Black', 0xff000000), ('Teal', 0xff008080)])
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: RetroButton(
                    minWidth: 0,
                    onPressed: () => setState(() => _bg = color),
                    child: Text(label, style: TextStyle(fontWeight: _bg == color ? FontWeight.bold : FontWeight.normal)),
                  ),
                ),
            ]),
        ],
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          RetroButton(onPressed: _busy ? null : _pick, child: const Text('Choose Picture…')),
          RetroButton(isDefault: true, onPressed: img == null ? null : _make, child: const Text('Next >')),
        ]),
      ]);
    });
  }

  Widget _cropView(WorkingImage img) {
    final k = _viewport / (img.width < img.height ? img.width : img.height);
    return ClipRect(
      child: Stack(children: [
        InteractiveViewer(
          transformationController: _tc,
          constrained: false,
          minScale: 1,
          maxScale: 8,
          boundaryMargin: EdgeInsets.zero,
          child: SizedBox(
            width: img.width * k,
            height: img.height * k,
            child: RawImage(image: img.preview, fit: BoxFit.fill),
          ),
        ),
        IgnorePointer(child: CustomPaint(size: Size(_viewport, _viewport), painter: _GridPainter())),
      ]),
    );
  }

  Widget _fitView(WorkingImage img) {
    return Container(
      color: Color(_bg),
      alignment: Alignment.center,
      child: RawImage(image: img.preview, fit: BoxFit.contain, width: _viewport, height: _viewport),
    );
  }

  Widget _confirm() {
    final r = _result!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('This is how your buddy icon will look:'),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        Column(children: [BuddyAvatar(bytes: r, size: 48), const Text('Actual size', style: TextStyle(fontSize: 12))]),
        Column(children: [BuddyAvatar(bytes: r, size: 96), const Text('Zoomed', style: TextStyle(fontSize: 12))]),
      ]),
      const SizedBox(height: 6),
      Text('48×48, ${(r.length / 1024).toStringAsFixed(1)} KB of 7 KB', textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        RetroButton(onPressed: () => setState(() => _result = null), child: const Text('< Back')),
        RetroButton(
            autofocus: true, isDefault: true, onPressed: () => Navigator.of(context).pop(r), child: const Text('Use Icon')),
      ]),
    ]);
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), p);
      canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), p);
    }
    canvas.drawRect(Offset.zero & size, p..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
