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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Brand(),
                  const SizedBox(height: 36),
                  if (auth is AuthAwaitingTwoFactor)
                    _twoFactorBody(auth)
                  else if (_savedCardVisible(ref))
                    _savedAccountBody(ref.watch(savedAccountProvider)!)
                  else
                    _credentialsBody(),
                  const SizedBox(height: 28),
                  Text(
                    '非官方客户端，与 VRChat 官方无关\n登录凭据仅保存在本机',
                    style: TextStyle(
                      fontSize: AppText.label,
                      height: 1.7,
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                ],
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

  /// 上次登录的账号：头像 + 名字 + 继续登录 / 使用其他账号。
  Widget _savedAccountBody(SavedAccount saved) {
    final name = saved.displayName.isEmpty ? '上次登录的账号' : saved.displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '继续登录',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '使用上次登录的账号',
          style: TextStyle(
            fontSize: AppText.secondary,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: saved.avatarUrl.isEmpty
                      ? const ColoredBox(color: AppTheme.surfaceHigh)
                      : CachedNetworkImage(
                          imageUrl: saved.avatarUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              const ColoredBox(color: AppTheme.surfaceHigh),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppText.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      saved.username.isEmpty ? 'VRChat 账号' : saved.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.caption,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
          label: '继续登录',
          busy: _busy,
          onTap: _oneTapLogin,
        ),
        const SizedBox(height: 2),
        TextButton(
          onPressed: _busy ? null : _switchAccount,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.45),
            minimumSize: const Size(0, 38),
          ),
          child: const Text(
            '使用其他账号',
            style: TextStyle(fontSize: AppText.caption),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _ErrorText(_error!),
          const SizedBox(height: 2),
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
                padding: const EdgeInsets.symmetric(horizontal: 2),
                minimumSize: const Size(0, 34),
                foregroundColor: AppTheme.accent,
              ),
              child: const Text(
                '重新登录（只需输密码）',
                style: TextStyle(
                  fontSize: AppText.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
        const Text(
          '登录',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '使用 VRChat 账号或邮箱',
          style: TextStyle(
            fontSize: AppText.secondary,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 22),
        const _FieldLabel('用户名 / 邮箱'),
        const SizedBox(height: 8),
        TextField(
          controller: _username,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: '用户名或邮箱'),
        ),
        const SizedBox(height: 16),
        const _FieldLabel('密码'),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submitCredentials(),
          decoration: InputDecoration(
            hintText: '密码',
            suffixIcon: IconButton(
              iconSize: 20,
              color: Colors.white.withValues(alpha: 0.4),
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (_error != null || signedOutMessage != null) ...[
          const SizedBox(height: 14),
          _ErrorText(_error ?? signedOutMessage!),
        ],
        const SizedBox(height: 10),
        InkWell(
          onTap: () => setState(() => _rememberPassword = !_rememberPassword),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: _rememberPassword,
                    onChanged: (v) =>
                        setState(() => _rememberPassword = v ?? false),
                    visualDensity: VisualDensity.compact,
                    activeColor: AppTheme.accent,
                    checkColor: const Color(0xFF08131A),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '记住密码',
                  style: TextStyle(
                    fontSize: AppText.caption,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_rememberPassword) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              '仅保存在本机的加密存储里，换网络掉登录时可自动重新验证',
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.6,
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _PrimaryButton(
          label: '登录',
          busy: _busy,
          onTap: () => _submitCredentials(),
        ),
      ],
    );
  }

  Widget _twoFactorBody(AuthAwaitingTwoFactor state) {
    final emailOtp = state.types.contains(TwoFactorAuthType.emailOtp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '两步验证',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          state.hint,
          style: TextStyle(
            fontSize: AppText.secondary,
            height: 1.6,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        if (emailOtp) ...[
          const SizedBox(height: 6),
          Text(
            '验证码已发送到你的邮箱',
            style: TextStyle(
              fontSize: AppText.caption,
              color: AppTheme.accent.withValues(alpha: 0.8),
            ),
          ),
        ],
        const SizedBox(height: 22),
        const _FieldLabel('验证码'),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, letterSpacing: 6),
          onSubmitted: (_) => _busy ? null : _submitCode(),
          decoration: const InputDecoration(hintText: '6 位验证码'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorText(_error!),
        ],
        const SizedBox(height: 18),
        _PrimaryButton(
          label: '验证',
          busy: _busy,
          onTap: _submitCode,
        ),
        const SizedBox(height: 2),
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
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.45),
            minimumSize: const Size(0, 38),
          ),
          child: const Text('返回', style: TextStyle(fontSize: AppText.caption)),
        ),
        if (emailOtp) ...[
          const SizedBox(height: 8),
          Text(
            '没收到邮件？验证码有效期很短，重新登录一次可以再发一封。',
            style: TextStyle(
              fontSize: AppText.label,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
        ],
      ],
    );
  }
}

/// 左上角品牌区：小方块图标 + 名字，不做发光和大渐变。
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.pets, size: 21, color: AppTheme.accent),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Neko VRC',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'VRChat 第三方客户端',
              style: TextStyle(
                fontSize: AppText.label,
                color: Colors.white.withValues(alpha: 0.32),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 输入框上方的小标签，代替字段里的前缀图标。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppText.caption,
        fontWeight: FontWeight.w500,
        color: Colors.white.withValues(alpha: 0.45),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.error_outline,
            size: 15,
            color: Color(0xFFF87171),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: AppText.caption,
              height: 1.5,
              color: Color(0xFFFCA5A5),
            ),
          ),
        ),
      ],
    );
  }
}

/// 主按钮：实色、无光晕。
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: const Color(0xFF08131A),
        disabledBackgroundColor: AppTheme.accent.withValues(alpha: 0.35),
        disabledForegroundColor: const Color(0xFF08131A),
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontSize: AppText.body,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF08131A),
              ),
            )
          : Text(label),
    );
  }
}
