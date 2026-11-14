/// go_router routes of the online Social Station (wired into the app router by the integration agent).
///   /social                 hub (my profile card + Friends / Chats / Clubs)
///   /social/friends         friends, requests, search by username
///   /social/chats           conversation list (inbox)
///   /social/chats/:id       chat screen with realtime messages
///   /social/clubs           club list, join / leave
///   /social/clubs/:id       club detail (members, club chat)
///   /social/profile         my online profile (edit username, bio, avatar url)
///   /social/user/:id        another user's public profile
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'pages/chats_page.dart';
import 'pages/clubs_page.dart';
import 'pages/friends_page.dart';
import 'pages/profile_page.dart';
import 'pages/social_hub_page.dart';

final List<RouteBase> socialOnlineRoutes = <RouteBase>[
  GoRoute(
    path: '/social',
    builder: (BuildContext context, GoRouterState s) => const SocialHubPage(),
    routes: <RouteBase>[
      GoRoute(path: 'friends', builder: (BuildContext context, GoRouterState s) => const SocialFriendsPage()),
      GoRoute(
        path: 'chats',
        builder: (BuildContext context, GoRouterState s) => const SocialChatsPage(),
        routes: <RouteBase>[
          GoRoute(path: ':id', builder: (BuildContext context, GoRouterState s) => SocialChatPage(conversationId: s.pathParameters['id'] ?? '')),
        ],
      ),
      GoRoute(
        path: 'clubs',
        builder: (BuildContext context, GoRouterState s) => const SocialClubsPage(),
        routes: <RouteBase>[
          GoRoute(path: ':id', builder: (BuildContext context, GoRouterState s) => SocialClubDetailPage(clubId: s.pathParameters['id'] ?? '')),
        ],
      ),
      GoRoute(path: 'profile', builder: (BuildContext context, GoRouterState s) => const SocialMyProfilePage()),
      GoRoute(path: 'user/:id', builder: (BuildContext context, GoRouterState s) => SocialUserProfilePage(userId: s.pathParameters['id'] ?? '')),
    ],
  ),
];
