/// Pure-Dart models + mappers for the online Social Station (live Supabase schema).
/// No Flutter / Supabase imports so they are unit-testable and reusable server-side.
///
/// Live columns used (verified 2026-11-14):
///   profiles(id, username, avatar, avatar_url, bio, xp, level, club_id, online_at, rating, wins, losses, draws)
///   friends view(user_id, friend_id, since) · friend_requests(from_user, to_user, status, created_at)
///   inbox view(id, kind, title, avatar_url, club_id, last_message_at, role, muted, last_message json, unread, peer json, members)
///   messages(id, conversation_id, sender, body, image_url, reply_to, deleted, created_at)
///   club_list view(id, name, tag, emblem, description, owner, join_policy, min_level, max_members, conversation_id, members, power)
///   club_members(club_id, user_id, role, joined_at)
/// NOTE: profiles has no display-name column; the username is the display name.
library;

import 'dart:math' as math;

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : (v == null ? d : int.tryParse('$v') ?? d);
String _s(Object? v, [String d = '']) => v == null ? d : '$v';
String? _sn(Object? v) {
  if (v == null) return null;
  final String s = '$v';
  return s.isEmpty ? null : s;
}

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse('$v');
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Server formula (level_for_xp): floor(sqrt(xp/100)) + 1, never below 1.
int socialLevelForXp(num xp) {
  final num x = xp < 0 ? 0 : xp;
  final int l = math.sqrt(x / 100).floor() + 1;
  return l < 1 ? 1 : l;
}

/// XP needed to reach level [l] (inverse of [socialLevelForXp]).
int socialXpForLevel(int l) => l <= 1 ? 0 : (l - 1) * (l - 1) * 100;

/// 0..1 progress inside the current level.
double socialLevelProgress(num xp) {
  final int l = socialLevelForXp(xp);
  final int a = socialXpForLevel(l);
  final int b = socialXpForLevel(l + 1);
  if (b <= a) return 0;
  final double f = (xp - a) / (b - a);
  return f < 0 ? 0 : (f > 1 ? 1 : f);
}

class SocialProfile {
  const SocialProfile({
    required this.id,
    required this.username,
    this.avatar = '',
    this.avatarUrl,
    this.bio,
    this.xp = 0,
    this.clubId,
    this.onlineAt,
    this.rating = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
  });

  factory SocialProfile.fromRow(Map<String, dynamic> r) => SocialProfile(
        id: _s(r['id']),
        username: _s(r['username'], '…'),
        avatar: _s(r['avatar']),
        avatarUrl: _sn(r['avatar_url']),
        bio: _sn(r['bio']),
        xp: _i(r['xp']),
        clubId: _sn(r['club_id']),
        onlineAt: _dt(r['online_at']),
        rating: _i(r['rating']),
        wins: _i(r['wins']),
        losses: _i(r['losses']),
        draws: _i(r['draws']),
      );

  final String id;
  final String username;
  final String avatar;
  final String? avatarUrl;
  final String? bio;
  final int xp;
  final String? clubId;
  final DateTime? onlineAt;
  final int rating;
  final int wins;
  final int losses;
  final int draws;

  /// Display name (no separate column in the live schema).
  String get displayName => username;

  /// Level from the server formula, computed from xp.
  int get level => socialLevelForXp(xp);
  double get levelProgress => socialLevelProgress(xp);

  /// Considered online when presence was touched within the last 3 minutes.
  bool isOnlineAt(DateTime now) => onlineAt != null && now.difference(onlineAt!).inSeconds.abs() < 180;

  /// Only the columns the client may update (column grants: username, avatar, avatar_url, bio).
  static Map<String, dynamic> updatePatch({String? username, String? bio, String? avatarUrl, String? avatar}) {
    final Map<String, dynamic> p = <String, dynamic>{};
    if (username != null) p['username'] = username.trim();
    if (bio != null) p['bio'] = bio.trim().isEmpty ? null : bio.trim();
    if (avatarUrl != null) p['avatar_url'] = avatarUrl.trim().isEmpty ? null : avatarUrl.trim();
    if (avatar != null) p['avatar'] = avatar;
    return p;
  }
}

enum FriendRequestDir { incoming, outgoing }

class FriendRequestInfo {
  const FriendRequestInfo({required this.fromUser, required this.toUser, required this.status, this.createdAt});
  factory FriendRequestInfo.fromRow(Map<String, dynamic> r) => FriendRequestInfo(
        fromUser: _s(r['from_user']),
        toUser: _s(r['to_user']),
        status: _s(r['status'], 'pending'),
        createdAt: _dt(r['created_at']),
      );
  final String fromUser;
  final String toUser;
  final String status;
  final DateTime? createdAt;

  bool get pending => status == 'pending';
  FriendRequestDir dirFor(String me) => toUser == me ? FriendRequestDir.incoming : FriendRequestDir.outgoing;
  String otherOf(String me) => fromUser == me ? toUser : fromUser;
}

/// Friend relation state between me and another user (for buttons).
enum FriendState { none, friends, incoming, outgoing, self }

class InboxItem {
  const InboxItem({
    required this.id,
    required this.kind,
    this.title,
    this.avatarUrl,
    this.clubId,
    this.lastMessageAt,
    this.lastBody,
    this.lastSender,
    this.unread = 0,
    this.peer,
    this.members = 0,
    this.muted = false,
  });

  factory InboxItem.fromRow(Map<String, dynamic> r) {
    final Map<String, dynamic> lm = _m(r['last_message']);
    final Map<String, dynamic> pr = _m(r['peer']);
    return InboxItem(
      id: _s(r['id']),
      kind: _s(r['kind'], 'dm'),
      title: _sn(r['title']),
      avatarUrl: _sn(r['avatar_url']),
      clubId: _sn(r['club_id']),
      lastMessageAt: _dt(r['last_message_at']),
      lastBody: lm.isEmpty ? null : (_sn(lm['body']) ?? (_sn(lm['image_url']) != null ? '🖼' : null)),
      lastSender: lm.isEmpty ? null : _sn(lm['sender']),
      unread: _i(r['unread']),
      peer: pr.isEmpty ? null : SocialProfile.fromRow(pr),
      members: _i(r['members']),
      muted: r['muted'] == true,
    );
  }

  final String id;
  final String kind;
  final String? title;
  final String? avatarUrl;
  final String? clubId;
  final DateTime? lastMessageAt;
  final String? lastBody;
  final String? lastSender;
  final int unread;
  final SocialProfile? peer;
  final int members;
  final bool muted;

  bool get isDm => kind == 'dm';

  /// Title to show: DM → peer username, otherwise conversation title.
  String displayTitle(String fallback) {
    if (isDm && peer != null) return peer!.username;
    final String t = (title ?? '').trim();
    return t.isEmpty ? fallback : t;
  }

  String? get displayAvatarUrl => isDm ? (peer?.avatarUrl ?? avatarUrl) : avatarUrl;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    this.sender,
    this.body,
    this.imageUrl,
    this.replyTo,
    this.deleted = false,
    required this.createdAt,
  });

  factory ChatMessage.fromRow(Map<String, dynamic> r) => ChatMessage(
        id: _i(r['id']),
        conversationId: _s(r['conversation_id']),
        sender: _sn(r['sender']),
        body: _sn(r['body']),
        imageUrl: _sn(r['image_url']),
        replyTo: r['reply_to'] == null ? null : _i(r['reply_to']),
        deleted: r['deleted'] == true,
        createdAt: _dt(r['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final String conversationId;
  final String? sender;
  final String? body;
  final String? imageUrl;
  final int? replyTo;
  final bool deleted;
  final DateTime createdAt;

  bool mine(String me) => sender != null && sender == me;

  /// Row for `messages.insert` (RLS: sender must be auth.uid() and can_post()).
  static Map<String, dynamic> insertRow({required String conversationId, required String sender, required String body}) =>
      <String, dynamic>{'conversation_id': conversationId, 'sender': sender, 'body': body.trim()};
}

/// Merges a new message into a list sorted by id ascending, without duplicates.
List<ChatMessage> mergeMessage(List<ChatMessage> list, ChatMessage m) {
  if (m.deleted) return list.where((ChatMessage x) => x.id != m.id).toList();
  final List<ChatMessage> out = list.where((ChatMessage x) => x.id != m.id).toList()..add(m);
  out.sort((ChatMessage a, ChatMessage b) => a.id.compareTo(b.id));
  return out;
}

class ClubInfo {
  const ClubInfo({
    required this.id,
    required this.name,
    required this.tag,
    this.emblem = '',
    this.description,
    this.owner,
    this.joinPolicy = 'open',
    this.minLevel = 1,
    this.maxMembers = 0,
    this.conversationId,
    this.members = 0,
    this.power = 0,
  });

  factory ClubInfo.fromRow(Map<String, dynamic> r) => ClubInfo(
        id: _s(r['id']),
        name: _s(r['name'], '…'),
        tag: _s(r['tag']),
        emblem: _s(r['emblem']),
        description: _sn(r['description']),
        owner: _sn(r['owner']),
        joinPolicy: _s(r['join_policy'], 'open'),
        minLevel: _i(r['min_level'], 1),
        maxMembers: _i(r['max_members']),
        conversationId: _sn(r['conversation_id']),
        members: _i(r['members']),
        power: _i(r['power']),
      );

  final String id;
  final String name;
  final String tag;
  final String emblem;
  final String? description;
  final String? owner;
  final String joinPolicy; // open | request | invite
  final int minLevel;
  final int maxMembers;
  final String? conversationId;
  final int members;
  final int power;

  bool get full => maxMembers > 0 && members >= maxMembers;
  bool get inviteOnly => joinPolicy == 'invite';
  bool get open => joinPolicy == 'open';
}

class ClubMembership {
  const ClubMembership({required this.clubId, required this.userId, required this.role});
  factory ClubMembership.fromRow(Map<String, dynamic> r) =>
      ClubMembership(clubId: _s(r['club_id']), userId: _s(r['user_id']), role: _s(r['role'], 'member'));
  final String clubId;
  final String userId;
  final String role;
}
