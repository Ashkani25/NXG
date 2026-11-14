/// Which online board each arcade game uses (hooks live in lib/games/<id>/<id>_entry.dart).
library;

import 'package:flutter/material.dart';

import 'package:nexora/core/widgets/nx_widgets.dart';
import 'package:nexora/games/backgammon/backgammon_entry.dart';
import 'package:nexora/games/ludo/ludo_entry.dart';
import 'package:nexora/games/mafia/mafia_entry.dart';
import 'package:nexora/games/quiz/quiz_entry.dart';
import 'package:nexora/games/snakes_ladders/snakes_ladders_entry.dart';
import 'package:nexora/games/uno/uno_entry.dart';

import 'billiards_online.dart';
import 'carrom_online.dart';
import 'gm_match_controller.dart';
import 'gm_models.dart';

Widget buildGmBoard(BuildContext context, String gameId, GmMatchController c) {
  switch (gameId) {
    case 'backgammon':
      return buildBackgammonOnline(c);
    case 'ludo':
      return buildLudoOnline(c);
    case 'snakes_ladders':
      return buildSnakesLaddersOnline(c);
    case 'uno':
      return buildUnoOnline(c);
    case 'quiz':
      return buildQuizOnline(c);
    case 'mafia':
      return buildMafiaOnline(c);
    case 'carrom':
      return buildCarromOnline(c);
    case 'billiards':
      return buildBilliardsOnline(c);
    default:
      final GmGameSpec? s = gmSpec(gameId);
      return Padding(
        padding: const EdgeInsets.all(16),
        child: OnlineOnlyNotice(
          featureFa: 'نسخه‌ی آنلاین ${s?.nameFa ?? gameId} (به‌زودی)',
          featureEn: 'Online ${s?.nameEn ?? gameId} (coming soon)',
        ),
      );
  }
}

/// Extra line on the result card (gammon, card points, final scores, winning team).
String? gmResultDetail(BuildContext context, GmView v) {
  switch (v.game) {
    case 'backgammon':
      return buildBackgammonOnlineResultDetail(context, v);
    case 'uno':
      return buildUnoOnlineResultDetail(context, v);
    case 'quiz':
      return buildQuizOnlineResultDetail(context, v);
    case 'mafia':
      return buildMafiaOnlineResultDetail(context, v);
    case 'carrom':
      return carromOnlineResultDetail(context, v);
    case 'billiards':
      return billiardsOnlineResultDetail(context, v);
    default:
      return null;
  }
}
