import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/storage/local_store.dart';
import '../data/orbit_repository.dart';
import '../data/orbit_shared_inbox.dart';
import '../models/orbit_models.dart';

/// Swap for an online implementation later.
final orbitRepositoryProvider = Provider<OrbitRepository>((ref) => LocalOrbitRepository(LocalStore.instance));

final orbitControllerProvider = ChangeNotifierProvider<OrbitController>((ref) => OrbitController(
      ref.watch(orbitRepositoryProvider),
      OrbitSharedInbox(LocalStore.instance),
      ownerId: ref.read(profileProvider).explorerId,
    ));

class OrbitChatSummary {
  OrbitChatSummary(this.chat, this.last, this.unread);
  final OrbitChat chat;
  final OrbitMessage? last;
  final int unread;
}

/// XP rules for messages: small, capped per day so chatting can't be farmed.
class OrbitXpRules {
  OrbitXpRules._();
  static const int xpPerMessage = 2;
  static const int dailyRewardedMessages = 30;
  static const String kDay = 'orbit.xp_day';
  static const String kCount = 'orbit.xp_count';

  /// Returns true (and consumes a slot) if this message still earns XP today.
  static Future<bool> consumeSlot(LocalStore store, DateTime now) async {
    final day = '${now.year}-${now.month}-${now.day}';
    var count = store.getInt(kCount) ?? 0;
    if (store.getString(kDay) != day) {
      count = 0;
      await store.setString(kDay, day);
    }
    if (count >= dailyRewardedMessages) return false;
    await store.setInt(kCount, count + 1);
    return true;
  }
}

class OrbitController extends ChangeNotifier {
  OrbitController(this.repo, this.inbox, {required this.ownerId}) {
    refresh();
  }

  final OrbitRepository repo;
  final OrbitSharedInbox inbox;
  final String ownerId;

  bool loading = true;
  bool _disposed = false;
  List<OrbitChatSummary> summaries = <OrbitChatSummary>[];
  List<SharedItem> inboxItems = <SharedItem>[];
  final Map<String, List<OrbitMessage>> _messages = <String, List<OrbitMessage>>{};

  int get totalUnread => summaries.fold<int>(0, (int a, OrbitChatSummary s) => a + s.unread);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  OrbitChat? chatById(String id) {
    for (final s in summaries) {
      if (s.chat.id == id) return s.chat;
    }
    return null;
  }

  List<OrbitMessage> messagesOf(String chatId) => _messages[chatId] ?? const <OrbitMessage>[];

  OrbitMessage? messageById(String chatId, String? id) {
    if (id == null) return null;
    for (final m in messagesOf(chatId)) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> refresh() async {
    final chats = await repo.chats(ownerId: ownerId);
    final out = <OrbitChatSummary>[];
    for (final c in chats) {
      out.add(OrbitChatSummary(c, await repo.lastMessage(c.id), await repo.unreadCount(c.id, ownerId)));
    }
    summaries = out;
    inboxItems = inbox.read();
    for (final id in _messages.keys.toList()) {
      _messages[id] = await repo.messages(id);
    }
    loading = false;
    _notify();
  }

  Future<void> openChat(String chatId) async {
    _messages[chatId] = await repo.messages(chatId);
    await repo.markRead(chatId);
    await refresh();
  }

  void closeChat(String chatId) {
    _messages.remove(chatId);
  }

  Future<OrbitMessage?> send(
    String chatId, {
    required String authorName,
    OrbitMessageKind kind = OrbitMessageKind.text,
    String text = '',
    Map<String, dynamic>? payload,
    String? replyToId,
  }) async {
    if (kind == OrbitMessageKind.text && text.trim().isEmpty) return null;
    final m = await repo.send(
      chatId: chatId,
      authorId: ownerId,
      authorName: authorName,
      kind: kind,
      text: text,
      payload: payload,
      replyToId: replyToId,
    );
    await refresh();
    return m;
  }

  /// Bumps 'orbit.sent' and awards capped XP. Returns the award outcome.
  Future<AwardOutcome> reward(ProfileService profile) async {
    profile.bump('orbit.sent');
    final bool earns = await OrbitXpRules.consumeSlot(LocalStore.instance, DateTime.now());
    final sent = profile.counter('orbit.sent');
    if (sent == 1 || sent % 25 == 0) {
      profile.logActivity('orbit', '$sent پیام در Orbit Network', '$sent messages in Orbit Network');
    }
    return profile.award('orbit.message', xp: earns ? OrbitXpRules.xpPerMessage : 0);
  }

  Future<bool> edit(String chatId, String id, String text) async {
    final ok = await repo.editMessage(chatId, id, text);
    await refresh();
    return ok;
  }

  Future<void> delete(String chatId, String id) async {
    await repo.deleteMessage(chatId, id);
    await refresh();
  }

  Future<void> togglePin(String chatId, String id) async {
    await repo.togglePin(chatId, id);
    await refresh();
  }

  Future<void> toggleStar(String chatId, String id) async {
    await repo.toggleStar(chatId, id);
    await refresh();
  }

  Future<OrbitChat> createChat({
    required OrbitChatKind kind,
    required String name,
    required String ownerName,
    String description = '',
    String badgeId = '',
  }) async {
    final c = await repo.createChat(
      kind: kind,
      name: name,
      ownerId: ownerId,
      ownerName: ownerName,
      description: description,
      badgeId: badgeId,
    );
    await refresh();
    return c;
  }

  Future<void> updateChat(OrbitChat chat) async {
    await repo.updateChat(chat);
    await refresh();
  }

  Future<void> deleteChat(String id) async {
    await repo.deleteChat(id);
    _messages.remove(id);
    await refresh();
  }

  Future<List<OrbitMessage>> search(String q) => repo.search(q);
  Future<List<OrbitMessage>> starred() => repo.starred();

  /// Delivers a shared item into a chat as a rich card and removes it from the inbox.
  Future<void> deliverShared(SharedItem item, String chatId, {required String authorName}) async {
    await repo.send(
      chatId: chatId,
      authorId: ownerId,
      authorName: authorName,
      kind: item.type == SharedItem.gameInvite ? OrbitMessageKind.invite : OrbitMessageKind.shared,
      text: item.text,
      payload: item.type == SharedItem.gameInvite
          ? <String, dynamic>{'gameId': item.gameId ?? '', 'text': item.text}
          : item.toJson(),
    );
    await inbox.remove(item.key);
    await refresh();
  }

  Future<void> dismissShared(SharedItem item) async {
    await inbox.remove(item.key);
    await refresh();
  }
}
