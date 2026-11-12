// Disc Football catalogue — 1:1 port of nexora-universe/src/game/data.ts (+ util.ts helpers).
// Pure Dart: no Flutter imports.

/// Field geometry in world units (already scaled like the Expo FIELDS table).
class Field {
  const Field({
    required this.id,
    required this.name,
    required this.w,
    required this.h,
    required this.l,
    required this.r,
    required this.t,
    required this.b,
    required this.cs,
    required this.g,
    required this.gs,
  });
  final String id;
  final String name;
  final double w;
  final double h;
  final double l;
  final double r;
  final double t;
  final double b;

  /// Kick-off spot y.
  final double cs;

  /// Half goal-mouth width.
  final double g;

  /// Goal style key into [kGS].
  final String gs;
}

class RawField {
  const RawField(this.id, this.name, this.w, this.h, this.l, this.r, this.t, this.b, this.cs, this.g, this.gs);
  final String id;
  final String name;
  final int w;
  final int h;
  final int l;
  final int r;
  final int t;
  final int b;
  final int cs;
  final int g;
  final String gs;
}

class DiscCat {
  const DiscCat(this.key, this.label, this.names);
  final String key;
  final String label;
  final List<String> names;
}

class Formation {
  const Formation(this.code, this.name, this.rows);
  final String code;
  final String name;

  /// rows of [depth (fraction of field height from own goal line), count]
  final List<List<double>> rows;
}

class TrailStyle {
  const TrailStyle(this.k, this.c);
  final String k;
  final List<int> c;
}

class FieldFx {
  const FieldFx(this.k, this.c, this.g);
  final int k;
  final List<int> c;
  final double g;
}

class Team {
  const Team({required this.id, required this.cat, required this.name, required this.idx});
  final String id;
  final String cat;
  final String name;
  final int idx;
}

/// JS Math.round (round half toward +infinity).
double jsRound(double x) => (x + 0.5).floorToDouble();

const double _kFS = 1.12;

/// FIELDS (scaled exactly like data.ts: W,H,L,R,T,B,cs × 1.12 rounded; g × 1.04 rounded).
final List<Field> kFields = List<Field>.unmodifiable(kRawFields.map((RawField f) => Field(
      id: f.id,
      name: f.name,
      w: jsRound(f.w * _kFS),
      h: jsRound(f.h * _kFS),
      l: jsRound(f.l * _kFS),
      r: jsRound(f.r * _kFS),
      t: jsRound(f.t * _kFS),
      b: jsRound(f.b * _kFS),
      cs: jsRound(f.cs * _kFS),
      g: jsRound(f.g * 1.04),
      gs: f.gs,
    )));

/// All 202 discs, ids `<cat><index>` (e.g. club0), like TEAMS in data.ts.
final List<Team> kTeams = List<Team>.unmodifiable(<Team>[
  for (final DiscCat c in kCats)
    for (int i = 0; i < c.names.length; i++) Team(id: '${c.key}$i', cat: c.key, name: c.names[i], idx: i),
]);

final Map<String, String> kCatLabel = <String, String>{for (final DiscCat c in kCats) c.key: c.label};

int teamPrice(Team t) {
  if (t.cat == 'vip') return t.idx < kVipPrices.length && kVipPrices[t.idx] != 0 ? kVipPrices[t.idx] : 250;
  if (t.cat == 'club' || t.cat == 'nat') return 0;
  if (t.cat == 'leg') return 520;
  if (t.cat == 'emb') return 220;
  if (t.cat == 'elite') return t.idx == 0 ? 0 : 160;
  if (t.cat == 'chrome') return 180;
  return 120;
}

int ballPrice(int i) => i < 6 ? 0 : 60 + (i % 7) * 20;

/// index 0 is the free default NEXORA Pitch.
int fieldPrice(int i) => i < 5 ? 0 : 80 + ((i - 1) % 5) * 20;

const int kDefaultField = 0;
const int kBallCount = 36;

/// Formation slots as (nx, ny) in [0,1] — same as data.ts `slots`.
List<List<double>> slots(int fi) {
  final List<List<double>> o = <List<double>>[];
  for (final List<double> row in kForms[fi].rows) {
    final double ny = row[0];
    final int c = row[1].toInt();
    for (int i = 0; i < c; i++) {
      o.add(<double>[c == 1 ? .5 : c == 2 ? .27 + .46 * i : .17 + .33 * i, ny]);
    }
  }
  return o;
}

// ---------------- util.ts ----------------
String teamKey(Team t) => '${t.cat}${t.idx.toString().padLeft(2, '0')}';

Team teamById(String id) {
  for (final Team t in kTeams) {
    if (t.id == id) return t;
  }
  return kTeams[0];
}

/// Accepts a disc id (club0) or an art key (club00), like online/ui.tsx teamOfAvatar.
Team teamOfAvatar(String? key) {
  for (final Team t in kTeams) {
    if (t.id == key || teamKey(t) == key) return t;
  }
  return kTeams[0];
}

/// FNV-1a 32-bit, identical to util.ts `hash`.
int hashStr(String s) {
  int h = 2166136261;
  for (int i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h & 0xFFFFFFFF;
}

int rarity(Team t) => t.cat == 'vip' || t.cat == 'leg'
    ? 3
    : t.cat == 'lux' || t.cat == 'car' || t.cat == 'emb' || t.cat == 'chrome'
        ? 2
        : t.cat == 'spt' || t.cat == 'elite'
            ? 1
            : 0;

class RarityInfo {
  const RarityInfo(this.name, this.color);
  final String name;
  final int color;
}

const List<RarityInfo> kRarity = <RarityInfo>[
  RarityInfo('COMMON', 0xFF8EA3D6),
  RarityInfo('RARE', 0xFF4FE3FF),
  RarityInfo('EPIC', 0xFFB46BFF),
  RarityInfo('LEGENDARY', 0xFFFFD257),
];

/// Offline disc stats (net/discs.tsx fallback): legends/VIP 8, club/national 5, others 6.
/// The online catalogue (power/accuracy per disc) overrides this when available.
class DiscStatsData {
  const DiscStatsData(this.power, this.accuracy);
  final double power;
  final double accuracy;
}

final Map<String, DiscStatsData> discCatalogOverride = <String, DiscStatsData>{};

DiscStatsData discStatsFor(String? id) {
  final DiscStatsData? o = id == null ? null : discCatalogOverride[id];
  if (o != null) return o;
  Team? t;
  for (final Team x in kTeams) {
    if (x.id == (id ?? 'club0')) t = x;
  }
  final double base = t != null && (t.cat == 'leg' || t.cat == 'vip')
      ? 8
      : t != null && (t.cat == 'club' || t.cat == 'nat')
          ? 5
          : 6;
  return DiscStatsData(base, base);
}

bool isFreeDisc(String id) => RegExp(r'^(club|nat)\d+$').hasMatch(id) || id == 'elite0';


/// Goal sprite metrics per goal style: [imgW, imgH, mouthLeftFrac, mouthRightFrac].
const Map<String, List<double>> kGS = <String, List<double>>{
  'white': <double>[840.0, 307.0, 0.0491, 0.9522],
  'wood': <double>[840.0, 306.0, 0.0474, 0.9519],
  'ice': <double>[840.0, 305.0, 0.0535, 0.9429],
  'black': <double>[840.0, 235.0, 0.0521, 0.9527],
  'rope': <double>[840.0, 246.0, 0.0493, 0.9528],
  'gold': <double>[840.0, 237.0, 0.0431, 0.9521],
  'red': <double>[840.0, 233.0, 0.0502, 0.9509],
  'blue': <double>[840.0, 236.0, 0.0452, 0.9526],
};

/// Raw (pre-scale) field table, index 0 = NEXORA Pitch.
const List<RawField> kRawFields = <RawField>[
  RawField('pitch', 'NEXORA Pitch', 747, 1371, 27, 719, 90, 1279, 686, 123, 'white'),
  RawField('forest', 'Forest', 1086, 1448, 195, 890, 127, 1311, 702, 130, 'wood'),
  RawField('ice', 'Ice', 1086, 1448, 190, 895, 134, 1308, 700, 132, 'ice'),
  RawField('ocean', 'Ocean', 1086, 1448, 191, 897, 108, 1313, 701, 132, 'blue'),
  RawField('street', 'Street', 1086, 1448, 182, 902, 157, 1313, 706, 134, 'gold'),
  RawField('streetarena', 'Street Arena', 1086, 1448, 194, 888, 117, 1309, 702, 130, 'rope'),
  RawField('lava', 'Lava', 1086, 1448, 200, 884, 127, 1305, 699, 128, 'black'),
  RawField('stadium', 'Stadium', 1086, 1448, 196, 888, 115, 1311, 701, 129, 'white'),
  RawField('checker', 'Checker', 1086, 1448, 193, 890, 102, 1353, 704, 130, 'red'),
  RawField('futsal', 'Futsal', 1086, 1448, 190, 895, 104, 1318, 697, 132, 'gold'),
  RawField('arena', 'Arena', 1086, 1448, 199, 884, 118, 1313, 694, 128, 'red'),
  RawField('arena2', 'Grand Arena', 1086, 1448, 164, 921, 135, 1302, 703, 134, 'gold'),
  RawField('desert', 'Desert', 1086, 1448, 163, 920, 84, 1315, 694, 134, 'black'),
  RawField('grove', 'Grove', 1086, 1448, 172, 918, 108, 1320, 695, 134, 'rope'),
  RawField('pool', 'Pool', 1086, 1448, 160, 925, 98, 1312, 697, 134, 'white'),
  RawField('neon', 'Neon Tech', 1024, 1536, 141, 883, 131, 1385, 745, 139, 'black'),
  RawField('royal', 'Royal', 1024, 1536, 148, 877, 147, 1350, 730, 136, 'gold'),
  RawField('mahogany', 'Mahogany', 1024, 1536, 97, 925, 90, 1393, 729, 155, 'wood'),
  RawField('leather', 'Leather', 1024, 1536, 99, 925, 99, 1405, 730, 154, 'gold'),
  RawField('aqua', 'Aquarium', 1024, 1536, 122, 905, 122, 1390, 742, 146, 'blue'),
  RawField('asphalt', 'Asphalt', 1024, 1536, 97, 925, 113, 1417, 742, 155, 'rope'),
  RawField('court', 'Court', 1024, 1536, 118, 907, 115, 1377, 715, 148, 'white'),
  RawField('cyberbox', 'Cyber Box', 1024, 1536, 118, 906, 108, 1378, 706, 147, 'black'),
  RawField('realmadrid', 'Real Madrid', 1086, 1448, 195, 889, 100, 1330, 722, 130, 'black'),
  RawField('psg', 'Paris SG', 1086, 1448, 204, 881, 115, 1296, 666, 130, 'red'),
  RawField('acmilan', 'AC Milan', 1086, 1448, 195, 889, 100, 1330, 722, 130, 'white'),
  RawField('barcelona', 'FC Barcelona', 1086, 1448, 194, 889, 101, 1329, 721, 130, 'gold'),
  RawField('persepolis', 'Persepolis', 1152, 1536, 207, 943, 135, 1410, 770, 130, 'white'),
  RawField('esteghlal', 'Esteghlal', 1086, 1448, 195, 890, 100, 1322, 690, 130, 'gold'),
  RawField('mancity', 'Man City', 1086, 1448, 195, 889, 102, 1329, 719, 130, 'red'),
];

/// Disc catalogue categories: [key, label, names].
const List<DiscCat> kCats = <DiscCat>[
  DiscCat('club', 'Clubs', <String>['Real Madrid', 'Barcelona', 'Manchester City', 'Manchester United', 'Liverpool', 'Arsenal', 'Chelsea', 'Bayern Munich', 'Borussia Dortmund', 'Paris Saint-Germain', 'Inter Milan', 'AC Milan', 'Juventus', 'Atletico Madrid', 'Ajax', 'Benfica', 'Porto', 'Boca Juniors', 'River Plate', 'Flamengo', 'Al Nassr', 'Al Hilal', 'Roma', 'Besiktas', 'Tottenham', 'Marseille', 'Napoli', 'Sporting CP', 'Sevilla', 'Valencia', 'PSV', 'Celtic', 'Bayer Leverkusen', 'RB Leipzig', 'Lyon', 'Galatasaray', 'Fenerbahce', 'Shakhtar Donetsk', 'Inter Miami', 'Newcastle United', 'Aston Villa', 'West Ham United', 'Everton', 'Villarreal', 'Fiorentina', 'Corinthians', 'Lazio', 'Wolfsburg', 'Persepolis', 'Esteghlal']),
  DiscCat('nat', 'National', <String>['Argentina', 'Brazil', 'France', 'Germany', 'Portugal', 'Spain', 'Italy', 'England', 'Netherlands', 'Belgium', 'Uruguay', 'Sweden', 'Poland', 'Denmark', 'Croatia', 'Switzerland', 'Mexico', 'USA', 'Japan', 'South Korea', 'Australia', 'Senegal', 'Morocco', 'Tunisia', 'Egypt', 'Iceland', 'Iran', 'Qatar', 'Saudi Arabia', 'Colombia', 'Canada', 'Turkey']),
  DiscCat('vip', 'VIP', <String>['Nova Blue', 'Aurum Crest', 'Emerald Core', 'Specter Wings', 'Infernal Edge', 'Timber Blaze', 'Chrome Vortex', 'Crimson Pulse', 'Thunder Gold', 'Jade Marble', 'Kakero Noir', 'Kakero Frost']),
  DiscCat('car', 'Cars', <String>['Lamborghini', 'Ferrari', 'Rolls-Royce', 'Mercedes-Benz', 'BMW', 'Porsche', 'Maserati', 'Aston Martin', 'Bentley', 'Bugatti', 'Lexus', 'Cadillac', 'McLaren', 'Tesla']),
  DiscCat('lux', 'Luxury', <String>['Louis Vuitton', 'Chanel', 'Gucci', 'Hermes', 'Prada', 'Dior', 'Versace', 'Rolex', 'Cartier', 'Fendi', 'Valentino', 'Burberry', 'Saint Laurent', 'Swarovski']),
  DiscCat('spt', 'Sports', <String>['Nike', 'Adidas', 'Puma', 'Under Armour', 'New Balance', 'Reebok', 'Jordan', 'Asics', 'Wilson', 'Speedo', 'Converse', 'Vans', 'NBA', 'Umbro']),
  DiscCat('elite', 'Elite', <String>['NX Prime', 'Real Madrid', 'Barcelona', 'Juventus', 'Liverpool', 'Manchester United', 'Paris SG', 'Bayern Munich', 'Atletico Madrid', 'Inter Milan', 'AC Milan', 'Chelsea', 'Manchester City', 'Arsenal', 'Tottenham', 'Dortmund', 'Leverkusen', 'Napoli', 'Roma', 'Lazio', 'Fiorentina', 'Monaco', 'Marseille', 'Benfica', 'Porto', 'Sporting CP', 'Galatasaray', 'Besiktas', 'Fenerbahce', 'Ajax', 'Al Hilal', 'Al Nassr', 'Al Ittihad', 'Al Ain', 'Al Ahly', 'Zamalek']),
  DiscCat('emb', 'Emblems', <String>['Golden Lion', 'Shadow Wolf', 'Azure Dragon', 'Phoenix', 'Viper', 'Silver Eagle', 'Iron Bull', 'Frost Crown', 'Scorpion', 'Tide Shark', 'Evergreen', 'Royal Fleur', 'Compass', 'NX Gold', 'Polaris', 'Grizzly']),
  DiscCat('leg', 'Legends', <String>['Inferno Scorpion', 'Dire Wolf', 'Samurai Sun', 'Venom Dragon', 'Bermuda', 'Magma Golem']),
  DiscCat('chrome', 'Chrome', <String>['Mercedes Chrome', 'BMW Chrome', 'Toyota Chrome', 'Ferrari Chrome', 'Lambo Chrome', 'Porsche Chrome', 'Tesla Chrome', 'Audi Chrome']),
];

/// Formations: [code, name, rows of (depth, count)].
const List<Formation> kForms = <Formation>[
  Formation('1-2-2', 'Balanced', <List<double>>[<double>[0.09, 1.0], <double>[0.22, 2.0], <double>[0.36, 2.0]]),
  Formation('2-2-1', 'Cautious', <List<double>>[<double>[0.1, 2.0], <double>[0.24, 2.0], <double>[0.37, 1.0]]),
  Formation('3-1-1', 'Wall', <List<double>>[<double>[0.1, 3.0], <double>[0.25, 1.0], <double>[0.37, 1.0]]),
  Formation('2-1-2', 'Diamond', <List<double>>[<double>[0.1, 2.0], <double>[0.24, 1.0], <double>[0.37, 2.0]]),
  Formation('1-3-1', 'Midfield', <List<double>>[<double>[0.09, 1.0], <double>[0.23, 3.0], <double>[0.37, 1.0]]),
  Formation('1-1-3', 'Attack', <List<double>>[<double>[0.09, 1.0], <double>[0.22, 1.0], <double>[0.36, 3.0]]),
];

/// Ball trail styles (ARGB colours).
const List<TrailStyle> kTrails = <TrailStyle>[
  TrailStyle('bolt', <int>[0xFF19B4FF, 0xFF8FE6FF, 0xFFFFFFFF]),
  TrailStyle('prism', <int>[0xFFFF7BD5, 0xFF7BD7FF, 0xFFFFFFFF]),
  TrailStyle('wave', <int>[0xFF2FE0D0, 0xFF9FF7EF, 0xFFFFFFFF]),
  TrailStyle('star', <int>[0xFF5CB6FF, 0xFFBFE3FF, 0xFFFFFFFF]),
  TrailStyle('smoke', <int>[0xFFE8ECF2, 0xFF9AA3B0, 0xFFFFFFFF]),
  TrailStyle('rainbow', <int>[0xFFFF5B5B, 0xFFFFD23A, 0xFF5BFF8A, 0xFF5BD0FF, 0xFFC05BFF]),
  TrailStyle('neon', <int>[0xFF4DFF2A, 0xFFB6FF9A, 0xFFFFFFFF]),
  TrailStyle('yin', <int>[0xFFFFFFFF, 0xFF9B5CFF, 0xFF000000]),
  TrailStyle('fire', <int>[0xFFFF8A1F, 0xFFFFD24A, 0xFFFFF3C4]),
  TrailStyle('blade', <int>[0xFFFF2B3A, 0xFFFF8A92, 0xFFFFFFFF]),
  TrailStyle('ghost', <int>[0xFFDBE7FF, 0xFF8FB0FF, 0xFFFFFFFF]),
  TrailStyle('ember', <int>[0xFFFF6A1F, 0xFFFFB347, 0xFFFFF0C8]),
  TrailStyle('plasma', <int>[0xFF2F8BFF, 0xFF7FC6FF, 0xFFFFFFFF]),
  TrailStyle('ghost', <int>[0xFFD9915B, 0xFFF2C9A0, 0xFFFFF4E6]),
  TrailStyle('star', <int>[0xFF2F7BFF, 0xFF8FD0FF, 0xFFFFFFFF]),
  TrailStyle('wave', <int>[0xFF9B5CFF, 0xFFE0B8FF, 0xFFFFFFFF]),
  TrailStyle('fire', <int>[0xFFE0A82E, 0xFFFFE08A, 0xFFFFF7D6]),
  TrailStyle('bolt', <int>[0xFF2F6BFF, 0xFF7FB4FF, 0xFFFFFFFF]),
  TrailStyle('neon', <int>[0xFF2F8BFF, 0xFFE8B84A, 0xFFFFFFFF]),
  TrailStyle('prism', <int>[0xFF1FD6A0, 0xFF3B9BFF, 0xFFFFFFFF]),
  TrailStyle('blade', <int>[0xFFFF2B3A, 0xFFFF8A92, 0xFFFFFFFF]),
  TrailStyle('plasma', <int>[0xFF18D8C0, 0xFF9FF5E6, 0xFFFFFFFF]),
  TrailStyle('ember', <int>[0xFF2F5BFF, 0xFFFFC83A, 0xFFFFF3C4]),
  TrailStyle('yin', <int>[0xFFFFFFFF, 0xFFE0A82E, 0xFF000000]),
  TrailStyle('smoke', <int>[0xFFFF4A4A, 0xFF9AA3B0, 0xFFFFFFFF]),
  TrailStyle('star', <int>[0xFFE0A82E, 0xFFFFF0B0, 0xFFFFFFFF]),
  TrailStyle('plasma', <int>[0xFF2F8BFF, 0xFFC0C8D8, 0xFFFFFFFF]),
  TrailStyle('ghost', <int>[0xFF9B5CFF, 0xFFFFFFFF, 0xFFFFFFFF]),
  TrailStyle('neon', <int>[0xFF4DFF2A, 0xFFC0C8D8, 0xFFFFFFFF]),
  TrailStyle('blade', <int>[0xFFE8B84A, 0xFF2F6BFF, 0xFFFFFFFF]),
  TrailStyle('fire', <int>[0xFFFF2B3A, 0xFFFF8A92, 0xFFFFFFFF]),
  TrailStyle('ember', <int>[0xFFFF8A1F, 0xFFFFD24A, 0xFFFFFFFF]),
  TrailStyle('wave', <int>[0xFF3B9BFF, 0xFF2FE08A, 0xFFFFFFFF]),
  TrailStyle('prism', <int>[0xFFFF4A7A, 0xFF9B5CFF, 0xFFFFFFFF]),
  TrailStyle('bolt', <int>[0xFF2F6BFF, 0xFFFFFFFF, 0xFFFFFFFF]),
  TrailStyle('star', <int>[0xFFFFD56B, 0xFFFFFFFF, 0xFFFFFFFF]),
];

const List<String> kBallNames = <String>['Bolt', 'Prism', 'Wave', 'Starlight', 'Classic', 'Rainbow', 'Neon', 'Yin', 'Fire', 'Blade', 'Ghost', 'Ember', 'Plasma', 'Noir Copper', 'Space Modern', 'Purple Sky', 'Black Lux', 'Electron', 'Cobalt Gold', 'Aurora', 'Crimson', 'Teal Storm', 'Royal Gold', 'Gold Rush', 'Classic Red', 'Luxury', 'Noir Chrome', 'Violet Strike', 'Emerald Edge', 'Royal Blue Gold', 'Crimson Noir', 'Blaze Orange', 'Aqua Wave', 'Sunset Pro', 'Elite Cobalt', 'Crown Luxury'];

const Map<String, FieldFx> kFieldFx = <String, FieldFx>{
  'pitch': FieldFx(1, <int>[0xFFFFFFFF, 0xFFD8FFB0, 0xFF7BFF5A], 0),
  'forest': FieldFx(2, <int>[0xFF6FD36B, 0xFFB8F5A0, 0xFF2E8B3A], 130),
  'ice': FieldFx(1, <int>[0xFFE8FBFF, 0xFF9FE8FF, 0xFFFFFFFF], 30),
  'ocean': FieldFx(4, <int>[0xFFBFF3FF, 0xFF5CD0FF, 0xFFFFFFFF], -140),
  'street': FieldFx(5, <int>[0xFFFF2BD6, 0xFFFFE14A, 0xFF2BF0FF], 0),
  'streetarena': FieldFx(5, <int>[0xFFFFB02B, 0xFFFF3B6B, 0xFFFFFFFF], 0),
  'lava': FieldFx(0, <int>[0xFFFF5A1F, 0xFFFFB347, 0xFFFFE08A], -220),
  'stadium': FieldFx(1, <int>[0xFFFFD86B, 0xFFFFFFFF, 0xFFFFE9A8], 0),
  'checker': FieldFx(3, <int>[0xFFFFFFFF, 0xFF9AA3B0, 0xFFFF4040], 0),
  'futsal': FieldFx(5, <int>[0xFFFFCF8A, 0xFFFFFFFF, 0xFFFFA14A], 0),
  'arena': FieldFx(5, <int>[0xFF7FB8FF, 0xFFFFFFFF, 0xFF3B7BFF], 0),
  'arena2': FieldFx(1, <int>[0xFFC79BFF, 0xFFFFFFFF, 0xFF7B4BFF], 0),
  'desert': FieldFx(0, <int>[0xFFE8C689, 0xFFC99A54, 0xFFFFF0C8], 60),
  'grove': FieldFx(0, <int>[0xFFD8FF6A, 0xFFFFFFA0, 0xFF9CF06A], -30),
  'pool': FieldFx(0, <int>[0xFF9FE9FF, 0xFFE6FBFF, 0xFF4CC7FF], 380),
  'neon': FieldFx(5, <int>[0xFF7DFF3A, 0xFFD6FF9A, 0xFFFFFFFF], 0),
  'royal': FieldFx(1, <int>[0xFFFFD86B, 0xFFFFF3C4, 0xFFFF9A3A], 0),
  'mahogany': FieldFx(1, <int>[0xFFFFCF8A, 0xFFFFF0C8, 0xFFD9923A], -20),
  'leather': FieldFx(0, <int>[0xFFD9A066, 0xFFFFD9A0, 0xFF8A5A2A], -30),
  'aqua': FieldFx(4, <int>[0xFFBFF3FF, 0xFF5CD0FF, 0xFFFFFFFF], -150),
  'asphalt': FieldFx(5, <int>[0xFFFFE14A, 0xFFFFFFFF, 0xFFFFB02B], 0),
  'court': FieldFx(5, <int>[0xFFFFFFFF, 0xFFFFCF8A, 0xFF4AA8FF], 0),
  'cyberbox': FieldFx(5, <int>[0xFFFF3B3B, 0xFF3B8BFF, 0xFFFFFFFF], 0),
  'realmadrid': FieldFx(1, <int>[0xFFFFFFFF, 0xFFFFD86B, 0xFF3B6BFF], 0),
  'psg': FieldFx(5, <int>[0xFFFF2B3A, 0xFF3B6BFF, 0xFFFFFFFF], 0),
  'acmilan': FieldFx(5, <int>[0xFFFF2B3A, 0xFFFFFFFF, 0xFF111111], 0),
  'barcelona': FieldFx(5, <int>[0xFFFF2B5A, 0xFF3B6BFF, 0xFFFFD86B], 0),
  'persepolis': FieldFx(5, <int>[0xFFFF2B3A, 0xFFFFD86B, 0xFFFFFFFF], 0),
  'esteghlal': FieldFx(1, <int>[0xFF3B8BFF, 0xFFFFFFFF, 0xFFFFD86B], 0),
  'mancity': FieldFx(1, <int>[0xFF7FD0FF, 0xFFFFFFFF, 0xFF3B8BFF], 0),
};

const List<int> kVipPrices = <int>[260, 275, 290, 255, 300, 265, 280, 270, 0, 295, 285, 250];
