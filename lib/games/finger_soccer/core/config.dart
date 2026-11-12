/// Finger Soccer deterministic configuration.
/// MUST match the TS reference (test/games/tools/fs_physics_ref.ts = supabase submit_shot/physics.ts, CFG). Change both together.
class FsConfig {
  static const double fieldW = 680;
  static const double fieldH = 1000;
  static const double goalW = 220;
  static const double goalDepth = 46;
  static const double postR = 6;
  static const double discR = 34;
  static const double ballR = 20;
  static const double discMass = 1.0;
  static const double ballMass = 0.35;
  static const double dt = 1 / 120;
  static const double drag = 1.35;
  static const double stopSpeed = 6.0;
  static const double eDisc = 0.90;
  static const double eWall = 0.82;
  static const double eBall = 0.96;
  static const double maxShotSpeed = 2300;
  static const int discsPerTeam = 5;
  static const double maxSimTime = 9.0;
  static const int goalsToWin = 5;
  static const int maxTurns = 40;
  static const double turnSeconds = 15;

  /// UI only (not part of the deterministic contract).
  static const double maxPull = 170;

  static final int maxSteps = (maxSimTime / dt).floor();
  static const double mouthL = (fieldW - goalW) / 2;
  static const double mouthR = (fieldW + goalW) / 2;
}
