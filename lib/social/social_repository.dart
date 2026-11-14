/// Online Social repository: every call goes to the live Supabase project through the
/// shared client in lib/online (Online / OnlineCore). Never throws: returns OnlineResult-style
/// values with Persian error text (errFa).
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../online/online_core.dart';
import '../online/supabase_client.dart';
import 'social_models.dart';

/// Result of a repository call.
class SocialResult<T> {
  const SocialResult.ok(this.value)
      : ok = true,
        error = '';
  const SocialResult.fail(this.error)
      : ok = false,
        value = null;
  final bool ok;
  final T? value;
  final String error;
}

List<Map<String, dynamic>> _rows(Object? d) {
  if (d is List) {
    return d.whereType<Map<dynamic, dynamic>>().map((Map<dynamic, dynamic> m) => Map<String, dynamic>.from(m)).toList();
  }
  return <Map<String, dynamic>>[];
}

class FriendsSnapshot {
  const FriendsSnapshot({required this.friends, required this.incoming, required this.outgoing});
  final List<SocialProfile> friends;
  final List<SocialProfile> incoming;
  final List<SocialProfile> outgoing;

  FriendState stateOf(String me, String other) {
    if (other == me) return FriendState.self;
    if (friends.any((SocialProfile p) => p.id == other)) return FriendState.friends;
    if (incoming.any((SocialProfile p) => p.id == other)) return FriendState.incoming;
    if (outgoing.any((SocialProfile p) => p.id == other)) return FriendState.outgoing;
    return FriendState.none;
  }
}

class SocialRepository {
  SocialRepository._();
  static final SocialRepository instance = SocialRepository._();

  OnlineCore get core => OnlineCore.instance;
  bool get ready => Online.ready;
  String get me => core.uid;
  bool get signedIn => core.signedIn;

  Future<SocialResult<T>> _run<T>(Future<T> Function() f) async {
    if (!Online.ready) await core.boot();
    if (!Online.ready) return SocialResult<T>.fail(errFa('Network request failed'));
    try {
      final T v = await f().timeout(const Duration(seconds: 15));
      return SocialResult<T>.ok(v);
    } catch (e) {
      return SocialResult<T>.fail(errFa(e));
    }
  }

  SupabaseClient get _db => Online.client;

  // ---------------------------------------------------------------- profiles
  Future<SocialResult<SocialProfile?>> myProfile() => _run<SocialProfile?>(() async {
        if (me.isEmpty) return null;
        final Map<String, dynamic>? r = await _db.from('profiles').select().eq('id', me).maybeSingle();
        return r == null ? null : SocialProfile.fromRow(r);
      });

  Future<SocialResult<SocialProfile?>> profile(String id) => _run<SocialProfile?>(() async {
        final Map<String, dynamic>? r = await _db.from('profiles').select().eq('id', id).maybeSingle();
        return r == null ? null : SocialProfile.fromRow(r);
      });

  Future<List<SocialProfile>> _profilesByIds(List<String> ids) async {
    if (ids.isEmpty) return <SocialProfile>[];
    final Object? d = await _db.from('profiles').select().inFilter('id', ids);
    return _rows(d).map(SocialProfile.fromRow).toList();
  }

  /// Updates username / bio / avatar_url of the signed-in user. Checks username availability first.
  Future<SocialResult<SocialProfile?>> updateMyProfile({String? username, String? bio, String? avatarUrl}) =>
      _run<SocialProfile?>(() async {
        if (me.isEmpty) throw Exception('not signed in');
        final Map<String, dynamic> patch = SocialProfile.updatePatch(username: username, bio: bio, avatarUrl: avatarUrl);
        if (patch.isEmpty) return null;
        final String cur = '${core.profile['username'] ?? ''}';
        final Object? un = patch['username'];
        if (un is String && un != cur) {
          final dynamic okName = await _db.rpc<dynamic>('username_available', params: <String, dynamic>{'p_name': un});
          if (okName == false) throw Exception('duplicate key username');
        }
        final Map<String, dynamic> r = await _db.from('profiles').update(patch).eq('id', me).select().single();
        unawaited(core.refreshProfile());
        return SocialProfile.fromRow(r);
      });

  Future<SocialResult<List<SocialProfile>>> searchUsers(String q) => _run<List<SocialProfile>>(() async {
        final String t = q.trim().replaceAll('%', '').replaceAll('_', r'\_');
        if (t.length < 2) return <SocialProfile>[];
        final Object? d = await _db.from('profiles').select().ilike('username', '%$t%').neq('id', me).order('xp', ascending: false).limit(25);
        return _rows(d).map(SocialProfile.fromRow).toList();
      });

  // ---------------------------------------------------------------- friends
  Future<SocialResult<FriendsSnapshot>> friends() => _run<FriendsSnapshot>(() async {
        if (me.isEmpty) throw Exception('not signed in');
        final Object? f = await _db.from('friends').select('user_id, friend_id, since').eq('user_id', me);
        final List<String> fIds = _rows(f).map((Map<String, dynamic> r) => '${r['friend_id']}').toList();
        final Object? rq = await _db.from('friend_requests').select().eq('status', 'pending').or('from_user.eq.$me,to_user.eq.$me');
        final List<FriendRequestInfo> reqs = _rows(rq).map(FriendRequestInfo.fromRow).toList();
        final List<String> inIds = <String>[];
        final List<String> outIds = <String>[];
        for (final FriendRequestInfo r in reqs) {
          final String o = r.otherOf(me);
          if (fIds.contains(o)) continue;
          (r.dirFor(me) == FriendRequestDir.incoming ? inIds : outIds).add(o);
        }
        final List<SocialProfile> all = await _profilesByIds(<String>{...fIds, ...inIds, ...outIds}.toList());
        List<SocialProfile> pick(List<String> ids) => all.where((SocialProfile p) => ids.contains(p.id)).toList()
          ..sort((SocialProfile a, SocialProfile b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
        return FriendsSnapshot(friends: pick(fIds), incoming: pick(inIds), outgoing: pick(outIds));
      });

  /// Returns 'sent' or 'friends'.
  Future<SocialResult<String>> sendFriendRequest(String user) => _run<String>(() async {
        final dynamic r = await _db.rpc<dynamic>('send_friend_request', params: <String, dynamic>{'p_user': user});
        return '${r ?? 'sent'}';
      });

  Future<SocialResult<bool>> respondFriendRequest(String from, bool accept) => _run<bool>(() async {
        await _db.rpc<dynamic>('respond_friend_request', params: <String, dynamic>{'p_from': from, 'p_accept': accept});
        return true;
      });

  Future<SocialResult<bool>> cancelFriendRequest(String user) => _run<bool>(() async {
        await _db.rpc<dynamic>('cancel_friend_request', params: <String, dynamic>{'p_user': user});
        return true;
      });

  Future<SocialResult<bool>> removeFriend(String user) => _run<bool>(() async {
        await _db.rpc<dynamic>('remove_friend', params: <String, dynamic>{'p_user': user});
        return true;
      });

  // ---------------------------------------------------------------- chats
  Future<SocialResult<List<InboxItem>>> inbox() => _run<List<InboxItem>>(() async {
        if (me.isEmpty) throw Exception('not signed in');
        final Object? d = await _db.from('inbox').select().order('last_message_at', ascending: false).limit(100);
        return _rows(d).map(InboxItem.fromRow).toList();
      });

  /// Opens (or creates) the DM with [user]; returns the conversation id.
  Future<SocialResult<String>> openDm(String user) => _run<String>(() async {
        final dynamic r = await _db.rpc<dynamic>('open_dm', params: <String, dynamic>{'p_user': user});
        final String id = '${r ?? ''}';
        if (id.isEmpty) throw Exception('not allowed');
        return id;
      });

  Future<SocialResult<InboxItem?>> conversation(String id) => _run<InboxItem?>(() async {
        final Map<String, dynamic>? r = await _db.from('inbox').select().eq('id', id).maybeSingle();
        if (r != null) return InboxItem.fromRow(r);
        final Map<String, dynamic>? c =
            await _db.from('conversations').select('id, kind, title, avatar_url, club_id, last_message_at').eq('id', id).maybeSingle();
        return c == null ? null : InboxItem.fromRow(c);
      });

  Future<SocialResult<List<ChatMessage>>> messages(String conversationId, {int limit = 60}) => _run<List<ChatMessage>>(() async {
        final Object? d = await _db
            .from('messages')
            .select('id, conversation_id, sender, body, image_url, reply_to, deleted, created_at')
            .eq('conversation_id', conversationId)
            .eq('deleted', false)
            .order('id', ascending: false)
            .limit(limit);
        final List<ChatMessage> out = _rows(d).map(ChatMessage.fromRow).toList();
        out.sort((ChatMessage a, ChatMessage b) => a.id.compareTo(b.id));
        return out;
      });

  Future<SocialResult<Map<String, SocialProfile>>> profilesFor(List<String> ids) => _run<Map<String, SocialProfile>>(() async {
        final List<SocialProfile> ps = await _profilesByIds(ids.toSet().toList());
        return <String, SocialProfile>{for (final SocialProfile p in ps) p.id: p};
      });

  Future<SocialResult<bool>> canPost(String conversationId) => _run<bool>(() async {
        final dynamic r = await _db.rpc<dynamic>('can_post', params: <String, dynamic>{'c': conversationId});
        return r == true;
      });

  Future<SocialResult<ChatMessage>> send(String conversationId, String body) => _run<ChatMessage>(() async {
        if (me.isEmpty) throw Exception('not signed in');
        final Map<String, dynamic> r = await _db
            .from('messages')
            .insert(ChatMessage.insertRow(conversationId: conversationId, sender: me, body: body))
            .select('id, conversation_id, sender, body, image_url, reply_to, deleted, created_at')
            .single();
        return ChatMessage.fromRow(r);
      });

  Future<void> markRead(String conversationId) async {
    if (!Online.ready || me.isEmpty) return;
    try {
      await _db
          .from('conversation_members')
          .update(<String, dynamic>{'last_read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', conversationId)
          .eq('user_id', me);
    } catch (_) {}
  }

  /// Realtime inserts/updates of one conversation's messages. Call [RealtimeChannel.unsubscribe] when done.
  RealtimeChannel? watchMessages(String conversationId, void Function(ChatMessage m) onMessage) {
    if (!Online.ready) return null;
    final RealtimeChannel ch = _db.channel('social-conv:$conversationId');
    void handle(PostgresChangePayload p) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(p.newRecord);
      if (row.isEmpty) return;
      onMessage(ChatMessage.fromRow(row));
    }

    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: conversationId),
      callback: handle,
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: conversationId),
      callback: handle,
    );
    ch.subscribe();
    return ch;
  }

  /// Realtime pings for the inbox (any message / membership change visible to me).
  RealtimeChannel? watchInbox(void Function() onChange) {
    if (!Online.ready || me.isEmpty) return null;
    final RealtimeChannel ch = _db.channel('social-inbox:$me');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (PostgresChangePayload p) => onChange(),
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'conversation_members',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: me),
      callback: (PostgresChangePayload p) => onChange(),
    );
    ch.subscribe();
    return ch;
  }

  Future<void> unwatch(RealtimeChannel? ch) async {
    if (ch == null || !Online.ready) return;
    try {
      await _db.removeChannel(ch);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- clubs
  Future<SocialResult<List<ClubInfo>>> clubs({String query = ''}) => _run<List<ClubInfo>>(() async {
        final String t = query.trim().replaceAll('%', '');
        final Object? d = t.isEmpty
            ? await _db.from('club_list').select().order('power', ascending: false).limit(60)
            : await _db.from('club_list').select().or('name.ilike.%$t%,tag.ilike.%$t%').order('power', ascending: false).limit(60);
        return _rows(d).map(ClubInfo.fromRow).toList();
      });

  Future<SocialResult<ClubMembership?>> myClub() => _run<ClubMembership?>(() async {
        if (me.isEmpty) return null;
        final Map<String, dynamic>? r = await _db.from('club_members').select().eq('user_id', me).maybeSingle();
        return r == null ? null : ClubMembership.fromRow(r);
      });

  Future<SocialResult<List<SocialProfile>>> clubMembers(String clubId) => _run<List<SocialProfile>>(() async {
        final Object? d = await _db.from('club_members').select('user_id').eq('club_id', clubId).limit(100);
        final List<String> ids = _rows(d).map((Map<String, dynamic> r) => '${r['user_id']}').toList();
        final List<SocialProfile> ps = await _profilesByIds(ids);
        ps.sort((SocialProfile a, SocialProfile b) => b.xp.compareTo(a.xp));
        return ps;
      });

  /// Returns 'joined' or 'requested'.
  Future<SocialResult<String>> joinClub(String clubId) => _run<String>(() async {
        final dynamic r = await _db.rpc<dynamic>('join_club', params: <String, dynamic>{'p_club': clubId});
        unawaited(core.refreshProfile());
        return '${r ?? 'joined'}';
      });

  Future<SocialResult<bool>> leaveClub() => _run<bool>(() async {
        await _db.rpc<dynamic>('leave_club');
        unawaited(core.refreshProfile());
        return true;
      });
}
