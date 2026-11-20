import 'dart:typed_data';

/// LZX decompressor for Microsoft Cabinet folders (compression type 3).
/// Port of a reference implementation that was checked byte-for-byte against
/// libarchive on the AIM 5.1 installer.

final List<int> _extraBits = () {
  final eb = List<int>.filled(52, 0);
  var j = 0;
  for (var i = 0; i < 52; i += 2) {
    eb[i] = j;
    eb[i + 1] = j;
    if (i != 0 && j < 17) j++;
  }
  return eb;
}();

final List<int> _positionBase = () {
  final pb = List<int>.filled(52, 0);
  for (var i = 1; i < 52; i++) {
    pb[i] = pb[i - 1] + (1 << _extraBits[i - 1]);
  }
  return pb;
}();

const Map<int, int> _positionSlots = {15: 30, 16: 32, 17: 34, 18: 36, 19: 38, 20: 42, 21: 50};

class LzxFormatException implements Exception {
  final String message;
  LzxFormatException(this.message);
  @override
  String toString() => 'LZX: $message';
}

class _Bits {
  final Uint8List d;
  int p = 0;
  int buf = 0;
  int n = 0;
  _Bits(this.d);

  void fill(int need) {
    while (n < need) {
      final w = (p + 1 < d.length) ? (d[p] | (d[p + 1] << 8)) : 0;
      p += 2;
      buf = ((buf << 16) | w) & 0xffffffffffff;
      n += 16;
    }
  }

  int peek(int k) {
    fill(k);
    return (buf >> (n - k)) & ((1 << k) - 1);
  }

  void drop(int k) {
    n -= k;
    buf &= (1 << n) - 1;
  }

  int read(int k) {
    if (k == 0) return 0;
    final v = peek(k);
    drop(k);
    return v;
  }

  void align16() => drop(n & 15);

  void alignUncompressed() {
    if ((n & 15) != 0) {
      drop(n & 15);
    } else if (n == 0) {
      fill(16);
      drop(16);
    } else if (n >= 16) {
      drop(16);
    }
    p -= n ~/ 8;
    buf = 0;
    n = 0;
  }
}

class _Huff {
  int maxLen = 0;
  Int32List? table; // (symbol << 5) | length, -1 = invalid

  _Huff(List<int> lens) {
    for (final l in lens) {
      if (l > maxLen) maxLen = l;
    }
    if (maxLen == 0) return;
    final t = Int32List(1 << maxLen)..fillRange(0, 1 << maxLen, -1);
    var code = 0;
    for (var len = 1; len <= maxLen; len++) {
      for (var sym = 0; sym < lens.length; sym++) {
        if (lens[sym] == len) {
          final start = code << (maxLen - len);
          final end = start + (1 << (maxLen - len));
          if (end > t.length) throw LzxFormatException('oversubscribed tree');
          for (var k = start; k < end; k++) {
            t[k] = (sym << 5) | len;
          }
          code++;
        }
      }
      code <<= 1;
    }
    table = t;
  }

  int decode(_Bits b) {
    final t = table;
    if (t == null) throw LzxFormatException('empty tree');
    final e = t[b.peek(maxLen)];
    if (e < 0) throw LzxFormatException('bad code');
    b.drop(e & 31);
    return e >> 5;
  }
}

void _readLens(_Bits b, List<int> lens, int first, int last) {
  final pre = List<int>.generate(20, (_) => b.read(4));
  final pt = _Huff(pre);
  var x = first;
  while (x < last) {
    var z = pt.decode(b);
    if (z == 17) {
      final y = b.read(4) + 4;
      for (var i = 0; i < y && x < lens.length; i++) {
        lens[x++] = 0;
      }
    } else if (z == 18) {
      final y = b.read(5) + 20;
      for (var i = 0; i < y && x < lens.length; i++) {
        lens[x++] = 0;
      }
    } else if (z == 19) {
      final y = b.read(1) + 4;
      z = pt.decode(b);
      var v = lens[x] - z;
      if (v < 0) v += 17;
      for (var i = 0; i < y && x < lens.length; i++) {
        lens[x++] = v;
      }
    } else {
      var v = lens[x] - z;
      if (v < 0) v += 17;
      lens[x++] = v;
    }
  }
}

Uint8List lzxDecompress(Uint8List data, int windowBits, int outLen) {
  final slots = _positionSlots[windowBits];
  if (slots == null) throw LzxFormatException('unsupported window $windowBits');
  final wsize = 1 << windowBits;
  final wmask = wsize - 1;
  final win = Uint8List(wsize);
  var wpos = 0;
  final mainElems = 256 + slots * 8;
  final mainLens = List<int>.filled(mainElems, 0);
  final lenLens = List<int>.filled(249, 0);
  var r0 = 1, r1 = 1, r2 = 1;
  final b = _Bits(data);
  final out = Uint8List(outLen);
  var outPos = 0;

  var intelSize = 0;
  if (b.read(1) == 1) {
    final hi = b.read(16);
    final lo = b.read(16);
    intelSize = (hi << 16) | lo;
  }

  var blockType = 0;
  var blockLen = 0;
  var remaining = 0;
  _Huff? mainT, lenT, alT;
  var frame = 0;

  while (outPos < outLen) {
    final frameSize = (outLen - outPos) < 32768 ? (outLen - outPos) : 32768;
    final frameStart = wpos;
    var produced = 0;
    while (produced < frameSize) {
      if (remaining == 0) {
        if (blockType == 3 && (blockLen & 1) == 1) b.p += 1;
        blockType = b.read(3);
        blockLen = (b.read(16) << 8) | b.read(8);
        remaining = blockLen;
        if (blockType == 2) {
          alT = _Huff(List<int>.generate(8, (_) => b.read(3)));
        }
        if (blockType == 1 || blockType == 2) {
          _readLens(b, mainLens, 0, 256);
          _readLens(b, mainLens, 256, mainElems);
          mainT = _Huff(mainLens);
          _readLens(b, lenLens, 0, 249);
          lenT = _Huff(lenLens);
        } else if (blockType == 3) {
          b.alignUncompressed();
          final bd = ByteData.sublistView(data);
          r0 = bd.getUint32(b.p, Endian.little);
          r1 = bd.getUint32(b.p + 4, Endian.little);
          r2 = bd.getUint32(b.p + 8, Endian.little);
          b.p += 12;
        } else {
          throw LzxFormatException('bad block type $blockType');
        }
        if (remaining == 0) continue;
      }
      final thisRun = remaining < (frameSize - produced) ? remaining : (frameSize - produced);
      if (blockType == 3) {
        for (var i = 0; i < thisRun; i++) {
          win[wpos] = data[b.p++];
          wpos = (wpos + 1) & wmask;
        }
        produced += thisRun;
        remaining -= thisRun;
        continue;
      }
      var run = thisRun;
      final mt = mainT!;
      final lt = lenT!;
      while (run > 0) {
        var m = mt.decode(b);
        if (m < 256) {
          win[wpos] = m;
          wpos = (wpos + 1) & wmask;
          run--;
          continue;
        }
        m -= 256;
        var mlen = m & 7;
        if (mlen == 7) mlen += lt.decode(b);
        mlen += 2;
        final slot = m >> 3;
        int off;
        if (slot == 0) {
          off = r0;
        } else if (slot == 1) {
          off = r1;
          r1 = r0;
          r0 = off;
        } else if (slot == 2) {
          off = r2;
          r2 = r0;
          r0 = off;
        } else {
          final eb = _extraBits[slot];
          off = _positionBase[slot] - 2;
          if (blockType == 2) {
            if (eb > 3) {
              off += b.read(eb - 3) << 3;
              off += alT!.decode(b);
            } else if (eb == 3) {
              off += alT!.decode(b);
            } else if (eb > 0) {
              off += b.read(eb);
            }
          } else {
            off += b.read(eb);
          }
          r2 = r1;
          r1 = r0;
          r0 = off;
        }
        var src = (wpos - off) & wmask;
        for (var i = 0; i < mlen; i++) {
          win[wpos] = win[src];
          wpos = (wpos + 1) & wmask;
          src = (src + 1) & wmask;
        }
        run -= mlen;
      }
      final used = thisRun - run;
      produced += used;
      remaining -= used;
    }
    if (produced > frameSize) throw LzxFormatException('match crossed frame boundary');

    final fb = Uint8List.fromList(Uint8List.sublistView(win, frameStart, frameStart + frameSize));
    if (intelSize != 0 && frameSize > 10 && frame < 32768) {
      final bd = ByteData.sublistView(fb);
      final base = frame * 32768;
      var i = 0;
      while (i < frameSize - 10) {
        if (fb[i] == 0xe8) {
          final abs = bd.getInt32(i + 1, Endian.little);
          final cur = base + i;
          if (-cur <= abs && abs < intelSize) {
            final rel = abs >= 0 ? abs - cur : abs + intelSize;
            bd.setInt32(i + 1, rel, Endian.little);
          }
          i += 5;
        } else {
          i++;
        }
      }
    }
    out.setRange(outPos, outPos + frameSize, fb);
    outPos += frameSize;
    frame++;
    b.align16();
  }
  return out;
}
