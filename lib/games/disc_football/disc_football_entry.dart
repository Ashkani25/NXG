import 'package:flutter/widgets.dart';

import 'package:nexora/games/core/game_contract.dart';
import 'ui/disc_match_screen.dart';

/// NEXORA Arcade entry for Finger Soccer / فوتبال انگشتی (registry id `finger_soccer`), ported from
/// the Godot build. Pure deterministic core in core/ (engine, AI, data, online wire codec), renderer
/// (DiscMatchView), HUD, pickers and the offline match screen in ui/.
Widget buildDiscFootballGame(GameLaunch launch) => DiscMatchScreen(launch: launch);
