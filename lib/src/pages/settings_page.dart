import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../models/friend_presence.dart';
import '../providers/friends_provider.dart';
import '../providers/saved_account.dart';
import '../services/friend_notifier.dart';
import '../theme.dart';
import 'cosmetics_picker_page.dart';
import 'favorites_page.dart';
import 'notifications_page.dart';

/// 设置页。原先挤在「我」页底部的那些运维信息都收到这里。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final friends = ref.watch(friendsProvider);
    final me = auth is AuthSignedIn ? auth.user : null;
    final accounts = ref.watch(savedAccountsProvider);
    final otherAccounts = me == null
        ? accounts
        : accounts.where((a) => a.userId != me.id).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          // ---- 账号 ----
          _Card(
            title: '账号',
            children: [
              if (me != null)
                _Row(
                  icon: Icons.person_outline,
                  label: me.displayName,
                  value: '${me.status.value} · ${FriendPresence.trustRankFromTags(me.tags) ?? '—'}',
                ),
              const SizedBox(height: 6),
              if (otherAccounts.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () =>
                      _showAccountSwitcher(context, ref, otherAccounts),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: BorderSide(
                      color: AppTheme.accent.withValues(alpha: 0.35),
                    ),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  label: const Text('切换账号'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: () => _confirmLogout(context, ref),
                icon: const Icon(Icons.logout, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFCA5A5),
                  side: BorderSide(color: const Color(0xFFF87171).withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(44),
                ),
                label: const Text('退出登录'),
              ),
            ],
          ),

          // ---- 提醒 ----
          _Card(
            title: '提醒',
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: FriendNotifier.instance.enabled,
                builder: (context, enabled, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged: (v) => _toggleFriendNotify(context, v),
                  title: const Text(
                    '好友上线提醒',
                    style: TextStyle(fontSize: AppText.secondary),
                  ),
                  subtitle: Text(
                    '好友进入 VRChat 时弹一条系统通知。\n'
                    '只在 App 运行时生效；Web 端上下线不提醒。',
                    style: TextStyle(
                      fontSize: AppText.label,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ---- 连接 ----
          _Card(
            title: '连接',
            children: [
              _Row(
                icon: Icons.people_outline,
                label: '好友',
                value: '${friends.friends.length} 人（${friends.onlineCount} 在线）',
              ),
              _Row(
                icon: Icons.sync,
                label: '上次同步',
                value: friends.lastSyncedAt == null ? '尚未同步' : _hhmm(friends.lastSyncedAt!),
              ),
              _Row(
                icon: friends.pipelineAlive ? Icons.bolt : Icons.bolt_outlined,
                label: '实时通道',
                value: friends.lastEventAt == null
                    ? '等待推送'
                    : '${_hhmm(friends.lastEventAt!)} 有推送',
                valueColor: friends.pipelineAlive ? const Color(0xFF4ADE80) : Colors.white38,
              ),
              if (!friends.pipelineAlive) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => ref.read(friendsProvider.notifier).reconnectPipeline(),
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('重连实时通道', style: TextStyle(fontSize: AppText.caption)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ---- 快捷入口 ----
          _Card(
            title: '快捷',
            children: [
              _Entry(
                icon: Icons.auto_awesome,
                label: '个人资料装饰',
                hint: '头像框、名字牌、资料特效',
                onTap: me == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CosmeticsPickerPage(userId: me.id),
                          ),
                        ),
              ),
              _Entry(
                icon: Icons.star_border,
                label: '收藏的世界',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const FavoritesPage()),
                ),
              ),
              _Entry(
                icon: Icons.notifications_none,
                label: '通知',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
                ),
              ),
            ],
          ),

          // ---- 关于 ----
          _Card(
            title: '关于',
            children: [
              _Row(icon: Icons.info_outline, label: '版本', value: AppInfo.version),
              _Row(
                icon: Icons.dns_outlined,
                label: '接口',
                value: 'api.vrchat.cloud',
              ),
              const SizedBox(height: 10),
              Text(
                '个人学习用途的非官方客户端，与 VRChat Inc. 无关。\n'
                '请遵守 VRChat 的 API 使用规范：不要高频轮询、不要滥用接口。',
                style: TextStyle(
                  fontSize: AppText.label,
                  height: 1.7,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFriendNotify(BuildContext context, bool value) async {
    if (value) {
      final granted = await FriendNotifier.instance.requestPermission();
      if (!granted) {
        if (context.mounted) {
          _toast(context, '系统没有给通知权限，请到系统设置里手动允许');
        }
        return;
      }
    }
    await FriendNotifier.instance.setEnabled(value);
  }

  /// 已保存的账号列表，点一下切换到那个账号。
  ///
  /// 只有当那个账号还留着密码（登录时勾了「记住密码」）才能无感切换，
  /// 否则提示退出后手动登录。
  Future<void> _showAccountSwitcher(
    BuildContext context,
    WidgetRef ref,
    List<SavedAccount> accounts,
  ) async {
    final headers = ref.read(imageHeadersProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, size: 16, color: AppTheme.accent),
                  SizedBox(width: 8),
                  Text(
                    '切换到其他账号',
                    style: TextStyle(
                      fontSize: AppText.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            for (final account in accounts)
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _switchAccount(context, ref, account);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _AccountAvatar(account: account, headers: headers),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.displayName.isEmpty
                                  ? '未命名账号'
                                  : account.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppText.body,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (account.username.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                account.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppText.label,
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Text(
                        '切换',
                        style: TextStyle(
                          fontSize: AppText.caption,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _switchAccount(
    BuildContext context,
    WidgetRef ref,
    SavedAccount account,
  ) async {
    if (account.username.isEmpty) {
      _toast(context, '这个账号没有记录登录名，请退出后手动登录');
      return;
    }
    final pwd = await SavedPassword.read(account.userId);
    if (pwd == null) {
      if (context.mounted) _toast(context, '没有保存这个账号的密码，请退出后手动登录');
      return;
    }
    await ref.read(authProvider.notifier).signOut();
    final err = await ref.read(authProvider.notifier).signIn(account.username, pwd);
    if (err != null && context.mounted) {
      _toast(context, '切换失败：$err');
    }
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('本机保存的登录态会被清除，下次需要重新输入密码。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('算了')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authProvider.notifier).signOut();
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account, required this.headers});

  final SavedAccount account;
  final Map<String, String> headers;

  static const double _size = 38;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: _size,
      height: _size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surfaceHigh,
      ),
      child: const Icon(Icons.person, size: 18, color: Colors.white24),
    );

    if (account.avatarUrl.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: account.avatarUrl,
        httpHeaders: headers,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xE6151B23),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: AppText.label,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.caption,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: AppText.caption, color: valueColor ?? Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.45)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppText.secondary,
                      color: onTap == null
                          ? Colors.white24
                          : Colors.white70,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint!,
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
