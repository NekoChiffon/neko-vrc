import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/location_parser.dart';
import '../providers/friends_provider.dart';
import '../services/presence_tracker.dart';
import '../theme.dart';
import 'world_detail_page.dart';

/// 动态的分类，和 VRCX 的分栏保持一致。
enum ActivityFilter {
  all('全部'),
  presence('上下线'),
  location('位置'),
  profile('资料'),
  met('相遇');

  const ActivityFilter(this.label);

  final String label;

  bool matches(PresenceKind kind) => switch (this) {
    ActivityFilter.all => true,
    ActivityFilter.presence =>
      kind == PresenceKind.online || kind == PresenceKind.offline,
    ActivityFilter.location => kind == PresenceKind.moved,
    ActivityFilter.profile => kind == PresenceKind.status,
    ActivityFilter.met => kind == PresenceKind.met,
  };
}

/// 当前选中的分类。顶栏的下拉按钮和列表共用同一份状态。
final activityFilterProvider = StateProvider<ActivityFilter>(
  (ref) => ActivityFilter.all,
);

/// 好友动态时间线。
///
/// 数据来源有两条：
/// 1. Pipeline 推送 —— App 开着时实时记；
/// 2. 定时 REST 快照对比 —— 补上刚启动、弱网、实时通道掉线时漏掉的变化。
///
/// 全部落在本机，不上传任何地方；历史上没有的变化补不回来，所以页面顶部
/// 直接展示「现在」的状态，让刚装上的人也有内容可看。
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(presenceEventsProvider);
    final filter = ref.watch(activityFilterProvider);
    final events = filter == ActivityFilter.all
        ? all
        : all.where((e) => filter.matches(e.kind)).toList();
    final friends = ref.watch(friendsProvider);

    Future<void> refresh() =>
        ref.read(friendsProvider.notifier).refresh(silent: true);

    // 按天分组，标题用「今天 / 昨天 / 10 月 17 日」。
    final grouped = <String, List<PresenceEvent>>{};
    for (final e in events) {
      final key = '${e.at.year}-${e.at.month}-${e.at.day}';
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final days = grouped.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return RefreshIndicator(
      onRefresh: refresh,
      color: AppTheme.accent,
      backgroundColor: AppTheme.surfaceHigh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (events.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: all.isEmpty
                  ? _EmptyActivity(state: friends, onRefresh: refresh)
                  : _EmptyFilter(
                      filter: filter,
                      onShowAll: () => ref
                          .read(activityFilterProvider.notifier)
                          .state = ActivityFilter.all,
                    ),
            )
          else
            for (final day in days) ...[
              SliverToBoxAdapter(
                child: _DayHeader(label: _dayLabel(day.value.first.at)),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _EventRow(event: day.value[i]),
                  childCount: day.value.length,
                ),
              ),
            ],
          if (events.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(t.year, t.month, t.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (target.year == now.year) return '${t.month} 月 ${t.day} 日';
    return '${t.year} 年 ${t.month} 月 ${t.day} 日';
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.state, required this.onRefresh});

  final FriendsState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final online = state.friends.where((f) => f.isOnline).toList();
    final preview = online.take(4).map((f) => f.displayName).toList();
    final more = online.length - preview.length;

    final failed = state.error != null && state.friends.isEmpty;
    final headline = failed
        ? '好友同步失败'
        : state.loading && state.friends.isEmpty
            ? '正在同步好友…'
            : '还没有动态';

    final hint = failed
        ? state.error!
        : state.friends.isEmpty
            ? '好友列表拉取成功后，这里会先显示在线情况'
            : '已同步 ${state.friends.length} 位好友，其中 ${state.onlineCount} 位在线\n'
                '动态只在好友上线、换房间或改状态时产生，且只存在本机';

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Icons.cloud_off_outlined : Icons.timeline,
              size: 40,
              color: Colors.white.withValues(alpha: failed ? 0.18 : 0.15),
            ),
            const SizedBox(height: 14),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.secondary,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.7,
                color: failed
                    ? const Color(0xFFF87171).withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.28),
              ),
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '现在在线：${preview.join('、')}'
                '${more > 0 ? ' 等 $more 人' : ''}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.label,
                  color: AppTheme.accent.withValues(alpha: 0.7),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text(
                '立即刷新',
                style: TextStyle(fontSize: AppText.caption),
              ),
              style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选了某个分类、但这一类还没有记录时的空状态。
class _EmptyFilter extends StatelessWidget {
  const _EmptyFilter({required this.filter, required this.onShowAll});

  final ActivityFilter filter;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_off,
              size: 40,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 14),
            Text(
              '「${filter.label}」还没有记录',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.secondary,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '其他分类里可能已经有动态，切换看看',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.7,
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onShowAll,
              style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
              child: const Text(
                '看全部动态',
                style: TextStyle(fontSize: AppText.caption),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏的「动态 ⌄」下拉：切换分类。
///
/// 放在 AppBar 里而不是页面内部，是为了滚动时它始终在顶上。
class ActivityFilterButton extends ConsumerWidget {
  const ActivityFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(activityFilterProvider);

    // 包一层 Material：PopupMenuButton 的水波纹画在最近的 Material 上，
    // 没有这层的话点击会出现一个方形的灰色高亮，圆角胶囊变成方块。
    return Material(
      color: AppTheme.surfaceHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<ActivityFilter>(
        initialValue: filter,
        tooltip: '筛选动态',
        offset: const Offset(0, 38),
        color: AppTheme.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        onSelected: (value) =>
            ref.read(activityFilterProvider.notifier).state = value,
        itemBuilder: (context) => [
          for (final item in ActivityFilter.values)
            PopupMenuItem<ActivityFilter>(
              value: item,
              height: 46,
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: item == filter
                        ? const Icon(Icons.check, size: 19)
                        : null,
                  ),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: AppText.secondary,
                      fontWeight: item == filter
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: item == filter ? Colors.white : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filter == ActivityFilter.all
                    ? '动态'
                    : '动态 · ${filter.label}',
                style: const TextStyle(
                  fontSize: AppText.body,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppText.caption,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _EventRow extends ConsumerWidget {
  const _EventRow({required this.event});

  final PresenceEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = _describe(ref);
    // 旧动态没存头像，用当前好友列表里的补上，升级后历史记录也能看到头像。
    final fallbackAvatar = ref.watch(
      friendsProvider.select((state) {
        for (final friend in state.friends) {
          if (friend.userId == event.userId) return friend.avatarUrl;
        }
        return null;
      }),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EventAvatar(
                url: event.avatarUrl ?? fallbackAvatar,
                name: event.displayName,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppText.body,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _stamp(event.at),
                          style: TextStyle(
                            fontSize: AppText.label,
                            color: Colors.white.withValues(alpha: 0.38),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(view.icon, size: 15, color: view.color),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            view.action,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppText.secondary,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (view.detail != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 23),
                        child: _EventDetail(
                          text: view.detail!,
                          worldId: view.worldId,
                          instanceId: view.instanceId,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          indent: 76,
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ],
    );
  }

  static String _stamp(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  ({
    IconData icon,
    Color color,
    String action,
    String? detail,
    String? worldId,
    String? instanceId,
  })
  _describe(WidgetRef ref) {
    switch (event.kind) {
      case PresenceKind.online:
        return (
          icon: Icons.login,
          color: const Color(0xFF4ADE80),
          action: '上线了',
          detail: null,
          worldId: null,
          instanceId: null,
        );
      case PresenceKind.offline:
        return (
          icon: Icons.logout,
          color: const Color(0xFF6B7280),
          action: '下线了',
          detail: null,
          worldId: null,
          instanceId: null,
        );
      case PresenceKind.status:
        final statusDesc = event.statusDescription?.trim();
        return (
          icon: Icons.edit_note,
          color: AppTheme.accent,
          action: '状态改为 ${event.note ?? '未知'}',
          detail: statusDesc == null || statusDesc.isEmpty ? null : statusDesc,
          worldId: null,
          instanceId: null,
        );
      case PresenceKind.moved:
        final worldId = event.worldId;
        final instanceId = event.instanceId;

        // 没有世界信息 —— 只可能是好友把位置设成了不可见/私人。
        if (worldId == null) {
          return (
            icon: Icons.place_outlined,
            color: Colors.white38,
            action: '位置变化',
            detail: '位于私人房间',
            worldId: null,
            instanceId: null,
          );
        }

        // 老记录没存实例号，只能按世界名 + 当时的备注显示。
        if (instanceId == null) {
          return (
            icon: Icons.place_outlined,
            color: AppTheme.accentAlt,
            action: '位置变化',
            detail: _locationDetail(_worldName(ref, worldId), event.note),
            worldId: null,
            instanceId: null,
          );
        }

        final loc = ParsedLocation.parse('$worldId:$instanceId');
        // 仅限邀请 / 邀请+ 这类私人房间不暴露地图，统一写成「位于私人房间」。
        if (loc.instanceType == InstancePrivacy.private) {
          return (
            icon: Icons.place_outlined,
            color: Colors.white38,
            action: '位置变化',
            detail: '位于私人房间',
            worldId: null,
            instanceId: null,
          );
        }

        final name = _worldName(ref, worldId);
        final number = instanceId.split('~').first;
        return (
          icon: Icons.place_outlined,
          color: AppTheme.accentAlt,
          action: '位置变化',
          detail: [
            if (name != null && name.isNotEmpty) name,
            loc.privacyLabel,
            '#$number',
          ].join(' · '),
          worldId: worldId,
          instanceId: instanceId,
        );
      case PresenceKind.met:
        final metWorldId = event.worldId;
        if (metWorldId == null) {
          return (
            icon: Icons.waving_hand,
            color: const Color(0xFFF472B6),
            action: '和你在同一个房间相遇',
            detail: null,
            worldId: null,
            instanceId: null,
          );
        }
        return (
          icon: Icons.waving_hand,
          color: const Color(0xFFF472B6),
          action: '和你相遇',
          detail: _worldName(ref, metWorldId),
          worldId: metWorldId,
          instanceId: event.instanceId,
        );
    }
  }

  static String? _worldName(WidgetRef ref, String worldId) {
    return ref.watch(worldNameProvider(worldId)).maybeWhen(
      data: (n) => n,
      orElse: () => null,
    );
  }

  /// 「世界名 · 好友+ · 状态语」这种一行说明。
  static String? _locationDetail(String? worldName, String? note) {
    final parts = <String>[
      if (worldName != null && worldName.isNotEmpty) worldName,
      if (note != null && note.trim().isNotEmpty) note.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// 动态第三行的说明文字。
///
/// 带世界 + 实例号时可以点进去，效果和从邀请通知点房间卡片一样 ——
/// 世界详情页会把这个实例放在「当前实例」最上面。
class _EventDetail extends StatelessWidget {
  const _EventDetail({
    required this.text,
    this.worldId,
    this.instanceId,
  });

  final String text;
  final String? worldId;
  final String? instanceId;

  @override
  Widget build(BuildContext context) {
    final world = worldId;
    final instance = instanceId;

    if (world == null || instance == null) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppText.secondary,
          height: 1.45,
          color: Colors.white.withValues(alpha: 0.42),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorldDetailPage(
            worldId: world,
            instanceLocation: instance,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.secondary,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 动态里的好友头像。URL 取不到时退回名字首字。
class _EventAvatar extends ConsumerWidget {
  const _EventAvatar({required this.url, required this.name});

  final String? url;
  final String name;

  static const double _size = 46;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = Container(
      width: _size,
      height: _size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surfaceHigh,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontSize: AppText.body,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );

    final src = url;
    if (src == null || src.isEmpty) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: src,
        httpHeaders: ref.watch(imageHeadersProvider),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
