import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/pages/home_page.dart';
import 'src/pages/login_page.dart';
import 'src/pages/welcome_page.dart';
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
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: switch (auth) {
        AuthUnknown() => const _SplashPage(),
        AuthSignedOut() || AuthAwaitingTwoFactor() => const LoginPage(),
        AuthSignedIn(:final user) => ref.watch(welcomePendingProvider)
            ? WelcomePage(user: user)
            : const HomePage(),
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
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.accent, AppTheme.accentAlt],
                ),
              ),
              child: const Icon(Icons.pets, size: 36, color: Color(0xFF0B0F14)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
