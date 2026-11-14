/// Routes of the online arcade games, for the main router to add:
///
///   routes: [..., ...gamesOnlineRoutes]
///
///   /arcade-online/:gameId                 lobby (quick match, create, join by code, rooms, ranks)
///   /arcade-online/:gameId/room/:roomId    waiting room → live match (also the reconnect link)
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'gm_lobby_page.dart';
import 'gm_models.dart';
import 'gm_room_page.dart';

export 'gm_models.dart' show gmSpec, gmPlayableGames, kGmGames, GmGameSpec;

/// Path of the online lobby of [gameId].
String gmLobbyPath(String gameId) => '/arcade-online/$gameId';

/// True when [gameId] has a working online mode in this build (others show «به‌زودی»).
bool gmHasOnline(String gameId) => gmSpec(gameId)?.playable ?? false;

final List<RouteBase> gamesOnlineRoutes = <RouteBase>[
  GoRoute(
    path: '/arcade-online/:gameId',
    builder: (BuildContext context, GoRouterState state) => GmLobbyPage(gameId: state.pathParameters['gameId'] ?? ''),
    routes: <RouteBase>[
      GoRoute(
        path: 'room/:roomId',
        builder: (BuildContext context, GoRouterState state) => GmRoomPage(
          gameId: state.pathParameters['gameId'] ?? '',
          roomId: state.pathParameters['roomId'] ?? '',
        ),
      ),
    ],
  ),
];
