import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/uno_game_view.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'online/uno_online.dart';

/// NX Cards (UNO-style card game). Game id stays 'uno'.
/// UI name: "NX Cards", subtitle "UNO-style".
Widget buildUnoGame(GameLaunch launch) => UnoGameView(launch: launch);

// ---- online (server-authoritative, see lib/games/core/online) ----
/// Online board for a live match driven by [GmMatchController].
Widget buildUnoOnline(GmMatchController c) => UnoOnlineBoard(c: c);

/// Extra line for the online result card.
String? buildUnoOnlineResultDetail(BuildContext context, GmView v) => unoResultDetail(context, v);
