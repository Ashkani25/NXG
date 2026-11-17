// The two finger-soccer goal models (owner choice, Nov 2026). Nothing else draws goals.
// Art is pure decoration: the physics goal (posts at CX +/- f.g on the goal line, depth from
// geo()) is unchanged. Each art declares where its two post feet are, so they are drawn exactly
// on the collision posts.

class BmGoalArt {
  const BmGoalArt(this.id, this.asset, this.postL, this.postR, this.foot, this.nameFa, this.nameEn);
  final String id, asset, nameFa, nameEn;

  /// Post-foot centres as fractions of the image width (top goal orientation).
  final double postL, postR;

  /// Goal-line (post feet) as a fraction of the image height; the art extends upward from it.
  final double foot;
}

const List<BmGoalArt> kBmGoalArts = <BmGoalArt>[
  // Green-framed goal with a green/white grid net, traced from the owner's top-down reference.
  BmGoalArt('green', 'assets/games/finger_soccer/goals/goal_green.webp', 0.0712, 0.9288, 0.979, 'سبز', 'Green'),
  // White tubular goal with a hexagon net (owner's art, background removed).
  BmGoalArt('hex', 'assets/games/finger_soccer/goals/goal_hex.webp', 0.0522, 0.9491, 0.985, 'سفید شش‌ضلعی', 'White hex'),
];

/// Default goal model: green.
const int kBmGoalDefault = 0;

/// Where to draw [art] (image [imgW] x [imgH]) for a TOP goal whose posts are at
/// [cx] +/- [halfWidth] on the goal line [lineY]: post feet land exactly on the posts.
/// The bottom goal is this rect mirrored about its own goal line.
({double left, double top, double width, double height}) bmGoalArtRect(
    BmGoalArt art, int imgW, int imgH, double cx, double halfWidth, double lineY) {
  final double w = 2 * halfWidth / (art.postR - art.postL);
  final double h = w * imgH / imgW;
  return (left: cx - halfWidth - art.postL * w, top: lineY - art.foot * h, width: w, height: h);
}
