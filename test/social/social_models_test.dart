import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/social/social_models.dart';

void main() {
  group('level formula (floor(sqrt(xp/100))+1)', () {
    test('matches server values', () {
      expect(socialLevelForXp(0), 1);
      expect(socialLevelForXp(99), 1);
      expect(socialLevelForXp(100), 2);
      expect(socialLevelForXp(399), 2);
      expect(socialLevelForXp(400), 3);
      expect(socialLevelForXp(10000), 11);
      expect(socialLevelForXp(-50), 1);
    });
    test('xpForLevel is the inverse and progress is in range', () {
      for (int l = 1; l < 30; l++) {
        expect(socialLevelForXp(socialXpForLevel(l)), l);
      }
      expect(socialLevelProgress(250), closeTo(0.5, 1e-9));
      expect(socialLevelProgress(0), 0);
    });
  });

  test('SocialProfile.fromRow maps live profiles row', () {
    final SocialProfile p = SocialProfile.fromRow(<String, dynamic>{
      'id': 'u1',
      'username': 'Nova',
      'avatar': 'club3',
      'avatar_url': '',
      'bio': 'hi',
      'xp': 450,
      'level': 99, // ignored: level is derived from xp
      'club_id': null,
      'online_at': '2026-11-14T10:00:00Z',
      'wins': 3,
    });
    expect(p.id, 'u1');
    expect(p.displayName, 'Nova');
    expect(p.avatarUrl, isNull);
    expect(p.level, 3);
    expect(p.wins, 3);
    expect(p.isOnlineAt(DateTime.parse('2026-11-14T10:01:00Z')), isTrue);
    expect(p.isOnlineAt(DateTime.parse('2026-11-14T11:00:00Z')), isFalse);
  });

  test('updatePatch only touches writable columns', () {
    final Map<String, dynamic> patch = SocialProfile.updatePatch(username: ' Nova ', bio: '  ', avatarUrl: 'https://x/y.png');
    expect(patch, <String, dynamic>{'username': 'Nova', 'bio': null, 'avatar_url': 'https://x/y.png'});
    expect(SocialProfile.updatePatch(), isEmpty);
  });

  test('InboxItem.fromRow maps inbox view (dm with peer + last message)', () {
    final InboxItem i = InboxItem.fromRow(<String, dynamic>{
      'id': 'c1',
      'kind': 'dm',
      'title': null,
      'last_message_at': '2026-11-14T09:00:00Z',
      'muted': false,
      'last_message': <String, dynamic>{'body': 'salam', 'sender': 'u2', 'created_at': '2026-11-14T09:00:00Z'},
      'unread': 2,
      'peer': <String, dynamic>{'id': 'u2', 'username': 'Orbit', 'avatar': 'club1'},
      'members': 2,
    });
    expect(i.isDm, isTrue);
    expect(i.displayTitle('x'), 'Orbit');
    expect(i.lastBody, 'salam');
    expect(i.lastSender, 'u2');
    expect(i.unread, 2);

    final InboxItem g = InboxItem.fromRow(<String, dynamic>{'id': 'c2', 'kind': 'group', 'title': '', 'last_message': null, 'peer': null});
    expect(g.displayTitle('Fallback'), 'Fallback');
    expect(g.lastBody, isNull);
  });

  test('ChatMessage mapping, insert row and merge', () {
    final ChatMessage a = ChatMessage.fromRow(<String, dynamic>{
      'id': 5,
      'conversation_id': 'c1',
      'sender': 'u1',
      'body': 'one',
      'deleted': false,
      'created_at': '2026-11-14T09:00:00Z',
    });
    final ChatMessage b = ChatMessage.fromRow(<String, dynamic>{'id': '3', 'conversation_id': 'c1', 'sender': 'u2', 'body': 'zero'});
    expect(a.mine('u1'), isTrue);
    expect(b.id, 3);
    List<ChatMessage> list = mergeMessage(<ChatMessage>[], a);
    list = mergeMessage(list, b);
    list = mergeMessage(list, a);
    expect(list.map((ChatMessage m) => m.id).toList(), <int>[3, 5]);
    final ChatMessage del = ChatMessage.fromRow(<String, dynamic>{'id': 5, 'conversation_id': 'c1', 'deleted': true});
    expect(mergeMessage(list, del).map((ChatMessage m) => m.id).toList(), <int>[3]);
    expect(ChatMessage.insertRow(conversationId: 'c1', sender: 'u1', body: ' hi '),
        <String, dynamic>{'conversation_id': 'c1', 'sender': 'u1', 'body': 'hi'});
  });

  test('ClubInfo + FriendRequestInfo mappers', () {
    final ClubInfo c = ClubInfo.fromRow(<String, dynamic>{
      'id': 'k1',
      'name': 'Stars',
      'tag': 'STR',
      'emblem': '',
      'join_policy': 'request',
      'min_level': 3,
      'max_members': 5,
      'members': 5,
      'power': 1200,
      'conversation_id': 'conv9',
    });
    expect(c.full, isTrue);
    expect(c.open, isFalse);
    expect(c.inviteOnly, isFalse);
    expect(c.conversationId, 'conv9');

    final FriendRequestInfo r = FriendRequestInfo.fromRow(<String, dynamic>{'from_user': 'a', 'to_user': 'me', 'status': 'pending'});
    expect(r.pending, isTrue);
    expect(r.dirFor('me'), FriendRequestDir.incoming);
    expect(r.otherOf('me'), 'a');
  });
}
