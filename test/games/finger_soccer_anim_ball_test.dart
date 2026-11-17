import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';

/// Canvas size of a VP8X (extended, with alpha) WebP file.
List<int> _webpSize(String path) {
  final Uint8List b = File(path).readAsBytesSync();
  expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(b.sublist(12, 16)), 'VP8X');
  int u24(int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
  return <int>[u24(24) + 1, u24(27) + 1];
}

void main() {
  test('animated balls use the GIF frame counts and exact GIF frame times', () {
    expect(kBmAnimBalls[36]!.frames, 12);
    expect(kBmAnimBalls[36]!.frameMs, 130);
    expect(kBmAnimBalls[37]!.frames, 9);
    expect(kBmAnimBalls[37]!.frameMs, 180);
  });

  test('sheets are 256 px per frame, one frame per GIF frame', () {
    for (final BmAnimBall a in kBmAnimBalls.values) {
      final List<int> wh = _webpSize(a.sheet);
      expect(wh[1], 256, reason: a.sheet);
      expect(wh[0], 256 * a.frames, reason: a.sheet);
    }
  });

  test('both animated balls are selectable', () {
    expect(kBmBallCount, NB + 2);
    expect(kBmBallN.length, greaterThanOrEqualTo(kBmBallCount));
    for (final int i in kBmAnimBalls.keys) {
      expect(i, lessThan(kBmBallCount));
      expect(File('assets/games/bermuda/balls/b$i.webp').existsSync(), isTrue);
    }
  });

  test('playback follows wall-clock time in GIF order and loops', () {
    expect(bmAnimFrame(0, 130, 12), 0);
    expect(bmAnimFrame(129.9, 130, 12), 0);
    expect(bmAnimFrame(130, 130, 12), 1);
    expect(bmAnimFrame(130.0 * 11, 130, 12), 11);
    expect(bmAnimFrame(130.0 * 12, 130, 12), 0);
    expect(bmAnimFrame(180.0 * 10, 180, 9), 1);
    expect(bmAnimFrame(-5, 180, 9), 0);
  });
}
