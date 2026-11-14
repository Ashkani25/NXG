import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/storage/local_store.dart';
import 'online/auth_links.dart';
import 'online/online_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStore.init();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF050818),
  ));
  runApp(const ProviderScope(child: NexoraApp()));
  // Online: Supabase (session persisted + auto-refreshed by supabase_flutter) and auth deep links.
  // Started after the first frame so a slow / missing network never delays the offline app.
  unawaited(OnlineCore.instance.boot().then((_) => AuthLinks.start()));
}
