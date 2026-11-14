// Disc Football catalogue — 1:1 port of the Godot build's src/core/data.gd (newest source of truth,
// 2026-11-14): fields (FS scaling applied), goal sprite metrics, disc catalogue (NX8 groups first),
// 9 formations, trails, field FX, prices, disc stats and the offline launch builder.
// Pure Dart: no Flutter imports. Asset paths live in the UI layer (ui/df_assets.dart).
import 'dart:math' as math;

/// Field geometry in world units.
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

  /// Art size (the field image is drawn over Rect(0, 0, w, h)).
  final double w;
  final double h;

  /// Playable rectangle edges (the engine insets them by 4).
  final double l;
  final double r;
  final double t;
  final double b;

  /// Kick-off spot y.
  final double cs;

  /// Half goal-mouth width.
  final double g;

  /// Goal style key into [kGS] (also the goal art name).
  final String gs;
}

class DiscCat {
  const DiscCat(this.key, this.label, this.names);
  final String key;
  final String label;
  final List<String> names;
}

/// A formation: Persian + English name and per-disc points [depth, lateral]
/// (depth 0 = own goal line .. 1 = halfway line; lateral 0..1 left -> right for the bottom side).
class Formation {
  const Formation(this.nameFa, this.nameEn, this.pts);
  final String nameFa;
  final String nameEn;
  final List<List<double>> pts;
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

const double kFS = 1.12;
const int kDefaultField = 0;
const int kBallCount = 36;

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

const List<String> kBallNames = <String>['Bolt', 'Prism', 'Wave', 'Starlight', 'Classic', 'Rainbow', 'Neon', 'Yin', 'Fire', 'Blade', 'Ghost', 'Ember', 'Plasma', 'Noir Copper', 'Space Modern', 'Purple Sky', 'Black Lux', 'Electron', 'Cobalt Gold', 'Aurora', 'Crimson', 'Teal Storm', 'Royal Gold', 'Gold Rush', 'Classic Red', 'Luxury', 'Noir Chrome', 'Violet Strike', 'Emerald Edge', 'Royal Blue Gold', 'Crimson Noir', 'Blaze Orange', 'Aqua Wave', 'Sunset Pro', 'Elite Cobalt', 'Crown Luxury'];

const List<int> kVipPrices = <int>[260, 275, 290, 255, 300, 265, 280, 270, 0, 295, 285, 250];

/// All visible discs, ids `<cat><index>` (e.g. club0), Godot TEAMS order; removed discs skipped.
final List<Team> kTeams = List<Team>.unmodifiable(<Team>[
  for (final DiscCat c in kCats)
    for (int i = 0; i < c.names.length; i++)
      if (!kRemovedTeams.contains('${c.key}$i')) Team(id: '${c.key}$i', cat: c.key, name: c.names[i], idx: i),
]);

final Map<String, Team> _teamIdx = <String, Team>{for (final Team t in kTeams) t.id: t};

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

int fieldPrice(int i) => i < 5 ? 0 : 80 + ((i - 1) % 5) * 20;

/// Formation slots [nx, ny]: nx = lateral 0..1 (engine insets by the disc radius),
/// ny = distance from own goal line as a fraction of the pitch length (Godot data.gd slots()).
List<List<double>> slots(int fi) {
  final Formation fm = kForms[fi.clamp(0, kForms.length - 1)];
  return <List<double>>[
    for (final List<double> pt in fm.pts) <double>[pt[1], 0.02 + pt[0] * 0.48],
  ];
}

// ---------------- util ----------------
String teamKey(Team t) => '${t.cat}${t.idx.toString().padLeft(2, '0')}';

bool teamRemoved(String id) => kRemovedTeams.contains(id);

Team teamById(String id) => _teamIdx[id] ?? _teamIdx['club0'] ?? kTeams[0];

/// Accepts a disc id (club0) or an art key (club00), like online_match.gd team_of_avatar.
Team teamOfAvatar(String? key) {
  for (final Team t in kTeams) {
    if (t.id == key || teamKey(t) == key) return t;
  }
  return kTeams[0];
}

/// FNV-1a 32-bit (Godot hash32).
int hashStr(String s) {
  int h = 2166136261;
  for (int i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h & 0xFFFFFFFF;
}

int rarity(Team t) {
  final String c = t.cat;
  if (c == 'vip' || c == 'leg') return 3;
  if (c == 'lux' || c == 'gal' || c == 'car' || c == 'emb' || c == 'chrome') return 2;
  if (c == 'spt' || c == 'elite') return 1;
  return 0;
}

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

// ---------------- disc stats (data.gd disc_stats) ----------------
class DiscStatsData {
  const DiscStatsData(this.power, this.accuracy);
  final double power;
  final double accuracy;
}

/// Server disc catalogue (online layer fills it: id -> power/accuracy).
final Map<String, DiscStatsData> discCatalogOverride = <String, DiscStatsData>{};

DiscStatsData discStatsFor(String? id) {
  final String key = id ?? '';
  final DiscStatsData? o = discCatalogOverride[key];
  if (o != null) return o;
  final Team? t = _teamIdx[key];
  final String cat = t?.cat ?? '';
  double base = (cat == 'leg' || cat == 'vip') ? 8.0 : ((cat == 'club' || cat == 'nat') ? 5.0 : 6.0);
  if (key.isEmpty) base = 5.0;
  return DiscStatsData(base, base);
}

bool isFreeDisc(String id) => RegExp(r'^(club|nat)\d+$').hasMatch(id) || id == 'elite0';

/// Offline opponents: club / national / elite discs (data.gd opp_pool).
List<Team> oppPool() => <Team>[
      for (final Team t in kTeams)
        if (t.cat == 'club' || t.cat == 'nat' || t.cat == 'elite') t,
    ];

Team pickOpp(math.Random rng) {
  final List<Team> p = oppPool();
  return p[rng.nextInt(p.length)];
}

bool teamBoosted(Team t) => t.cat == 'vip' || t.cat == 'leg';

/// Field table (Godot data.gd FIELDS, FS scaling already applied).
const List<Field> kFields = <Field>[
  Field(id: 'pitch', name: 'NEXORA Pitch', w: 837.0, h: 1536.0, l: 30.0, r: 805.0, t: 101.0, b: 1432.0, cs: 768.0, g: 128.0, gs: 'white'),
  Field(id: 'forest', name: 'Forest', w: 1216.0, h: 1622.0, l: 218.0, r: 997.0, t: 142.0, b: 1468.0, cs: 786.0, g: 135.0, gs: 'wood'),
  Field(id: 'ice', name: 'Ice', w: 1216.0, h: 1622.0, l: 213.0, r: 1002.0, t: 150.0, b: 1465.0, cs: 784.0, g: 137.0, gs: 'ice'),
  Field(id: 'ocean', name: 'Ocean', w: 1216.0, h: 1622.0, l: 214.0, r: 1005.0, t: 121.0, b: 1471.0, cs: 785.0, g: 137.0, gs: 'blue'),
  Field(id: 'street', name: 'Street', w: 1216.0, h: 1622.0, l: 204.0, r: 1010.0, t: 176.0, b: 1471.0, cs: 791.0, g: 139.0, gs: 'gold'),
  Field(id: 'streetarena', name: 'Street Arena', w: 1216.0, h: 1622.0, l: 217.0, r: 995.0, t: 131.0, b: 1466.0, cs: 786.0, g: 135.0, gs: 'rope'),
  Field(id: 'lava', name: 'Lava', w: 1216.0, h: 1622.0, l: 224.0, r: 990.0, t: 142.0, b: 1462.0, cs: 783.0, g: 133.0, gs: 'black'),
  Field(id: 'stadium', name: 'Stadium', w: 1216.0, h: 1622.0, l: 220.0, r: 995.0, t: 129.0, b: 1468.0, cs: 785.0, g: 134.0, gs: 'white'),
  Field(id: 'checker', name: 'Checker', w: 1216.0, h: 1622.0, l: 216.0, r: 997.0, t: 114.0, b: 1515.0, cs: 788.0, g: 135.0, gs: 'red'),
  Field(id: 'futsal', name: 'Futsal', w: 1216.0, h: 1622.0, l: 213.0, r: 1002.0, t: 116.0, b: 1476.0, cs: 781.0, g: 137.0, gs: 'gold'),
  Field(id: 'arena', name: 'Arena', w: 1216.0, h: 1622.0, l: 223.0, r: 990.0, t: 132.0, b: 1471.0, cs: 777.0, g: 133.0, gs: 'red'),
  Field(id: 'arena2', name: 'Grand Arena', w: 1216.0, h: 1622.0, l: 184.0, r: 1032.0, t: 151.0, b: 1458.0, cs: 787.0, g: 139.0, gs: 'gold'),
  Field(id: 'desert', name: 'Desert', w: 1216.0, h: 1622.0, l: 183.0, r: 1030.0, t: 94.0, b: 1473.0, cs: 777.0, g: 139.0, gs: 'black'),
  Field(id: 'grove', name: 'Grove', w: 1216.0, h: 1622.0, l: 193.0, r: 1028.0, t: 121.0, b: 1478.0, cs: 778.0, g: 139.0, gs: 'rope'),
  Field(id: 'pool', name: 'Pool', w: 1216.0, h: 1622.0, l: 179.0, r: 1036.0, t: 110.0, b: 1469.0, cs: 781.0, g: 139.0, gs: 'white'),
  Field(id: 'neon', name: 'Neon Tech', w: 1147.0, h: 1720.0, l: 158.0, r: 989.0, t: 147.0, b: 1551.0, cs: 834.0, g: 145.0, gs: 'black'),
  Field(id: 'royal', name: 'Royal', w: 1147.0, h: 1720.0, l: 166.0, r: 982.0, t: 165.0, b: 1512.0, cs: 818.0, g: 141.0, gs: 'gold'),
  Field(id: 'mahogany', name: 'Mahogany', w: 1147.0, h: 1720.0, l: 109.0, r: 1036.0, t: 101.0, b: 1560.0, cs: 816.0, g: 161.0, gs: 'wood'),
  Field(id: 'leather', name: 'Leather', w: 1147.0, h: 1720.0, l: 111.0, r: 1036.0, t: 111.0, b: 1574.0, cs: 818.0, g: 160.0, gs: 'gold'),
  Field(id: 'aqua', name: 'Aquarium', w: 1147.0, h: 1720.0, l: 137.0, r: 1014.0, t: 137.0, b: 1557.0, cs: 831.0, g: 152.0, gs: 'blue'),
  Field(id: 'asphalt', name: 'Asphalt', w: 1147.0, h: 1720.0, l: 109.0, r: 1036.0, t: 127.0, b: 1587.0, cs: 831.0, g: 161.0, gs: 'rope'),
  Field(id: 'court', name: 'Court', w: 1147.0, h: 1720.0, l: 132.0, r: 1016.0, t: 129.0, b: 1542.0, cs: 801.0, g: 154.0, gs: 'white'),
  Field(id: 'cyberbox', name: 'Cyber Box', w: 1147.0, h: 1720.0, l: 132.0, r: 1015.0, t: 121.0, b: 1543.0, cs: 791.0, g: 153.0, gs: 'black'),
  Field(id: 'realmadrid', name: 'Real Madrid', w: 1216.0, h: 1622.0, l: 218.0, r: 996.0, t: 112.0, b: 1490.0, cs: 809.0, g: 135.0, gs: 'black'),
  Field(id: 'psg', name: 'Paris SG', w: 1216.0, h: 1622.0, l: 228.0, r: 987.0, t: 129.0, b: 1452.0, cs: 746.0, g: 135.0, gs: 'red'),
  Field(id: 'acmilan', name: 'AC Milan', w: 1216.0, h: 1622.0, l: 218.0, r: 996.0, t: 112.0, b: 1490.0, cs: 809.0, g: 135.0, gs: 'white'),
  Field(id: 'barcelona', name: 'FC Barcelona', w: 1216.0, h: 1622.0, l: 217.0, r: 996.0, t: 113.0, b: 1488.0, cs: 808.0, g: 135.0, gs: 'gold'),
  Field(id: 'persepolis', name: 'Persepolis', w: 1290.0, h: 1720.0, l: 232.0, r: 1056.0, t: 151.0, b: 1579.0, cs: 862.0, g: 135.0, gs: 'white'),
  Field(id: 'esteghlal', name: 'Esteghlal', w: 1216.0, h: 1622.0, l: 218.0, r: 997.0, t: 112.0, b: 1481.0, cs: 773.0, g: 135.0, gs: 'gold'),
  Field(id: 'mancity', name: 'Man City', w: 1216.0, h: 1622.0, l: 218.0, r: 996.0, t: 114.0, b: 1488.0, cs: 805.0, g: 135.0, gs: 'red'),
];

/// Disc catalogue categories [key, label, names] in Godot order (NX8 groups first).
const List<DiscCat> kCats = <DiscCat>[
  DiscCat('lux', 'Luxury', <String>['Lamborghini', 'Ferrari', 'Porsche', 'Mercedes-Benz', 'BMW', 'Aston Martin', 'Rolls-Royce', 'Bentley', 'Maserati', 'Bugatti', 'McLaren', 'Lexus', 'Tesla', 'Volvo', 'Land Rover', 'Audi', 'Cadillac', 'Alfa Romeo', 'Pagani', 'Koenigsegg']),
  DiscCat('club', 'Clubs', <String>['Persepolis', 'Esteghlal', 'Sepahan', 'Tractor', 'Foolad', 'Zob Ahan', 'Nassaji Mazandaran', 'Sanat Naft Abadan', 'Aluminium Arak', 'Mes Rafsanjan', 'Paykan', 'Malavan', 'Gol Gohar Sirjan', 'Chadormalu', 'Shahin Bushehr', 'Mes Kerman', 'Kheybar Khorramabad', 'Arvand Khorramshahr', 'Real Madrid 1902', 'Barcelona 1899', 'Bayern 1900', 'AC Milan 1899', 'Juventus 1897', 'Inter 1908', 'Liverpool', 'Manchester City', 'Chelsea', 'Arsenal', 'Manchester United', 'Atlético Madrid', 'Inter Milan', 'AC Milan', 'Juventus', 'FC Barcelona', 'Real Madrid', 'Bayern Munich', 'Borussia Dortmund', 'Paris Saint-Germain', 'Marseille', 'AS Roma', 'Napoli', 'Lazio', 'Atalanta', 'Fiorentina', 'Sevilla', 'Benfica', 'Sporting CP', 'FC Porto', 'Ajax', 'PSV Eindhoven', 'Bayer Leverkusen', 'RB Leipzig', 'Gladbach', 'Lille', 'West Ham United', 'Leicester City', 'FC Basel', 'Celtic', 'Galatasaray', 'Beşiktaş', 'Shakhtar Donetsk', 'Zenit', 'Red Bull Salzburg', 'Dinamo Zagreb', 'Inter Miami', 'Wolfsburg', 'Tottenham', 'Rangers', 'Monaco', 'Aston Villa', 'Olympique Lyonnais', 'Al Hilal']),
  DiscCat('nat', 'National', <String>['Argentina', 'Brazil', 'Germany', 'France', 'Portugal', 'Spain', 'England', 'Italy', 'Netherlands', 'Uruguay', 'Mexico', 'Belgium', 'Poland', 'Switzerland', 'Croatia', 'Morocco', 'Senegal', 'South Korea', 'Japan', 'USA', 'Argentina II', 'Brazil II', 'France II', 'Germany II', 'England II', 'Italy II', 'Spain II', 'Portugal II', 'Netherlands II', 'Belgium II', 'Sweden', 'Denmark', 'Poland II', 'Switzerland II', 'Croatia II', 'Serbia', 'Mexico II', 'USA II', 'Uruguay II', 'Colombia', 'Chile', 'Ecuador', 'Algeria', 'Morocco II', 'Nigeria', 'Cameroon', 'Ghana', 'Senegal II', 'Ivory Coast', 'Tunisia', 'Egypt', 'Japan II', 'South Korea II', 'Australia', 'New Zealand', 'Iran', 'Saudi Arabia', 'Qatar', 'Iraq', 'UAE', 'Lebanon']),
  DiscCat('spt', 'Sport', <String>['Nike', 'Adidas', 'Puma', 'Under Armour', 'Reebok', 'New Balance', 'ASICS', 'Mizuno', 'Wilson', 'Converse', 'Jordan', 'Skechers', 'EA7', 'The North Face', 'Columbia', 'Speedo', 'Arena', 'Wilson Tennis', 'Dunlop', 'Head']),
  DiscCat('gal', 'Girls', <String>['Chanel', 'Louis Vuitton', 'Dior', 'Gucci', 'Yves Saint Laurent', 'Prada', 'MAC', 'Victoria\'s Secret', 'Sephora', 'Estée Lauder', 'Lancôme', 'Zara', 'H&M', 'Uniqlo', 'Pandora', 'Kate Spade', 'Coach', 'Cartier', 'Tiffany & Co.', 'PINK']),
  DiscCat('vip', 'VIP', <String>['Nova Blue', 'Aurum Crest', 'Emerald Core', 'Specter Wings', 'Infernal Edge', 'Timber Blaze', 'Chrome Vortex', 'Crimson Pulse', 'Thunder Gold', 'Jade Marble', 'Kakero Noir', 'Kakero Frost']),
  DiscCat('car', 'Cars', <String>['Lamborghini', 'Ferrari', 'Rolls-Royce', 'Mercedes-Benz', 'BMW', 'Porsche', 'Maserati', 'Aston Martin', 'Bentley', 'Bugatti', 'Lexus', 'Cadillac', 'McLaren', 'Tesla']),
  DiscCat('elite', 'Elite', <String>['NX Prime', 'Real Madrid', 'Barcelona', 'Juventus', 'Liverpool', 'Manchester United', 'Paris SG', 'Bayern Munich', 'Atletico Madrid', 'Inter Milan', 'AC Milan', 'Chelsea', 'Manchester City', 'Arsenal', 'Tottenham', 'Dortmund', 'Leverkusen', 'Napoli', 'Roma', 'Lazio', 'Fiorentina', 'Monaco', 'Marseille', 'Benfica', 'Porto', 'Sporting CP', 'Galatasaray', 'Besiktas', 'Fenerbahce', 'Ajax', 'Al Hilal', 'Al Nassr', 'Al Ittihad', 'Al Ain', 'Al Ahly', 'Zamalek']),
  DiscCat('emb', 'Emblems', <String>['Golden Lion', 'Shadow Wolf', 'Azure Dragon', 'Phoenix', 'Viper', 'Silver Eagle', 'Iron Bull', 'Frost Crown', 'Scorpion', 'Tide Shark', 'Evergreen', 'Royal Fleur', 'Compass', 'NX Gold', 'Polaris', 'Grizzly']),
  DiscCat('leg', 'Legends', <String>['Inferno Scorpion', 'Dire Wolf', 'Samurai Sun', 'Venom Dragon', 'Bermuda', 'Magma Golem']),
  DiscCat('chrome', 'Chrome', <String>['Mercedes Chrome', 'BMW Chrome', 'Toyota Chrome', 'Ferrari Chrome', 'Lambo Chrome', 'Porsche Chrome', 'Tesla Chrome', 'Audi Chrome']),
];

/// Discs hidden from game and shop (ids keep their index).
const Set<String> kRemovedTeams = <String>{'chrome0', 'chrome1', 'chrome2', 'chrome3', 'chrome4', 'chrome5', 'chrome6', 'chrome7', 'elite0', 'elite1', 'elite2', 'elite3', 'elite4', 'elite5', 'elite6', 'elite7', 'elite8', 'elite9', 'elite10', 'elite11', 'elite12', 'elite13', 'elite14', 'elite15', 'elite16', 'elite17', 'elite18', 'elite19', 'elite20', 'elite21', 'elite22', 'elite23', 'elite24', 'elite25', 'elite26', 'elite27', 'elite28', 'elite29', 'elite30', 'elite31', 'elite32', 'elite33', 'elite34', 'elite35'};

const Map<String, String> kCatFa = <String, String>{'lux': 'لوکس', 'club': 'باشگاه', 'nat': 'ملی', 'spt': 'ورزشی', 'gal': 'بانوان', 'vip': 'VIP', 'car': 'خودرو', 'elite': 'الیت', 'emb': 'نشان', 'leg': 'افسانه', 'chrome': 'کروم'};

/// Formations (Godot FORMS): name fa/en + per disc [depth, lateral].
const List<Formation> kForms = <Formation>[
  Formation('الماس', 'Diamond', <List<double>>[<double>[0.14, 0.5], <double>[0.39, 0.2], <double>[0.39, 0.8], <double>[0.76, 0.36], <double>[0.76, 0.64]]),
  Formation('عقاب', 'Eagle', <List<double>>[<double>[0.14, 0.5], <double>[0.36, 0.2], <double>[0.36, 0.8], <double>[0.56, 0.5], <double>[0.86, 0.5]]),
  Formation('موج', 'Wave', <List<double>>[<double>[0.3, 0.27], <double>[0.3, 0.73], <double>[0.62, 0.06], <double>[0.62, 0.5], <double>[0.62, 0.94]]),
  Formation('ماه', 'Moon', <List<double>>[<double>[0.18, 0.5], <double>[0.38, 0.18], <double>[0.38, 0.82], <double>[0.64, 0.04], <double>[0.64, 0.96]]),
  Formation('دیوانه', 'Crazy', <List<double>>[<double>[0.62, 0.5], <double>[0.86, 0.0], <double>[0.86, 0.31], <double>[0.86, 0.69], <double>[0.86, 1.0]]),
  Formation('لبه', 'Edge', <List<double>>[<double>[0.11, 0.5], <double>[0.37, 0.5], <double>[0.63, 0.5], <double>[0.86, 0.12], <double>[0.86, 0.88]]),
  Formation('نیش', 'Sting', <List<double>>[<double>[0.13, 0.5], <double>[0.5, 0.08], <double>[0.5, 0.92], <double>[0.88, 0.08], <double>[0.88, 0.92]]),
  Formation('بازو', 'Arm', <List<double>>[<double>[0.13, 0.5], <double>[0.56, 0.12], <double>[0.56, 0.5], <double>[0.56, 0.88], <double>[0.88, 0.88]]),
  Formation('حمله همه جانبه', 'All-out Attack', <List<double>>[<double>[0.13, 0.5], <double>[0.72, 0.3], <double>[0.72, 0.7], <double>[0.88, 0.04], <double>[0.88, 0.96]]),
];

/// Ball trail styles (ARGB).
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

const Map<String, FieldFx> kFieldFx = <String, FieldFx>{
  'pitch': FieldFx(1, <int>[0xFFFFFFFF, 0xFFD8FFB0, 0xFF7BFF5A], 0.0),
  'forest': FieldFx(2, <int>[0xFF6FD36B, 0xFFB8F5A0, 0xFF2E8B3A], 130.0),
  'ice': FieldFx(1, <int>[0xFFE8FBFF, 0xFF9FE8FF, 0xFFFFFFFF], 30.0),
  'ocean': FieldFx(4, <int>[0xFFBFF3FF, 0xFF5CD0FF, 0xFFFFFFFF], -140.0),
  'street': FieldFx(5, <int>[0xFFFF2BD6, 0xFFFFE14A, 0xFF2BF0FF], 0.0),
  'streetarena': FieldFx(5, <int>[0xFFFFB02B, 0xFFFF3B6B, 0xFFFFFFFF], 0.0),
  'lava': FieldFx(0, <int>[0xFFFF5A1F, 0xFFFFB347, 0xFFFFE08A], -220.0),
  'stadium': FieldFx(1, <int>[0xFFFFD86B, 0xFFFFFFFF, 0xFFFFE9A8], 0.0),
  'checker': FieldFx(3, <int>[0xFFFFFFFF, 0xFF9AA3B0, 0xFFFF4040], 0.0),
  'futsal': FieldFx(5, <int>[0xFFFFCF8A, 0xFFFFFFFF, 0xFFFFA14A], 0.0),
  'arena': FieldFx(5, <int>[0xFF7FB8FF, 0xFFFFFFFF, 0xFF3B7BFF], 0.0),
  'arena2': FieldFx(1, <int>[0xFFC79BFF, 0xFFFFFFFF, 0xFF7B4BFF], 0.0),
  'desert': FieldFx(0, <int>[0xFFE8C689, 0xFFC99A54, 0xFFFFF0C8], 60.0),
  'grove': FieldFx(0, <int>[0xFFD8FF6A, 0xFFFFFFA0, 0xFF9CF06A], -30.0),
  'pool': FieldFx(0, <int>[0xFF9FE9FF, 0xFFE6FBFF, 0xFF4CC7FF], 380.0),
  'neon': FieldFx(5, <int>[0xFF7DFF3A, 0xFFD6FF9A, 0xFFFFFFFF], 0.0),
  'royal': FieldFx(1, <int>[0xFFFFD86B, 0xFFFFF3C4, 0xFFFF9A3A], 0.0),
  'mahogany': FieldFx(1, <int>[0xFFFFCF8A, 0xFFFFF0C8, 0xFFD9923A], -20.0),
  'leather': FieldFx(0, <int>[0xFFD9A066, 0xFFFFD9A0, 0xFF8A5A2A], -30.0),
  'aqua': FieldFx(4, <int>[0xFFBFF3FF, 0xFF5CD0FF, 0xFFFFFFFF], -150.0),
  'asphalt': FieldFx(5, <int>[0xFFFFE14A, 0xFFFFFFFF, 0xFFFFB02B], 0.0),
  'court': FieldFx(5, <int>[0xFFFFFFFF, 0xFFFFCF8A, 0xFF4AA8FF], 0.0),
  'cyberbox': FieldFx(5, <int>[0xFFFF3B3B, 0xFF3B8BFF, 0xFFFFFFFF], 0.0),
  'realmadrid': FieldFx(1, <int>[0xFFFFFFFF, 0xFFFFD86B, 0xFF3B6BFF], 0.0),
  'psg': FieldFx(5, <int>[0xFFFF2B3A, 0xFF3B6BFF, 0xFFFFFFFF], 0.0),
  'acmilan': FieldFx(5, <int>[0xFFFF2B3A, 0xFFFFFFFF, 0xFF111111], 0.0),
  'barcelona': FieldFx(5, <int>[0xFFFF2B5A, 0xFF3B6BFF, 0xFFFFD86B], 0.0),
  'persepolis': FieldFx(5, <int>[0xFFFF2B3A, 0xFFFFD86B, 0xFFFFFFFF], 0.0),
  'esteghlal': FieldFx(1, <int>[0xFF3B8BFF, 0xFFFFFFFF, 0xFFFFD86B], 0.0),
  'mancity': FieldFx(1, <int>[0xFF7FD0FF, 0xFFFFFFFF, 0xFF3B8BFF], 0.0),
};
