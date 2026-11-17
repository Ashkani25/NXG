// Per-disc Power / Accuracy stats (rules change, Nov 2026, owner request).
//
// Every disc (team badge) in the catalog has two stable integer stats 1..10. They are derived
// from a seeded hash of the disc id, never rolled at runtime: same values on every launch, on
// every device and on both clients of an online match. Values are assigned by hash RANK over the
// catalog, so each stat is spread evenly over the whole 1..10 range (every value occurs).
//
// They change gameplay in BmEngine.fire():
//  * Power scales the shot speed linearly: 1 => x0.82 ... 10 => x1.18.
//  * Accuracy adds an aim deviation on release: 10 => 0 deg, 1 => up to +/-7 deg, scaled by the
//    shot strength; the deviation comes from a deterministic hash of (match seed, shot number,
//    piece id), and the deviated velocity is what goes into the online move payload.
import 'bm_engine.dart';

class BmDiscStats {
  const BmDiscStats(this.power, this.accuracy);
  final int power;
  final int accuracy;
}

const int kBmStatMin = 1, kBmStatMax = 10;
const double kBmPowerMinFactor = .82, kBmPowerMaxFactor = 1.18;
const double kBmMaxAimDeviationDeg = 7;

/// 32-bit FNV-1a of [s] with a [salt] (stable across runs and platforms of the VM).
int bmHash32(String s, int salt) {
  int h = (0x811C9DC5 ^ (salt & 0xFFFFFFFF)) & 0xFFFFFFFF;
  for (final int c in s.codeUnits) {
    h ^= c & 0xFF;
    h = (h * 0x01000193) & 0xFFFFFFFF;
    h ^= (c >> 8) & 0xFF;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  // final avalanche (murmur3 fmix32)
  h ^= h >> 16;
  h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
  h ^= h >> 13;
  h = (h * 0xC2B2AE35) & 0xFFFFFFFF;
  h ^= h >> 16;
  return h;
}

const int _kPowerSalt = 0x4E58504F; // "NXPO"
const int _kAccSalt = 0x4E584143; // "NXAC"

Map<String, int> _rankStat(List<String> ids, int salt) {
  final List<String> order = List<String>.from(ids)
    ..sort((String a, String b) {
      final int c = bmHash32(a, salt).compareTo(bmHash32(b, salt));
      return c != 0 ? c : a.compareTo(b);
    });
  final int n = order.length;
  return <String, int>{
    for (int i = 0; i < n; i++) order[i]: kBmStatMin + (i * (kBmStatMax - kBmStatMin + 1)) ~/ n,
  };
}

/// Stats of every disc in the catalog, by disc (team) id.
final Map<String, BmDiscStats> kBmDiscStats = () {
  final List<String> ids = <String>[for (final BmTeam t in kBmTeams) t.id];
  final Map<String, int> p = _rankStat(ids, _kPowerSalt), a = _rankStat(ids, _kAccSalt);
  return <String, BmDiscStats>{for (final String id in ids) id: BmDiscStats(p[id]!, a[id]!)};
}();

/// Stats of a disc; an unknown id gets the neutral middle (5, 5).
BmDiscStats bmDiscStats(String id) => kBmDiscStats[id] ?? const BmDiscStats(5, 5);

/// Shot speed multiplier for a power stat (1 => 0.82, 10 => 1.18, linear).
double bmPowerFactor(int power) {
  final int p = power.clamp(kBmStatMin, kBmStatMax);
  return kBmPowerMinFactor + (kBmPowerMaxFactor - kBmPowerMinFactor) * (p - kBmStatMin) / (kBmStatMax - kBmStatMin);
}

/// Largest aim deviation (degrees, at full strength) for an accuracy stat (10 => 0, 1 => 7).
double bmMaxAimDeviationDeg(int accuracy) {
  final int a = accuracy.clamp(kBmStatMin, kBmStatMax);
  return kBmMaxAimDeviationDeg * (kBmStatMax - a) / (kBmStatMax - kBmStatMin);
}

/// Deterministic unit value in [-1, 1) for one shot (match seed, shot number, piece id).
double bmAimNoise(int seed, int shot, int cid) =>
    bmHash32('$seed:$shot:$cid', 0x41494D21) / 0x80000000 - 1;

/// Signed aim deviation in degrees for one shot; [strength] is the pull 0..1.
double bmAimDeviationDeg(int accuracy, double strength, double noise) =>
    bmMaxAimDeviationDeg(accuracy) * strength.clamp(0.0, 1.0).toDouble() * noise.clamp(-1.0, 1.0).toDouble();
