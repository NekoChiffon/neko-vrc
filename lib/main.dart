import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/core/vrc_client.dart';
import 'src/providers/friends_provider.dart';
import 'src/services/friend_notifier.dart';
import 'src/services/service_status.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final client = await VrcClient.create();
  await FriendNotifier.instance.init();
  // VRChat 服务状态异常 / 恢复的提醒。
  await ServiceStatusWatcher.instance.start();

  runApp(
    ProviderScope(
      overrides: [vrcClientProvider.overrideWithValue(client)],
      child: const NekoVrcApp(),
    ),
  );
}
