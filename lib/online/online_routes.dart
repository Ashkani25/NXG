/// go_router routes of the online area (online core + online Disc Football).
///   /online                         hub (?quick=1v1|2v2|3v3 starts a quick match)
///   /online/account                 account + online profile
///   /online/lobby/:roomId           room lobby (?skip=<matchId>&why=quit|hostLost|aborted)
///   /online/match/:roomId/:matchId  online Disc Football match
///   /online/result/:roomId          result (extra: OnlineOutcome)
///   /online/ranks                   leaderboard (?tab=leagues → leagues & season)
///   /online/arena                   arena ladder + find opponent
///   /online/challenges              daily challenges
///   /online/tournaments             tournaments list / create
///   /online/tournaments/:id         tournament detail
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../games/disc_football/online/online_match_page.dart';
import 'models.dart';
import 'screens/account_page.dart';
import 'screens/challenges_page.dart';
import 'screens/hub_page.dart';
import 'screens/lobby_page.dart';
import 'screens/online_result_page.dart';
import 'screens/ranks_page.dart';
import 'screens/tournaments_page.dart';

/// The app router, set by buildRouter (auth deep links open the account page for password recovery).
GoRouter? onlineRouter;

final List<RouteBase> onlineRoutes = <RouteBase>[
  GoRoute(
    path: '/online',
    builder: (BuildContext context, GoRouterState s) => OnlineHubPage(quick: s.uri.queryParameters['quick'] ?? ''),
    routes: <RouteBase>[
      GoRoute(path: 'account', builder: (BuildContext context, GoRouterState s) => const OnlineAccountPage()),
      GoRoute(
        path: 'lobby/:roomId',
        builder: (BuildContext context, GoRouterState s) => OnlineLobbyPage(
          roomId: s.pathParameters['roomId'] ?? '',
          skipMatch: s.uri.queryParameters['skip'] ?? '',
          why: s.uri.queryParameters['why'] ?? '',
        ),
      ),
      GoRoute(
        path: 'match/:roomId/:matchId',
        builder: (BuildContext context, GoRouterState s) =>
            OnlineMatchPage(roomId: s.pathParameters['roomId'] ?? '', matchId: s.pathParameters['matchId'] ?? ''),
      ),
      GoRoute(
        path: 'result/:roomId',
        builder: (BuildContext context, GoRouterState s) =>
            OnlineResultPage(roomId: s.pathParameters['roomId'] ?? '', outcome: s.extra is OnlineOutcome ? s.extra! as OnlineOutcome : null),
      ),
      GoRoute(path: 'ranks', builder: (BuildContext context, GoRouterState s) => OnlineRanksPage(tab: s.uri.queryParameters['tab'] ?? 'top')),
      GoRoute(path: 'arena', builder: (BuildContext context, GoRouterState s) => const OnlineArenaPage()),
      GoRoute(path: 'challenges', builder: (BuildContext context, GoRouterState s) => const OnlineChallengesPage()),
      GoRoute(
        path: 'tournaments',
        builder: (BuildContext context, GoRouterState s) => const OnlineTournamentsPage(),
        routes: <RouteBase>[
          GoRoute(path: ':id', builder: (BuildContext context, GoRouterState s) => OnlineTournamentDetailPage(id: s.pathParameters['id'] ?? '')),
        ],
      ),
    ],
  ),
];
