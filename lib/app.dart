import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/pages/home_page.dart';
import 'src/pages/login_page.dart';
import 'src/pages/welcome_page.dart';
import 'src/providers/appearance.dart';
import 'src/providers/friends_provider.dart';
import 'src/theme.dart';

class NekoVrcApp extends ConsumerStatefulWidget {
  const NekoVrcApp({super.key});

  @override
  ConsumerState<NekoVrcApp> createState() => _NekoVrcAppState();
}

class _NekoVrcAppState extends ConsumerState<NekoVrcApp> {
  @override
  void initState() {
    super.initState();
    // 冷启动先试试本地 cookie 还能不能用，不能用就落到登录页。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return MaterialApp(
      title: 'Neko VRC',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(appearanceProvider),
      home: switch (auth) {
        AuthUnknown() => const _SplashPage(),
        AuthSignedOut() || AuthAwaitingTwoFactor() => const LoginPage(),
        AuthSignedIn(:final user) => ref.watch(welcomePendingProvider)
            ? WelcomePage(user: user)
            : HomePage(),
      },
    );
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.appColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.pets, size: 22, color: context.appColors.accent),
            ),
            const SizedBox(height: 14),
            const Text(
              'Neko VRC',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            // 一条细进度线，代替屏幕正中的转圈。
            SizedBox(
              width: 96,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: context.appColors.ink(0.06),
                  color: context.appColors.ink(0.22),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '正在检查登录状态',
              style: TextStyle(
                fontSize: AppText.label,
                color: context.appColors.ink(0.28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
