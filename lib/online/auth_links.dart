/// Auth deep links (nexora://auth#access_token=…&refresh_token=…&type=signup|recovery) — the
/// e-mail confirmation / password-recovery redirect used by Godot and Expo (Supa.AUTH_REDIRECT).
/// The Android intent filter for nexora://auth is injected by CI (see .github/workflows).
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'online_core.dart';

class AuthLinks {
  AuthLinks._();
  static StreamSubscription<Uri>? _sub;
  static String _last = '';

  /// Persian result of the last handled link ('' = ok) for the UI to toast; null = none yet.
  static final ValueNotifier<String?> lastResult = ValueNotifier<String?>(null);

  static Future<void> start() async {
    if (_sub != null || kIsWeb) return;
    try {
      final AppLinks links = AppLinks();
      _sub = links.uriLinkStream.listen(_handle, onError: (Object _) {});
      final Uri? first = await links.getInitialLink();
      if (first != null) await _handle(first);
    } catch (e) {
      debugPrint('NEXORA auth links unavailable: $e');
    }
  }

  static Future<void> _handle(Uri uri) async {
    if (uri.scheme != 'nexora' || uri.host != 'auth') return;
    final String s = uri.toString();
    if (s == _last) return;
    _last = s;
    final OnlineResult r = await OnlineCore.instance.handleAuthUrl(uri);
    lastResult.value = r.ok ? '' : r.error;
  }
}
