import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/core/vrc_client.dart';
import 'src/providers/friends_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final client = await VrcClient.create();

  runApp(
    ProviderScope(
      overrides: [vrcClientProvider.overrideWithValue(client)],
      child: const NekoVrcApp(),
    ),
  );
}
