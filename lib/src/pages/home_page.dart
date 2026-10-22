import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend_presence.dart';
import 'album_page.dart';
import '../providers/discovery_provider.dart';
import '../providers/group_visibility.dart';
import '../providers/my_rooms_history.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';
import '../widgets/friend_tile.dart';
import '../widgets/status_sheet.dart';
import '../widgets/profile_view.dart';
import '../widgets/motion.dart';
import '../widgets/skeleton.dart';
import 'activity_page.dart';
import 'friend_detail_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';
import 'search_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧之后再打请求，避免在 build 期间改 provider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 先刷新自己：登录快照里的 location 会过期（PC 端可能已经上线/换房）。
      try {
        final auth = ref.read(authProvider);
        if (auth is AuthSignedIn) {
          await ref.read(authProvider.notifier).refreshMe();
          final fresh = ref.read(authProvider);
          if (fresh is AuthSignedIn) {
            ref
                .read(myRoomsHistoryProvider.notifier)
                .record(fresh.user.location);
          }
        }
      } catch (_) {
        // 刷新失败不影响主流程
      }
      ref.read(friendsProvider.notifier).refresh();
      _startPolling();
    });
  }

  /// 前台每 60 秒静默刷新一次好友。
  ///
  /// VRChat 只给「当前状态」，手机端也没有桌面端那种游戏日志，所以动态只能靠
  /// 「定时取快照 + 对比差异」。Pipeline 正常时事件已经实时记下，这里只是兜底；
  /// Pipeline 没连上（弱网、被拦、token 过期）时，轮询仍然能产生动态。
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      ref.read(friendsProvider.notifier).refresh(silent: true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 刷新自己的资料 + 详情页数据（所在世界、当前模型）。
  Future<void> _refreshMeAndDetail() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSignedIn) return;
    await ref.read(authProvider.notifier).refreshMe();
    ref.invalidate(userDetailProvider(auth.user.id));
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台回来：先看实时通道还活着没，再顺手刷一次好友。
      ref.read(friendsProvider.notifier).reconnectIfStale();
      ref.read(friendsProvider.notifier).refresh();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      // 后台不轮询，省电也避免无谓请求。
      _stopPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final auth = ref.watch(authProvider);
    final me = auth is AuthSignedIn ? auth.user : null;
    // 未读通知数。第一次进 App 会顺带拉一次通知列表，之后就吃缓存。
    final unread = ref
            .watch(notificationsProvider)
            .valueOrNull
            ?.where((n) => !n.seen)
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        title: switch (_index) {
          0 => Row(
              children: [
                const Text('好友'),
                const SizedBox(width: 10),
                if (friends.friends.isNotEmpty)
                  Text(
                    '${friends.onlineCount} 在线 / ${friends.friends.length}',
                    style: TextStyle(
                      fontSize: AppText.caption,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
          1 => const Text('查找'),
          2 => const ActivityFilterButton(),
          _ => const Text('我'),
        },
        actions: [
          if (_index == 0) ...[
            if (me != null)
              IconButton(
                tooltip: '我的状态：${userStatusLabel(me.status)}',
                onPressed: () => showStatusSheet(context),
                icon: Icon(
                  Icons.circle,
                  size: 13,
                  color: userStatusColor(me.status),
                ),
              ),
            IconButton(
              tooltip: unread > 0 ? '通知（$unread 条未读）' : '通知',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
              ),
              icon: Badge(
                isLabelVisible: unread > 0,
                backgroundColor: const Color(0xFFF87171),
                label: PopOnChange(
                  trigger: unread,
                  child: Text(unread > 99 ? '99+' : '$unread'),
                ),
                child: const Icon(Icons.notifications_none),
              ),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: friends.loading
                  ? null
                  : () {
                      ref.read(friendsProvider.notifier).refresh();
                      // 顺手把通知也刷一遍，不用再单独跑一趟通知页。
                      ref.invalidate(notificationsProvider);
                    },
              icon: friends.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
          if (_index == 2) ...[
            IconButton(
              tooltip: '只看某个好友',
              onPressed: () => _showActivityFriendPicker(context, ref),
              icon: const Icon(Icons.person_search_outlined),
            ),
            if (ref.watch(presenceEventsProvider).isNotEmpty) ...[
              IconButton(
                tooltip: '导出动态',
                onPressed: () => _exportActivity(context, ref),
                icon: const Icon(Icons.ios_share),
              ),
              IconButton(
                tooltip: '清空动态',
                onPressed: () => _confirmClearActivity(context, ref),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
          if (_index == 3 && me != null) ...[
            IconButton(
              tooltip: '设置',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              tooltip: '相册',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AlbumPage()),
              ),
              icon: const Icon(Icons.photo_library_outlined),
            ),
            IconButton(
              tooltip: '分享主页链接',
              onPressed: () {
                final link = 'https://vrchat.com/home/user/${me.id}';
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制主页链接：$link')),
                );
              },
              icon: const Icon(Icons.ios_share),
            ),
          ],
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          _FriendsTab(),
          SearchPage(),
          ActivityPage(),
          _MeTab(),
        ],
      ),
      bottomNavigationBar: _BottomDock(
        index: _index,
        onSelected: _selectTab,
      ),
    );
  }

  void _selectTab(int i) {
    setState(() => _index = i);
    // 切到「动态」先取一次最新快照，变化能立刻反映出来。
    if (i == 2) ref.read(friendsProvider.notifier).refresh(silent: true);
    // 切到「我」时刷新一次：所在世界和当前模型会跟着电脑端变化。
    if (i == 3) _refreshMeAndDetail();
  }

  /// 动态页「只看某个好友」：从已经出现过的好友里选一个。
  void _showActivityFriendPicker(BuildContext context, WidgetRef ref) {
    final events = ref.read(presenceEventsProvider);
    final names = <String, String>{};
    for (final e in events) {
      names.putIfAbsent(e.userId, () => e.displayName);
    }
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有好友动态')),
      );
      return;
    }

    final entries = names.entries.toList()
      ..sort(
        (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
      );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
          ),
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
                    Icon(Icons.person_search_outlined,
                        size: 16, color: AppTheme.accent),
                    SizedBox(width: 8),
                    Text(
                      '只看某个好友的动态',
                      style: TextStyle(
                        fontSize: AppText.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.groups_outlined, size: 20),
                      title: const Text(
                        '全部好友',
                        style: TextStyle(fontSize: AppText.secondary),
                      ),
                      onTap: () {
                        ref.read(activityFriendFilterProvider.notifier).state =
                            null;
                        Navigator.pop(ctx);
                      },
                    ),
                    for (final e in entries)
                      ListTile(
                        leading: const Icon(Icons.person_outline, size: 20),
                        title: Text(
                          e.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppText.secondary),
                        ),
                        onTap: () {
                          ref
                                  .read(activityFriendFilterProvider.notifier)
                                  .state =
                              (userId: e.key, displayName: e.value);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 导出当前筛选下的动态：直接复制成 JSON 到剪贴板。
  Future<void> _exportActivity(BuildContext context, WidgetRef ref) async {
    final category = ref.read(activityFilterProvider);
    final friend = ref.read(activityFriendFilterProvider);
    var events = ref.read(presenceEventsProvider);
    if (friend != null) {
      events = events.where((e) => e.userId == friend.userId).toList();
    }
    if (category != ActivityFilter.all) {
      events = events.where((e) => category.matches(e.kind)).toList();
    }
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前筛选下没有可导出的动态')),
      );
      return;
    }

    final text = const JsonEncoder.withIndent('  ')
        .convert([for (final e in events) e.toJson()]);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${events.length} 条动态（JSON）到剪贴板')),
    );
  }

  Future<void> _confirmClearActivity(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空动态？'),
        content: const Text('本机记录的好友动态会被删掉，之后的变化会重新开始记。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('算了')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(friendsProvider.notifier).clearEvents();
    }
  }
}

/// 悬浮式底栏：一颗胶囊装三项，搜索单独一颗圆按钮。
///
/// 只借了那种 floating dock 的观感，入口还是原来的四个 —— 把「查找」拆到
/// 右边那颗圆按钮上，其余三个留在胶囊里。
class _BottomDock extends StatelessWidget {
  const _BottomDock({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(16, 8, 16, inset > 0 ? inset + 6 : 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xF2151B23),
                borderRadius: BorderRadius.circular(31),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _DockItem(
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: '好友',
                    selected: index == 0,
                    onTap: () => onSelected(0),
                  ),
                  _DockItem(
                    icon: Icons.timeline_outlined,
                    activeIcon: Icons.timeline,
                    label: '动态',
                    selected: index == 2,
                    onTap: () => onSelected(2),
                  ),
                  _DockItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: '我',
                    selected: index == 3,
                    onTap: () => onSelected(3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _DockSearchButton(
            selected: index == 1,
            onTap: () => onSelected(1),
          ),
        ],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accent : Colors.white.withValues(alpha: 0.52);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 38,
              height: 28,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(selected ? activeIcon : icon, size: 21, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockSearchButton extends StatelessWidget {
  const _DockSearchButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '查找',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppTheme.accent : const Color(0xF2151B23),
            border: Border.all(
              color: selected
                  ? AppTheme.accent
                  : Colors.white.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.search,
            size: 26,
            color: selected ? AppTheme.canvas : Colors.white.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 好友
// ---------------------------------------------------------------------------

class _FriendsTab extends ConsumerStatefulWidget {
  const _FriendsTab();

  @override
  ConsumerState<_FriendsTab> createState() => _FriendsTabState();
}

enum _FriendFilter { all, online, web, offline }

class _FriendsTabState extends ConsumerState<_FriendsTab> {
  final _search = TextEditingController();
  _FriendFilter _filter = _FriendFilter.all;

  /// 当前选中的好友收藏夹（内部名）。null 表示不按收藏夹过滤。
  String? _favoriteGroup;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<FriendPresence> _apply(
    List<FriendPresence> all,
    Map<String, String> notes,
  ) {
    final q = _search.text.trim().toLowerCase();
    return all.where((f) {
      if (q.isNotEmpty) {
        final name = f.displayName.toLowerCase();
        final note = (notes[f.userId] ?? '').toLowerCase();
        if (!name.contains(q) && !note.contains(q)) return false;
      }
      return switch (_filter) {
        _FriendFilter.all => true,
        _FriendFilter.online => f.isOnline,
        _FriendFilter.web => f.isWebPlatform,
        _FriendFilter.offline => !f.isOnline,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendsProvider);

    if (state.friends.isEmpty && state.loading) {
      return const FriendListSkeleton();
    }

    if (state.friends.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.24),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Icon(
                      state.error != null ? Icons.cloud_off : Icons.pets,
                      size: 44,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      state.error ?? '还没有好友，或者列表还没加载出来',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppText.secondary,
                        height: 1.6,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 好友收藏夹过滤（和房间分组是两套维度，可以叠加）
    final favGroups = ref.watch(friendFavoriteGroupsProvider).valueOrNull ?? const [];
    String? favoriteLabel;
    for (final g in favGroups) {
      if (g.name == _favoriteGroup) {
        favoriteLabel = g.displayName;
        break;
      }
    }

    // 用局部变量承接，Dart 才能把可空类型提升成非空。
    final favKey = _favoriteGroup;
    final favAsync = favKey == null ? null : ref.watch(favoriteGroupMembersProvider(favKey));
    final favoriteMembers = favAsync?.valueOrNull;
    final favLoading = favAsync != null && favoriteMembers == null;

    final byFilter = _apply(
      state.friends,
      ref.watch(friendNotesProvider).valueOrNull ?? const {},
    );
    final filtered = favoriteMembers == null
        ? byFilter
        : byFilter.where((f) => favoriteMembers.contains(f.userId)).toList();
    final hiddenKinds = ref.watch(groupVisibilityProvider);
    final allGroups = buildFriendGroups(filtered);
    // 分组显示开关是给「全部」视图减噪用的。
    // 一旦明确筛选了某一类（比如只看 Web），就按筛选走，不再被分组开关吃掉。
    final groups = _filter == _FriendFilter.all
        ? allGroups.where((g) => !hiddenKinds.contains(groupKindOf(g))).toList()
        : allGroups;
    final onlineCount = state.friends.where((f) => f.isOnline).length;
    final webCount = state.friends.where((f) => f.isWebPlatform).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            // 别名/名字可能是中文，别关联想 —— 某些国产 ROM 会因此弹出安全键盘。
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: AppText.secondary),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜好友名字',
              hintStyle: TextStyle(
                fontSize: AppText.secondary,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 38),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
              suffixIconConstraints: const BoxConstraints(minWidth: 36),
            ),
          ),
        ),
        if (_favoriteGroup != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 13,
                  color: AppTheme.accent.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '收藏夹：${favoriteLabel ?? _favoriteGroup}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.label,
                      color: AppTheme.accent.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _favoriteGroup = null),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 16),
                  children: [
                    _chip('全部 ${state.friends.length}', _FriendFilter.all),
                    _chip('在线 $onlineCount', _FriendFilter.online),
                    if (webCount > 0) _chip('Web $webCount', _FriendFilter.web),
                    _chip('离线 ${state.friends.length - onlineCount}', _FriendFilter.offline),
                  ],
                ),
              ),
            ),
            // 分组显示设置：只有三条杠
            InkWell(
              onTap: () => _showGroupSettings(context, ref),
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Container(
                width: 34,
                height: 32,
                alignment: Alignment.center,
                child: Icon(
                  Icons.menu,
                  size: 19,
                  color: (hiddenKinds.isEmpty && _favoriteGroup == null)
                      ? Colors.white.withValues(alpha: 0.55)
                      : AppTheme.accent,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: favLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          favKey != null ? '这个收藏夹里没有好友' : '没有匹配的好友',
                          style: TextStyle(
                            fontSize: AppText.caption,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: groups.length,
                    itemBuilder: (context, i) {
                      final group = groups[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (i > 0) const SizedBox(height: 8),
                          _GroupHeader(group: group),
                          ...group.members.map(
                            (f) => FriendTile(
                              friend: f,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => FriendDetailPage(presence: f),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// 好友收藏夹选择。
  void _showGroupSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref2, _) {
          final favGroups =
              ref2.watch(friendFavoriteGroupsProvider).valueOrNull ?? const [];
          final favorites =
              ref2.watch(friendFavoritesProvider).valueOrNull ?? const [];

          int countOf(String name) {
            var n = 0;
            for (final f in favorites) {
              if (f.tags.contains(name)) n++;
            }
            return n;
          }

          Widget favRow(String? key, String label, int? count) {
            final selected = _favoriteGroup == key;
            return InkWell(
              onTap: () {
                setState(() => _favoriteGroup = key);
                Navigator.pop(ctx);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected
                          ? AppTheme.accent
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.body,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    if (count != null)
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: AppText.caption,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Text(
                      '好友收藏夹',
                      style: TextStyle(
                        fontSize: AppText.caption,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppTheme.accent.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  if (favGroups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Text(
                        '正在读取收藏夹…',
                        style: TextStyle(
                          fontSize: AppText.caption,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  favRow(null, '全部好友', null),
                  for (final g in favGroups) favRow(g.name, g.displayName, countOf(g.name)),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, _FriendFilter filter) {
    final active = _filter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = filter),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: active ? AppTheme.accent.withValues(alpha: 0.45) : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppText.label,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? AppTheme.accent : Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({required this.group});

  final FriendGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    String title;
    if (group.isOfflineGroup) {
      title = '离线';
    } else if (group.isPrivateGroup) {
      title = '私密世界';
    } else if (group.isWebGroup) {
      title = 'Web 在线';
    } else if (group.worldId != null) {
      final asyncName = ref.watch(worldNameProvider(group.worldId!));
      final worldName = asyncName.maybeWhen(
        data: (name) => name ?? _shortId(group.worldId!),
        orElse: () => _shortId(group.worldId!),
      );
      // 「世界名 · 好友+」，同一世界的不同房间靠这一行区分。
      title = '$worldName · ${group.privacyLabel}';
    } else {
      title = '位置不可见';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Icon(
            group.isOfflineGroup
                ? Icons.nightlight_round
                : group.isPrivateGroup
                ? Icons.lock_outline
                : group.isWebGroup
                ? Icons.language
                : Icons.meeting_room_outlined,
            size: 13,
            color: AppTheme.accent.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.secondary,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${group.members.length} 人',
            style: TextStyle(
              fontSize: AppText.label,
              color: Colors.white.withValues(alpha: 0.32),
            ),
          ),
        ],
      ),
    );
  }

  static String _shortId(String id) =>
      id.length <= 14 ? id : '${id.substring(0, 14)}…';
}

// ---------------------------------------------------------------------------
// 我
// ---------------------------------------------------------------------------

class _MeTab extends ConsumerWidget {
  const _MeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth is! AuthSignedIn) {
      return const Center(child: Text('未登录'));
    }

    // 和好友资料页共用同一套版式，只是不带返回按钮、按钮换成「编辑个人资料」，
    // 右上角多一个设置入口。下拉可刷新自己的资料（所在世界 / 当前模型）。
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(authProvider.notifier).refreshMe();
        ref.invalidate(userDetailProvider(auth.user.id));
      },
      child: ProfileView(
        userId: auth.user.id,
        showBackButton: false,
        selfMode: true,
        onOpenSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
        ),
      ),
    );
  }
}
