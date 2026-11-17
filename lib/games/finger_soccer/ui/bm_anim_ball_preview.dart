// Small looping preview of an animated sprite-sheet ball (ball picker / shop). Plays exactly like the owner's GIF:
// frames in order at the GIF's own frame time, upright, never rotated. Cheap: the sheet is decoded once (cached,
// downscaled), and the painter repaints only when the frame index changes (one drawImageRect).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/bm_data.dart';

class BmAnimBallPreview extends StatefulWidget {
  const BmAnimBallPreview({super.key, required this.ball, this.framePx = 112});

  final BmAnimBall ball;

  /// Decoded size of one frame (the sheet is decoded at frames * framePx wide).
  final int framePx;

  @override
  State<BmAnimBallPreview> createState() => _BmAnimBallPreviewState();
}

class _BmAnimBallPreviewState extends State<BmAnimBallPreview> with SingleTickerProviderStateMixin {
  static final Map<String, Future<ui.Image?>> _cache = <String, Future<ui.Image?>>{};

  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  ui.Image? _sheet;

  static Future<ui.Image?> _load(String path, int width) {
    return _cache.putIfAbsent('$path@$width', () async {
      try {
        final ByteData data = await rootBundle.load(path);
        final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
        final ui.FrameInfo f = await codec.getNextFrame();
        codec.dispose();
        return f.image;
      } catch (_) {
        return null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final ui.Image? im = await _load(widget.ball.sheet, widget.ball.frames * widget.framePx);
    if (!mounted || im == null) return;
    setState(() => _sheet = im);
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final int f = bmAnimFrame(elapsed.inMicroseconds / 1000, widget.ball.frameMs, widget.ball.frames);
    if (f != _frame.value) _frame.value = f;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? sheet = _sheet;
    if (sheet == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(painter: _SheetPainter(sheet, widget.ball.frames, _frame)),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter(this.sheet, this.frames, this.frame) : super(repaint: frame);

  final ui.Image sheet;
  final int frames;
  final ValueNotifier<int> frame;

  @override
  void paint(Canvas canvas, Size size) {
    final double fw = sheet.width / frames;
    canvas.drawImageRect(sheet, Rect.fromLTWH(frame.value * fw, 0, fw, sheet.height.toDouble()), Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_SheetPainter old) => old.sheet != sheet || old.frames != frames;
}
