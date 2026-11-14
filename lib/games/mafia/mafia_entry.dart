import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/mafia_narrator_view.dart';
import 'ui/mafia_vsbot_view.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'online/mafia_online.dart';

/// Entry point registered in game_registry.dart.
///  * GameMode.vsBot: the player against offline AI citizens.
///  * GameMode.local: narrator mode for 6..12 friends sharing one phone.
Widget buildMafiaGame(GameLaunch launch) {
  if (launch.mode == GameMode.vsBot) {
    return MafiaVsBotView(launch: launch);
  }
  return MafiaNarratorView(launch: launch);
}

// ---- online (server-authoritative, see lib/games/core/online) ----
/// Online board for a live match driven by [GmMatchController].
Widget buildMafiaOnline(GmMatchController c) => MafiaOnlineBoard(c: c);

/// Extra line for the online result card.
String? buildMafiaOnlineResultDetail(BuildContext context, GmView v) => mafiaResultDetail(context, v);
