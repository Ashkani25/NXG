enum FsKind { disc, ball }

class FsBody {
  FsBody({
    required this.id,
    required this.kind,
    required this.team,
    required this.r,
    required this.m,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
  });

  final int id;
  final FsKind kind;

  /// 0 = bottom team (attacks top goal), 1 = top team (attacks bottom goal), -1 = ball.
  final int team;
  final double r;
  final double m;
  double x;
  double y;
  double vx;
  double vy;

  bool get isBall => kind == FsKind.ball;

  FsBody clone() => FsBody(id: id, kind: kind, team: team, r: r, m: m, x: x, y: y, vx: vx, vy: vy);

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.index, 'team': team, 'x': x, 'y': y};

  factory FsBody.fromJson(Map<String, dynamic> j, {required double r, required double m}) => FsBody(
        id: (j['id'] as num).toInt(),
        kind: FsKind.values[(j['kind'] as num).toInt()],
        team: (j['team'] as num).toInt(),
        r: r,
        m: m,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
      );
}
