/// Voice chat over LiveKit — port of src/net/voice.ts.
/// Token: supabase.functions.invoke('livekit-token', {room_id}) → {url, token, canPublish}.
/// One session per room; emits [VoiceState] for the UI and never throws to callers.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

enum VoiceStatus { off, connecting, on, error }

@immutable
class VoiceState {
  const VoiceState({
    this.status = VoiceStatus.off,
    this.mic = false,
    this.speaker = true,
    this.canPublish = false,
    this.speaking = const [],
    this.error,
  });
  final VoiceStatus status;
  final bool mic, speaker, canPublish;
  /// identities (user ids) currently speaking
  final List<String> speaking;
  final String? error;

  VoiceState copyWith({VoiceStatus? status, bool? mic, bool? speaker, bool? canPublish, List<String>? speaking, Object? error = _k}) =>
      VoiceState(
        status: status ?? this.status,
        mic: mic ?? this.mic,
        speaker: speaker ?? this.speaker,
        canPublish: canPublish ?? this.canPublish,
        speaking: speaking ?? this.speaking,
        error: identical(error, _k) ? this.error : error as String?,
      );
  static const _k = Object();
}

/// Persian message for a livekit-token failure (same rules as voice.ts).
String voiceTokenErrorFa(int status, Object? body) {
  final err = body is Map ? body['error'] : null;
  if (status == 503 || err == 'voice_not_configured') return 'چت صوتی هنوز فعال نشده';
  if (status == 403) return 'برای چت صوتی باید داخل اتاق باشی';
  return 'اتصال به سرور صدا ناموفق بود';
}

class VoiceException implements Exception {
  VoiceException(this.fa);
  final String fa;
  @override
  String toString() => fa;
}

/// Platform support check (voice.ts voiceSupport): web is not supported.
String? voiceUnsupportedReason() => kIsWeb ? 'چت صوتی فقط روی موبایل' : null;

class VoiceSession extends ChangeNotifier {
  VoiceSession(this.roomId);
  final String roomId;

  VoiceState _state = const VoiceState();
  VoiceState get state => _state;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  bool _alive = true;

  void _set(VoiceState s) {
    if (!_alive) return;
    _state = s;
    notifyListeners();
  }

  Future<void> join() async {
    final unsupported = voiceUnsupportedReason();
    if (unsupported != null) {
      _set(_state.copyWith(status: VoiceStatus.error, error: unsupported));
      return;
    }
    if (_state.status == VoiceStatus.connecting || _state.status == VoiceStatus.on) return;
    _set(_state.copyWith(status: VoiceStatus.connecting, error: null));
    try {
      Map<String, dynamic> data;
      try {
        final res = await Online.client.functions.invoke('livekit-token', body: {'room_id': roomId});
        if (res.status >= 400) throw VoiceException(voiceTokenErrorFa(res.status, res.data));
        data = Map<String, dynamic>.from(res.data as Map);
      } on FunctionException catch (e) {
        throw VoiceException(voiceTokenErrorFa(e.status, e.details));
      } on VoiceException {
        rethrow;
      } catch (_) {
        throw VoiceException('اتصال به سرور صدا ناموفق بود');
      }
      if (!_alive) return;
      var canPublish = data['canPublish'] == true;
      if (canPublish && defaultTargetPlatform == TargetPlatform.android) {
        final g = await Permission.microphone.request();
        if (!g.isGranted) canPublish = false;
      }
      final room = lk.Room(roomOptions: const lk.RoomOptions(adaptiveStream: false, dynacast: false));
      _room = room;
      final l = room.createListener();
      _listener = l;
      l
        ..on<lk.ActiveSpeakersChangedEvent>((e) => _set(_state.copyWith(speaking: e.speakers.map((p) => p.identity).toList())))
        ..on<lk.RoomDisconnectedEvent>((_) {
          if (_alive) _set(_state.copyWith(status: VoiceStatus.off, mic: false, speaking: const []));
        })
        ..on<lk.TrackSubscribedEvent>((e) {
          try {
            if (e.track is lk.RemoteAudioTrack) e.track.mediaStreamTrack.enabled = _state.speaker;
          } catch (_) {}
        });
      await room.connect('${data['url']}', '${data['token']}', connectOptions: const lk.ConnectOptions(autoSubscribe: true));
      if (!_alive) {
        await room.disconnect();
        return;
      }
      _set(_state.copyWith(status: VoiceStatus.on, canPublish: canPublish, mic: false));
      if (canPublish) await setMic(true);
    } catch (e) {
      final msg = e is VoiceException ? e.fa : 'اتصال صدا ناموفق بود';
      _set(_state.copyWith(status: VoiceStatus.error, error: msg));
      await leave(keepError: true);
    }
  }

  Future<void> setMic(bool on) async {
    final r = _room;
    if (r == null || !_state.canPublish) return;
    try {
      await r.localParticipant?.setMicrophoneEnabled(on);
      _set(_state.copyWith(mic: on));
    } catch (_) {
      _set(_state.copyWith(mic: false));
    }
  }

  void setSpeaker(bool on) {
    _set(_state.copyWith(speaker: on));
    try {
      for (final p in _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[]) {
        for (final pub in p.audioTrackPublications) {
          pub.track?.mediaStreamTrack.enabled = on;
        }
      }
    } catch (_) {}
  }

  Future<void> leave({bool keepError = false}) async {
    final r = _room;
    _room = null;
    final l = _listener;
    _listener = null;
    try {
      await l?.dispose();
    } catch (_) {}
    try {
      await r?.disconnect();
      await r?.dispose();
    } catch (_) {}
    if (!keepError) _set(_state.copyWith(status: VoiceStatus.off, mic: false, speaking: const []));
  }

  void destroy() {
    if (!_alive) return;
    leave();
    _alive = false;
    dispose();
  }
}
