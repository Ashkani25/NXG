import 'package:flutter/widgets.dart';
import 'package:nexora/games/core/game_contract.dart';

import 'ui/ludo_game.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'online/ludo_online.dart';

/// NEXORA Ludo: 2-4 seats, classic rules, offline bots and pass-and-play.
Widget buildLudoGame(GameLaunch launch) => LudoGame(launch: launch);

// ---- online (server-authoritative, see lib/games/core/online) ----
/// Online board for a live match driven by [GmMatchController].
Widget buildLudoOnline(GmMatchController c) => LudoOnlineBoard(c: c);
