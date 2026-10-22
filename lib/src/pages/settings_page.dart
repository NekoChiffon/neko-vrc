import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../models/friend_presence.dart';
import '../providers/friends_provider.dart';
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
