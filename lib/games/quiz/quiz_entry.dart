import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/quiz_view.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'online/quiz_online.dart';

/// NEXORA Quiz: 10-round knowledge duel (vs offline bot or same-device split screen).
Widget buildQuizGame(GameLaunch launch) => QuizView(launch: launch);

// ---- online (server-authoritative, see lib/games/core/online) ----
/// Online board for a live match driven by [GmMatchController].
Widget buildQuizOnline(GmMatchController c) => QuizOnlineBoard(c: c);

/// Extra line for the online result card.
String? buildQuizOnlineResultDetail(BuildContext context, GmView v) => quizResultDetail(context, v);
