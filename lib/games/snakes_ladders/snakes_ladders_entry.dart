import 'package:flutter/widgets.dart';
import 'package:nexora/games/core/game_contract.dart';

import 'ui/snl_game.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'online/snl_online.dart';

/// NEXORA Snakes & Ladders: 2-4 seats on a cosmic 10x10 board, offline bots
/// (vsBot) or pass-and-play (local).
Widget buildSnakesLaddersGame(GameLaunch launch) => SnlGame(launch: launch);

// ---- online (server-authoritative, see lib/games/core/online) ----
/// Online board for a live match driven by [GmMatchController].
Widget buildSnakesLaddersOnline(GmMatchController c) => SnlOnlineBoard(c: c);
