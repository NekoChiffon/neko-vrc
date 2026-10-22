import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/friends_provider.dart';
import '../providers/saved_account.dart';
import '../theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  /// 用户点了「切换账号」后用表单登录。
  bool _forceForm = false;

  /// 记住密码（存在系统加密存储里），换网络掉登录时才能「一键走到验证码」。
  bool _rememberPassword = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submitCredentials() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '用户名和密码都要填');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(authProvider.notifier).signIn(username, password);
    if (!mounted) return;

    // 成功或需要 2FA 时都算凭据有效，可以记住密码。
    final auth = ref.read(authProvider);
    if (_rememberPassword &&
        (err == null || auth is AuthAwaitingTwoFactor)) {
      final uid = auth is AuthSignedIn
          ? auth.user.id
          : (ref.read(savedAccountProvider)?.userId ?? '');
      if (uid.isNotEmpty) {
        await SavedPassword.save(uid, password);
      } else if (auth is AuthAwaitingTwoFactor) {
        // 2FA 阶段还没有 userId：先按用户名存，登录完成后再迁移
        await SavedPassword.save('pending_$username', password);
      }
    }

    setState(() {
      _busy = false;
      _error = err;
      if (err == null) _password.clear();
    });
  }

  Future<void> _submitCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(authProvider.notifier).submitTwoFactor(code);
    if (!mounted) return;

    if (err == null) {
      // 2FA 通过后才有 userId：把待迁移的密码挪到正式记录下。
      final auth = ref.read(authProvider);
      if (auth is AuthSignedIn) {
        final pending = await SavedPassword.read('pending_${_username.text}');
        if (pending != null) {
          await SavedPassword.save(auth.user.id, pending);
          await SavedPassword.clear('pending_${_username.text}');
        }
      }
    }

    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.62),
            radius: 1.15,
            colors: [Color(0xFF16262F), Color(0xFF0B0F14)],
          ),
        ),
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Logo(),
                  const SizedBox(height: 28),
                  if (auth is AuthAwaitingTwoFactor)
                    _twoFactorBody(auth)
                  else if (_savedCardVisible(ref))
                    _savedAccountBody(ref.watch(savedAccountProvider)!)
                  else
                    _credentialsBody(),
                  const SizedBox(height: 24),
                  Text(
                    '非官方应用 · 数据来自 VRChat 公开 API\n登录凭据只在本机使用，不会经过任何第三方服务器',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppText.label,
                      height: 1.6,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  bool _savedCardVisible(WidgetRef ref) {
    if (_forceForm) return false;
    return ref.watch(savedAccountProvider) != null;
  }

  Future<void> _oneTapLogin() async {
    final saved = ref.read(savedAccountProvider);
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
    // 1. 先试 cookie（同网络环境下直接进去）
    await ref.read(authProvider.notifier).bootstrap();
    if (!mounted) return;
    if (ref.read(authProvider) is AuthSignedIn) {
      setState(() => _busy = false);
      return;
    }

    // 2. cookie 失效（换网络）→ 用记住的密码重登，直接跳到验证码那一步
    if (saved != null && saved.username.isNotEmpty) {
      final pwd = await SavedPassword.read(saved.userId) ??
          await SavedPassword.read('pending_${saved.username}');
      if (pwd != null && pwd.isNotEmpty) {
        final err = await ref
            .read(authProvider.notifier)
            .signIn(saved.username, pwd);
        if (!mounted) return;

        final auth = ref.read(authProvider);
        // 需要 2FA 时页面会自动切到验证码界面，这里不算失败。
        if (err == null || auth is AuthAwaitingTwoFactor) {
          setState(() {
            _busy = false;
            _error = null;
          });
          return;
        }

        // 密码失效（改过密码）→ 清掉记住的密码，引导手动登录
        await SavedPassword.clear(saved.userId);
        setState(() {
          _busy = false;
          _error = '记住的密码已失效，请点「重新登录」手动输入一次';
        });
        return;
      }
    }

    setState(() {
      _busy = false;
      _error = '自动登录失败。切换网络后凭据会失效，需要重新验证一次';
    });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '网络请求失败，检查一下代理或网络再试';
      });
    }
  }

  Future<void> _switchAccount() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final account = ref.read(savedAccountProvider);
    final username = account?.username ?? '';
    if (account != null) {
      await SavedPassword.clear(account.userId);
    }
    await ref.read(authProvider.notifier).signOut();
    await ref.read(savedAccountProvider.notifier).clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _forceForm = true;
      _username.text = username;
    });
  }

  /// 上次登录的账号卡片：头像 + 名字 + 一键登录 / 切换账号。
  Widget _savedAccountBody(SavedAccount saved) {
    final name = saved.displayName.isEmpty ? '上次登录的账号' : saved.displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: saved.avatarUrl.isEmpty
                      ? ColoredBox(
                          color: AppTheme.surfaceHigh,
                          child: Icon(
                            Icons.person,
                            size: 28,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: saved.avatarUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const ColoredBox(
                            color: AppTheme.surfaceHigh,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '上次登录的账号',
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.verified_user_outlined,
                size: 20,
                color: AppTheme.accent.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GradientButton(
          label: '一键登录',
          busy: _busy,
          onTap: _oneTapLogin,
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _busy ? null : _switchAccount,
          child: Text(
            '切换账号',
            style: TextStyle(
              fontSize: AppText.secondary,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF87171).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: const Color(0xFFF87171).withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: AppText.label,
                    height: 1.6,
                    color: Color(0xFFFCA5A5),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _username.text = saved.username;
                              _forceForm = true;
                              _error = null;
                            }),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(
                      '重新登录（只需输密码）',
                      style: TextStyle(
                        fontSize: AppText.caption,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _credentialsBody() {
    final signedOutMessage = switch (ref.watch(authProvider)) {
      AuthSignedOut(:final message) => message,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _username,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'VRChat 用户名或邮箱',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submitCredentials(),
          decoration: InputDecoration(
            hintText: '密码',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (_error != null || signedOutMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorText(_error ?? signedOutMessage!),
        ],
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _rememberPassword = !_rememberPassword),
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _rememberPassword,
                    onChanged: (v) =>
                        setState(() => _rememberPassword = v ?? false),
                    visualDensity: VisualDensity.compact,
                    activeColor: AppTheme.accent,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '记住密码（换网络掉登录时可一键重新验证）',
                    style: TextStyle(
                      fontSize: AppText.label,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GradientButton(
          label: '登录',
          busy: _busy,
          onTap: () => _submitCredentials(),
        ),
      ],
    );
  }

  Widget _twoFactorBody(AuthAwaitingTwoFactor state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '两步验证',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          state.hint,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppText.caption,
            height: 1.6,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        if (state.types.contains(TwoFactorAuthType.emailOtp)) ...[
          const SizedBox(height: 8),
          Text(
            '验证码已发送到你的邮箱，填进来即可',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppText.label,
              color: AppTheme.accent.withValues(alpha: 0.8),
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 6),
          onSubmitted: (_) => _busy ? null : _submitCode(),
          decoration: const InputDecoration(hintText: '000000'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorText(_error!),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submitCode,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('验证'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  ref.read(authProvider.notifier).cancelTwoFactor();
                  setState(() {
                    _error = null;
                    _code.clear();
                  });
                },
          child: const Text('返回'),
        ),
        if (state.types.contains(TwoFactorAuthType.emailOtp))
          Text(
            '没收到邮件？VRChat 的验证码有效期很短，重新登录一次可以再发一封。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.label, color: Colors.white.withValues(alpha: 0.3)),
          ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // 背后一圈柔光
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accent.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.accent, AppTheme.accentAlt],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.pets, size: 40, color: Color(0xFF0B0F14)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Neko VRC',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),
        Text(
          '看看好友都在哪个世界',
          style: TextStyle(fontSize: AppText.secondary, color: Colors.white.withValues(alpha: 0.4)),
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF87171).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFF87171)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: AppText.caption, color: Color(0xFFFCA5A5)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 渐变主按钮（FilledButton 没法直接上渐变）。
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: busy
                ? [
                    AppTheme.accent.withValues(alpha: 0.5),
                    AppTheme.accentAlt.withValues(alpha: 0.5),
                  ]
                : [AppTheme.accent, AppTheme.accentAlt],
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: busy
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF0B0F14),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: AppText.body,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Color(0xFF0B0F14),
                  ),
                ),
        ),
      ),
    );
  }
}
