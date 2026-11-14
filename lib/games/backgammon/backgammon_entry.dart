import 'package:flutter/widgets.dart';
import 'package:nexora/games/core/game_contract.dart';

import 'ui/backgammon_game.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'online/backgammon_online.dart';

/// NEXORA Backgammon: full rules (bar, bearing off, doubles, forced larger
/// die, gammon/backgammon scoring), offline bot and pass-and-play.
Widget buildBackgammonGame(GameLaunch launch) => BackgammonGame(launch: launch);

// ---- online (server-authoritative, see lib/games/core/online) ----
/// Online board for a live match driven by [GmMatchController].
Widget buildBackgammonOnline(GmMatchController c) => BackgammonOnlineBoard(c: c);

/// Extra line for the online result card.
String? buildBackgammonOnlineResultDetail(BuildContext context, GmView v) => backgammonResultDetail(context, v);
