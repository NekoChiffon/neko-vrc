import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../core/app_info.dart';
import '../models/friend_presence.dart';
import '../providers/appearance.dart';
import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../providers/saved_account.dart';
import '../services/friend_notifier.dart';
import '../theme.dart';
import '../widgets/frosted_app_bar.dart';
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

    final list = ListView(
      // 顶部让出毛玻璃顶栏的高度。
      padding: EdgeInsets.fromLTRB(
        14,
        frostedAppBarInset(context) + 8,
        14,
        32,
      ),
      children: [
          // ---- 外观 ----
          _Card(
            title: '外观',
            children: [
              const SizedBox(height: 2),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ],
                selected: {ref.watch(appearanceProvider)},
                onSelectionChanged: (selection) {
                  ref.read(appearanceProvider.notifier).setMode(selection.first);
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
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
                    foregroundColor: context.appColors.accent,
                    side: BorderSide(
                      color: context.appColors.accent.withValues(alpha: 0.35),
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
              ValueListenableBuilder<NotifySettings>(
                valueListenable: FriendNotifier.instance.settings,
                builder: (context, s, _) {
                  Widget hint(String text) => Text(
                    text,
                    style: TextStyle(
                      fontSize: AppText.label,
                      height: 1.5,
                      color: context.appColors.ink(0.3),
                    ),
                  );
                  Widget switchRow({
                    required String title,
                    required String subtitle,
                    required bool value,
                    required Future<void> Function() apply,
                  }) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: value,
                      onChanged: (v) => _toggleSetting(context, v, apply),
                      title: Text(
                        title,
                        style: const TextStyle(fontSize: AppText.secondary),
                      ),
                      subtitle: hint(subtitle),
                    );
                  }

                  return Column(
                    children: [
                      switchRow(
                        title: '上线提醒',
                        subtitle: '好友进入 VRChat 时提醒',
                        value: s.online,
                        apply: () => FriendNotifier.instance.setOnline(!s.online),
                      ),
                      switchRow(
                        title: '下线提醒',
                        subtitle: '好友离开 VRChat 时提醒',
                        value: s.offline,
                        apply: () =>
                            FriendNotifier.instance.setOffline(!s.offline),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => _showReminderScope(context, ref),
                        title: const Text(
                          '提醒范围',
                          style: TextStyle(fontSize: AppText.secondary),
                        ),
                        subtitle: hint(_scopeLabel(s)),
                        trailing: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: context.appColors.ink(0.35),
                        ),
                      ),
                      switchRow(
                        title: '好友申请提醒',
                        subtitle: '收到新的好友请求时提醒',
                        value: s.friendRequest,
                        apply: () =>
                            FriendNotifier.instance.setFriendRequest(!s.friendRequest),
                      ),
                      switchRow(
                        title: 'VRChat 服务状态提醒',
                        subtitle: '官方服务异常或恢复正常时提醒',
                        value: s.serviceStatus,
                        apply: () => FriendNotifier.instance
                            .setServiceStatus(!s.serviceStatus),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: hint('只在 App 运行时生效；Web 端上下线不提醒。'),
                      ),
                    ],
                  );
                },
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
                valueColor: friends.pipelineAlive ? const Color(0xFF4ADE80) : context.appColors.ink(0.38),
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
                      foregroundColor: context.appColors.accent,
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
              OutlinedButton.icon(
                onPressed: () => _openGithub(context),
                icon: const Icon(Icons.code, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.appColors.ink(0.8),
                  side: BorderSide(color: context.appColors.ink(0.14)),
                  minimumSize: const Size.fromHeight(44),
                ),
                label: const Text('关于 APP · GitHub 项目主页'),
              ),
              const SizedBox(height: 10),
              Text(
                '个人学习用途的非官方客户端，与 VRChat Inc. 无关。\n'
                '请遵守 VRChat 的 API 使用规范：不要高频轮询、不要滥用接口。',
                style: TextStyle(
                  fontSize: AppText.label,
                  height: 1.7,
                  color: context.appColors.ink(0.25),
                ),
              ),
            ],
          ),
        ],
    );

    // 列表和顶栏放进同一个 Stack，滚动时列表会从毛玻璃下面经过。
    return Scaffold(
      body: Stack(
        children: [
          list,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: const FrostedAppBar(title: Text('设置')),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSetting(
    BuildContext context,
    bool value,
    Future<void> Function() apply,
  ) async {
    if (value) {
      final granted = await FriendNotifier.instance.requestPermission();
      if (!granted) {
        if (context.mounted) {
          _toast(context, '系统没有给通知权限，请到系统设置里手动允许');
        }
        return;
      }
    }
    await apply();
  }

  String _scopeLabel(NotifySettings s) => switch (s.scope) {
        NotifyScope.all => '全部好友',
        NotifyScope.groups => s.groupNames.isEmpty
            ? '仅好友收藏分组（尚未选择）'
            : '仅好友收藏分组（已选 ${s.groupNames.length} 个）',
        NotifyScope.selected => s.userIds.isEmpty
            ? '仅指定好友（尚未选择）'
            : '仅指定好友（已选 ${s.userIds.length} 位）',
      };

  /// 提醒范围：全部好友 / 收藏分组 / 指定好友。
  Future<void> _showReminderScope(BuildContext context, WidgetRef ref) async {
    final current = FriendNotifier.instance.settings.value;
    var scope = current.scope;
    final groups = <String>{...current.groupNames};
    final users = <String>{...current.userIds};

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final favGroups = ref.watch(friendFavoriteGroupsProvider).valueOrNull ??
              const <FavoriteGroup>[];
          final friends = [...ref.watch(friendsProvider).friends]
            ..sort((a, b) => a.displayName
                .toLowerCase()
                .compareTo(b.displayName.toLowerCase()));

          Widget radio(NotifyScope value, String title) {
            final selected = scope == value;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              onTap: () => setSheet(() => scope = value),
              leading: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: selected
                    ? ctx.appColors.accent
                    : ctx.appColors.ink(0.35),
              ),
              title: Text(
                title,
                style: const TextStyle(fontSize: AppText.secondary),
              ),
            );
          }

          Widget emptyHint(String text) => Center(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: AppText.caption,
                    color: ctx.appColors.ink(0.35),
                  ),
                ),
              );

          final imageHeaders = ref.watch(imageHeadersProvider);

          Widget avatar(FriendPresence friend) {
            const size = 34.0;
            final fallback = Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ctx.appColors.surfaceHigh,
              ),
              child: Text(
                friend.displayName.isEmpty
                    ? '?'
                    : friend.displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ctx.appColors.ink(0.6),
                ),
              ),
            );
            final url = friend.avatarUrl;
            return SizedBox(
              width: size,
              height: size,
              child: ClipOval(
                child: url == null || url.isEmpty
                    ? fallback
                    : CachedNetworkImage(
                        imageUrl: url,
                        httpHeaders: imageHeaders,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => fallback,
                        errorWidget: (_, _, _) => fallback,
                      ),
              ),
            );
          }

          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.72,
              // 统一左右内边距，别让内容贴着屏幕边框。
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 18, bottom: 4),
                      child: Text(
                        '提醒范围',
                        style: TextStyle(
                          fontSize: AppText.title,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    radio(NotifyScope.all, '全部好友'),
                    radio(NotifyScope.groups, '仅好友收藏分组'),
                    if (scope == NotifyScope.groups)
                      Expanded(
                        child: favGroups.isEmpty
                            ? emptyHint('还没有好友收藏夹')
                            : ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  for (final g in favGroups)
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      value: groups.contains(g.name),
                                      onChanged: (v) => setSheet(() {
                                        if (v == true) {
                                          groups.add(g.name);
                                        } else {
                                          groups.remove(g.name);
                                        }
                                      }),
                                      title: Text(
                                        favoriteGroupLabel(g),
                                        style: const TextStyle(
                                          fontSize: AppText.secondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    radio(NotifyScope.selected, '仅指定好友'),
                    if (scope == NotifyScope.selected)
                      Expanded(
                        child: friends.isEmpty
                            ? emptyHint('好友列表还没加载出来')
                            : ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  for (final f in friends)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      leading: avatar(f),
                                      trailing: Checkbox(
                                        value: users.contains(f.userId),
                                        onChanged: (v) => setSheet(() {
                                          if (v == true) {
                                            users.add(f.userId);
                                          } else {
                                            users.remove(f.userId);
                                          }
                                        }),
                                      ),
                                      onTap: () => setSheet(() {
                                        if (!users.remove(f.userId)) {
                                          users.add(f.userId);
                                        }
                                      }),
                                      title: Text(
                                        f.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: AppText.secondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('完成'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    await FriendNotifier.instance.update(
      current.copyWith(
        scope: scope,
        groupNames: groups.toList(),
        userIds: users.toList(),
      ),
    );
  }

  Future<void> _openGithub(BuildContext context) async {
    const url = 'https://github.com/NekoChiffon/neko-vrc';
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      _toast(context, '打不开浏览器，请手动访问 github.com/NekoChiffon/neko-vrc');
    }
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
      backgroundColor: context.appColors.surface,
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
                color: context.appColors.ink(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, size: 16, color: context.appColors.accent),
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
                                  color: context.appColors.ink(0.35),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        '切换',
                        style: TextStyle(
                          fontSize: AppText.caption,
                          color: context.appColors.accent,
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.appColors.surfaceHigh,
      ),
      child: Icon(Icons.person, size: 18, color: context.appColors.ink(0.24)),
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
        color: context.appColors.surface.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: AppText.label,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.appColors.accent,
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
          Icon(icon, size: 15, color: context.appColors.ink(0.4)),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.caption,
                color: context.appColors.ink(0.55),
              ),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: AppText.caption, color: valueColor ?? context.appColors.ink(0.7)),
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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: context.appColors.ink(0.45)),
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
                          ? context.appColors.ink(0.24)
                          : context.appColors.ink(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: context.appColors.ink(0.2),
            ),
          ],
        ),
      ),
    );
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
