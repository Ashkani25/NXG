import 'package:flutter/widgets.dart';

import 'package:nexora/games/core/game_contract.dart';
import 'ui/finger_soccer_view.dart';

/// NEXORA Arcade entry for Finger Soccer (pure core in core/, render + UI in ui/).
Widget buildFingerSoccerGame(GameLaunch launch) => FingerSoccerView(launch: launch);
