import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../core/location_parser.dart';
import '../models/friend_presence.dart';
import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../providers/my_rooms_history.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';

class WorldDetailPage extends ConsumerWidget {
  const WorldDetailPage({
    super.key,
    required this.worldId,
    this.instanceLocation,
  });

  final String worldId;

  /// 从邀请通知跳进来时带着具体实例（`12345~region(jp)~...`），
  /// 用来在「当前实例」顶部单独展示这个房间（公开实例列表里通常没有它）。
  final String? instanceLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(worldDetailProvider(worldId));

    return Scaffold(
      body: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.only(top: 16),
          child: DetailSkeleton(),
        ),
        error: (e, _) => _ErrorScaffold(message: e.toString()),
        data: (world) => CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: context.appColors.canvas,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: world.imageUrl,
                      httpHeaders: ref.watch(imageHeadersProvider),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          ColoredBox(color: context.appColors.surfaceHigh),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x33000000), Color(0xEE0B0F14)],
                          stops: [0.0, 0.92],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              title: Text(
                world.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      world.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'by ${world.authorName}',
                      style: TextStyle(
                        fontSize: AppText.caption,
                        color: context.appColors.ink(0.4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MetricGrid(
                      tiles: [
                        _Metric(
                          icon: Icons.person_outline,
                          value: '${world.capacity}',
                          label: '容量',
                        ),
                        _Metric(
                          icon: Icons.groups_2_outlined,
                          value: _compact(world.occupants ?? 0),
                          label: '在线',
                        ),
                        _Metric(
                          icon: Icons.visibility_outlined,
                          value: _compact(world.visits),
                          label: '访问',
                        ),
                        _Metric(
                          icon: Icons.favorite_border,
                          value: _compact(world.favorites ?? 0),
                          label: '收藏',
                        ),
                        _Metric(
                          icon: Icons.local_fire_department_outlined,
                          value: _compact(world.popularity),
                          label: '热度',
                        ),
                        _Metric(
                          icon: Icons.trending_up,
                          value: _compact(world.heat),
                          label: '知名度',
                        ),
                        _Metric(
                          icon: Icons.update,
                          value: 'v${world.version}',
                          label: '版本',
                        ),
                        _Metric(
                          icon: Icons.event_outlined,
                          value: _formatDate(world.publicationDate),
                          label: '发布',
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _showCreateInstance(
                              context,
                              ref,
                              worldId,
                              world.name,
                            ),
                            icon: const Icon(Icons.meeting_room_outlined, size: 18),
                            label: const Text('新建房间'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              foregroundColor: context.appColors.accent,
                              backgroundColor:
                                  context.appColors.accent.withValues(alpha: 0.10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _FavoriteEntry(worldId: worldId),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () => _showWorldActions(context, ref, worldId),
                          borderRadius: BorderRadius.circular(AppRadius.field),
                          child: Container(
                            width: 52,
                            height: 44,
                            decoration: BoxDecoration(
                              color: context.appColors.ink(0.05),
                              borderRadius: BorderRadius.circular(AppRadius.field),
                            ),
                            child: Icon(
                              Icons.more_horiz,
                              size: 20,
                              color: context.appColors.ink(0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ActiveInstancesSection(
                      worldId: worldId,
                      instanceLocation: instanceLocation,
                    ),
                    if (world.description.trim().isNotEmpty)
                      _Section(
                        title: '简介',
                        child: _ExpandableText(
                          text: world.description.trim(),
                          collapsedLines: 4,
                        ),
                      ),
                    _Section(
                      title: '信息',
                      child: Column(
                        children: [
                          _Row(
                            label: '创建',
                            value: DateFormat('yyyy 年 M 月 d 日').format(world.createdAt),
                          ),
                          _Row(label: '世界 ID', value: worldId, copiable: true),
                          _PlatformInfo(world: world),
                        ],
                      ),
                    ),
                    if (world.tags.isNotEmpty)
                      _Section(
                        title: '标签',
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: world.tags
                              .map(
                                (t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.appColors.ink(0.07),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t,
                                    style: TextStyle(
                                      fontSize: AppText.label,
                                      color: context.appColors.ink(0.6),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 发布日期是 ISO 字符串（`2026-10-10T...`），只取日期部分并换成点分隔。
  static String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final date = raw.length >= 10 ? raw.substring(0, 10) : raw;
    return date.replaceAll('-', '.');
  }

  static String _compact(int n) {
    if (n < 10000) return '$n';
    if (n < 100000000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '${(n / 100000000).toStringAsFixed(2)}亿';
  }
}

/// 一个指标（图标 + 数值 + 标签）。
class _Metric {
  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
    this.dense = false,
  });

  final IconData icon;
  final String value;
  final String label;

  /// 日期这类长文本用小一号字，避免挤爆卡片。
  final bool dense;
}

/// 4 列 × 2 行的指标卡片网格。
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.tiles});

  final List<_Metric> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 4) {
      final rowTiles = tiles.skip(i).take(4).toList();
      rows.add(
        Row(
          children: [
            for (var j = 0; j < 4; j++) ...[
              if (j > 0) const SizedBox(width: 8),
              Expanded(
                child: j < rowTiles.length
                    ? _MetricCard(metric: rowTiles[j])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
      if (i + 4 < tiles.length) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: context.appColors.ink(0.05),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: context.appColors.ink(0.05)),
      ),
      child: Column(
        children: [
          Icon(
            metric.icon,
            size: 17,
            color: context.appColors.accent.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              metric.value,
              maxLines: 1,
              style: TextStyle(
                fontSize: metric.dense ? AppText.caption : AppText.body,
                fontWeight: FontWeight.w700,
                color: context.appColors.ink(0.92),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppText.label,
              color: context.appColors.ink(0.38),
            ),
          ),
        ],
      ),
    );
  }
}


class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: AppText.caption,
              fontWeight: FontWeight.w600,
              color: context.appColors.ink(0.35),
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.copiable = false});

  final String label;
  final String value;
  final bool copiable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppText.caption,
                color: context.appColors.ink(0.4),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: AppText.caption, color: context.appColors.ink(0.7)),
            ),
          ),
          if (copiable)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制世界 ID')),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: context.appColors.ink(0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.secondary, color: context.appColors.ink(0.5)),
          ),
        ),
      ),
    );
  }
}

/// 当前有哪些公开实例可进。
class _ActiveInstancesSection extends ConsumerWidget {
  const _ActiveInstancesSection({
    required this.worldId,
    this.instanceLocation,
  });

  final String worldId;
  final String? instanceLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeInstancesProvider(worldId));

    final invited = (instanceLocation ?? '').isEmpty
        ? null
        : _InvitedInstanceCard(
            worldId: worldId,
            instanceId: instanceLocation!,
          );

    return _Section(
      title: '当前实例',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (invited != null) ...[
            invited,
            const SizedBox(height: 10),
          ],
          async.when(
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: context.appColors.ink(0.3),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '查一下…',
                style: TextStyle(
                  fontSize: AppText.caption,
                  color: context.appColors.ink(0.35),
                ),
              ),
            ],
          ),
        ),
        error: (_, _) => const SizedBox.shrink(),
        data: (instances) {
          if (instances.isEmpty) {
            return Text(
              '暂时查不到公开实例，可能没人开房，也可能这个世界的房间不在公开列表里',
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.6,
                color: context.appColors.ink(0.32),
              ),
            );
          }
          return Column(
            children: [
              for (final i in instances.take(8))
                _InstanceRow(worldId: worldId, instance: i),
            ],
          );
        },
          ),
        ],
      ),
    );
  }
}

class _InstanceRow extends StatelessWidget {
  const _InstanceRow({required this.worldId, required this.instance});

  final String worldId;
  final Instance instance;

  @override
  Widget build(BuildContext context) {
    final loc = ParsedLocation.parse('$worldId:${instance.instanceId}');
    final capacity = instance.capacity ?? 0;
    final full = capacity > 0 && instance.nUsers >= capacity;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: context.appColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              loc.instanceType.label,
              style: TextStyle(fontSize: 10, color: context.appColors.accent),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            capacity > 0 ? '${instance.nUsers}/$capacity 人' : '${instance.nUsers} 人',
            style: TextStyle(
              fontSize: AppText.caption,
              color: context.appColors.ink(full ? 0.35 : 0.65),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: () {
              final link = buildLaunchLink(worldId, instance.instanceId);
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已复制：$link')),
              );
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.link_rounded,
                size: 15,
                color: context.appColors.ink(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 星标：收藏 / 取消收藏。收藏时要先选一个收藏夹。
/// 生成实例 ID（**不含 worldId 前缀**），照 VRCX 的 legacy 格式。
///
/// 关键点：非公开实例必须带**所有者 userId**：
/// - 好友+  → `~hidden(usr_xxx)`（注意不是 friends+）
/// - 仅限好友 → `~friends(usr_xxx)`
/// - 仅限邀请 → `~private(usr_xxx)`
/// - 邀请+   → `~private(usr_xxx)~canRequestInvite`
/// 新版的 `~type(invite+)` 标签服务端不认（会 400）。
///
/// `inviteMyselfTo` 的路径是 `/invite/myself/to/{worldId}:{instanceId}`，
/// worldId 是单独一段 —— 这里不带前缀；`inviteUser` 的 body 里要完整格式。
String _buildInstanceId(String type, String region, String userId) {
  final rand = DateTime.now().microsecondsSinceEpoch % 99999 + 1;
  final name = rand.toString().padLeft(5, '0');
  final tags = <String>[name];

  if (type != 'public') {
    switch (type) {
      case 'friends+':
        tags.add('~hidden($userId)');
      case 'friends':
        tags.add('~friends($userId)');
      case 'invite+':
        tags..add('~private($userId)')..add('~canRequestInvite');
      case 'invite':
        tags.add('~private($userId)');
    }
  }
  if (region.isNotEmpty) tags.add('~region($region)');
  return tags.join();
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// 新建房间：选权限和区域 → 生成链接 → 复制 / 邀请自己 / 邀请好友。
///
/// VRChat 的房间是「隐式创建」的：只要有人进这个实例链接，房间就存在了。
/// 所以手机端没有独立的创建接口，生成合法 instanceId 就是全部。
void _showCreateInstance(
  BuildContext context,
  WidgetRef ref,
  String worldId,
  String worldName,
) {
  final auth = ref.read(authProvider);
  final me = auth is AuthSignedIn ? auth.user : null;
  final selfId = me?.id ?? '';
  var type = 'invite+';
  var region = 'jp';
  String? instanceId;
  var invitingSelf = false;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        // 局部不可变变量，Dart 才能做 null 提升（instanceId 本身是可变的）。
        final iid = instanceId;
        final fullId = iid == null ? null : '$worldId:$iid';
        final link = iid == null ? null : buildLaunchLink(worldId, iid);

        Widget chip(String label, bool selected, VoidCallback onTap) {
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? context.appColors.accent.withValues(alpha: 0.16)
                    : context.appColors.ink(0.05),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: selected
                      ? context.appColors.accent.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppText.caption,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? context.appColors.accent
                      : context.appColors.ink(0.55),
                ),
              ),
            ),
          );
        }

        Widget label(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: AppText.label,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: context.appColors.accent,
                ),
              ),
            );

        // ---- 已创建：链接 + 操作 ----
        if (iid != null) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '房间已创建',
                    style: const TextStyle(
                      fontSize: AppText.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    worldName,
                    style: TextStyle(
                      fontSize: AppText.caption,
                      color: context.appColors.ink(0.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    decoration: BoxDecoration(
                      color: context.appColors.ink(0.05),
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            fullId!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppText.label,
                              height: 1.5,
                              color: context.appColors.ink(0.6),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '复制链接',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: link!));
                            _toast(context, '已复制房间链接');
                          },
                          icon: Icon(
                            Icons.copy_rounded,
                            size: 16,
                            color: context.appColors.ink(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: invitingSelf
                              ? null
                              : () async {
                                  setSheet(() => invitingSelf = true);
                                  final err = await ref
                                      .read(vrcClientProvider)
                                      .inviteMyself(
                                        worldId: worldId,
                                        instanceId: iid,
                                      );
                                  if (!ctx.mounted) return;
                                  setSheet(() => invitingSelf = false);
                                  _toast(ctx, err ?? '已邀请自己，电脑端会收到邀请');
                                },
                          icon: invitingSelf
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.person_pin_circle_outlined, size: 16),
                          label: const Text('邀请自己'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showInviteFriends(ctx, ref, fullId),
                          icon: const Icon(Icons.group_add_outlined, size: 16),
                          label: const Text('邀请好友'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.appColors.ink(0.7),
                            side: BorderSide(
                              color: context.appColors.ink(0.15),
                            ),
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        // ---- 表单：权限 + 区域 ----
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '新建房间',
                  style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  worldName,
                  style: TextStyle(
                    fontSize: AppText.caption,
                    color: context.appColors.ink(0.4),
                  ),
                ),
                const SizedBox(height: 16),
                label('访问权限'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in const {
                      'public': '公开',
                      'friends+': '好友+',
                      'friends': '仅限好友',
                      'invite+': '邀请+',
                      'invite': '仅限邀请',
                    }.entries)
                      chip(e.value, type == e.key, () => setSheet(() => type = e.key)),
                  ],
                ),
                const SizedBox(height: 16),
                label('服务器区域'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in const {
                      'jp': '日本',
                      'use': '美国东部',
                      'us': '美国西部',
                      'eu': '欧洲',
                    }.entries)
                      chip(e.value, region == e.key, () => setSheet(() => region = e.key)),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: selfId.isEmpty
                      ? null
                      : () => setSheet(
                          () => instanceId = _buildInstanceId(type, region, selfId),
                        ),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: const Text('创建房间'),
                ),
                const SizedBox(height: 6),
                Text(
                  '生成的房间在有人进入之前不存在，把链接发给朋友或邀请自己即可',
                  style: TextStyle(
                    fontSize: AppText.label,
                    height: 1.6,
                    color: context.appColors.ink(0.28),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 选好友进房间（instanceId 传完整格式 `wrld_xxx:数字~...`）。
///
/// 顶部搜索过滤 + 多选，底部统一邀请，避免一个个点。
void _showInviteFriends(BuildContext ctx, WidgetRef ref, String instanceId) {
  final friends = ref.read(friendsProvider).friends;
  final sorted = [...friends]..sort((a, b) {
      final ar = a.isOnline ? 0 : 1;
      final br = b.isOnline ? 0 : 1;
      if (ar != br) return ar.compareTo(br);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

  var query = '';
  final selected = <String>{};
  var sending = false;

  showModalBottomSheet<void>(
    context: ctx,
    backgroundColor: ctx.appColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final q = query.trim().toLowerCase();
          final visible = q.isEmpty
              ? sorted
              : sorted
                  .where((f) =>
                      f.displayName.toLowerCase().contains(q) ||
                      f.userId.toLowerCase().contains(q))
                  .toList();

          void toggle(String userId) => setSheet(() {
                if (!selected.add(userId)) selected.remove(userId);
              });

          Future<void> send() async {
            if (selected.isEmpty || sending) return;
            setSheet(() => sending = true);
            final client = ref.read(vrcClientProvider);
            var ok = 0;
            String? firstErr;
            for (final uid in selected) {
              final err = await client.inviteFriendToInstance(
                userId: uid,
                instanceId: instanceId,
              );
              if (err == null) {
                ok++;
              } else {
                firstErr ??= err;
              }
            }
            if (!sheetCtx.mounted) return;
            Navigator.pop(sheetCtx);
            if (!ctx.mounted) return;
            _toast(ctx, firstErr ?? '已邀请 $ok 位好友');
          }

          Widget row(FriendPresence f) {
            final checked = selected.contains(f.userId);
            return InkWell(
              onTap: () => toggle(f.userId),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    Checkbox(
                      value: checked,
                      onChanged: (_) => toggle(f.userId),
                      visualDensity: VisualDensity.compact,
                      activeColor: ctx.appColors.accent,
                    ),
                    Expanded(
                      child: Text(
                        f.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.secondary,
                          color: f.isOnline
                              ? ctx.appColors.ink(1)
                              : ctx.appColors.ink(0.45),
                        ),
                      ),
                    ),
                    Text(
                      f.isOnline ? '在线' : '离线',
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: ctx.appColors.ink(0.28),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            child: SizedBox(
              height: 500,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        const Text(
                          '邀请好友',
                          style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (selected.isNotEmpty)
                          Text(
                            '已选 ${selected.length} 人',
                            style: TextStyle(fontSize: AppText.label, color: ctx.appColors.accent),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                    child: TextField(
                      maxLength: 32,
                      onChanged: (v) => setSheet(() => query = v),
                      style: const TextStyle(fontSize: AppText.secondary),
                      decoration: InputDecoration(
                        hintText: '搜索好友昵称或 ID',
                        hintStyle: TextStyle(
                          fontSize: AppText.caption,
                          color: ctx.appColors.ink(0.25),
                        ),
                        counterStyle:
                            const TextStyle(fontSize: 1, color: Colors.transparent),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 19,
                          color: ctx.appColors.ink(0.4),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Text(
                              '没有匹配的好友',
                              style: TextStyle(
                                fontSize: AppText.caption,
                                color: ctx.appColors.ink(0.35),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: visible.length,
                            itemBuilder: (context, i) => row(visible[i]),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    child: FilledButton.icon(
                      onPressed: selected.isEmpty || sending ? null : send,
                      icon: sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined, size: 16),
                      label: Text(
                        selected.isEmpty
                            ? '选择要邀请的好友'
                            : sending
                                ? '邀请中…'
                                : '邀请选中的 ${selected.length} 位好友',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}


/// 世界页的「⋯」菜单：设为家 / 加入过的房间。
void _showWorldActions(BuildContext context, WidgetRef ref, String worldId) {
  final auth = ref.read(authProvider);
  final me = auth is AuthSignedIn ? auth.user : null;

  showModalBottomSheet<void>(
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
          _WorldActionTile(
            icon: Icons.home_outlined,
            label: '设为家',
            hint: '进游戏的默认出生点',
            onTap: () async {
              Navigator.pop(ctx);
              if (me == null) return;
              final err = await ref
                  .read(vrcClientProvider)
                  .setHomeWorld(userId: me.id, worldId: worldId);
              if (!ctx.mounted) return;
              _toast(ctx, err ?? '已设为家');
            },
          ),
          _WorldActionTile(
            icon: Icons.history,
            label: '加入过的房间',
            hint: '从本 app 记录起',
            onTap: () {
              Navigator.pop(ctx);
              _showMyRoomsHistory(context, ref);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

class _WorldActionTile extends StatelessWidget {
  const _WorldActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.appColors.ink(0.55)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppText.body,
                      color: context.appColors.ink(0.9),
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint!,
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: context.appColors.ink(0.28),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自己进过的房间（本地记录），可搜索、点行复制链接。
void _showMyRoomsHistory(BuildContext context, WidgetRef ref) {
  final snapshot = ref.read(myRoomsHistoryProvider);
  var query = '';

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) {
        final q = query.trim().toLowerCase();
        final visible = q.isEmpty
            ? snapshot
            : snapshot
                .where((e) => (e['loc'] ?? '').toLowerCase().contains(q))
                .toList();

        return SafeArea(
          child: SizedBox(
            height: 460,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      '加入过的房间',
                      style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                  child: TextField(
                    maxLength: 64,
                    onChanged: (v) => setSheet(() => query = v),
                    style: const TextStyle(fontSize: AppText.secondary),
                    decoration: InputDecoration(
                      hintText: '搜索实例 ID 或世界 ID',
                      hintStyle: TextStyle(
                        fontSize: AppText.caption,
                        color: context.appColors.ink(0.25),
                      ),
                      counterStyle: const TextStyle(
                        fontSize: 1,
                        color: Colors.transparent,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 19,
                        color: context.appColors.ink(0.4),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              snapshot.isEmpty
                                  ? '还没有记录。app 每次启动和刷新时会记下你当时所在的房间，用得越久越全'
                                  : '没有匹配的记录',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: AppText.caption,
                                height: 1.7,
                                color: context.appColors.ink(0.35),
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: context.appColors.ink(0.05),
                          ),
                          itemBuilder: (context, i) {
                            final e = visible[i];
                            final loc = e['loc'] ?? '';
                            final at = e['at'] ?? '';
                            final date = at.length >= 16
                                ? '${at.substring(0, 4)}/${at.substring(5, 7)}/'
                                      '${at.substring(8, 10)} ${at.substring(11, 16)}'
                                : at;
                            final worldId = loc.split(':').first;

                            return InkWell(
                              onTap: () {
                                final instPart = loc.contains(':')
                                    ? loc.substring(loc.indexOf(':') + 1)
                                    : loc;
                                Clipboard.setData(ClipboardData(
                                  text: buildLaunchLink(worldId, instPart),
                                ));
                                _toast(context, '已复制房间链接');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.meeting_room_outlined,
                                      size: 16,
                                      color: context.appColors.ink(0.4),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            loc,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: AppText.caption,
                                              height: 1.4,
                                              color: context.appColors.ink(0.75),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            date,
                                            style: TextStyle(
                                              fontSize: AppText.label,
                                              color: context.appColors.ink(0.3),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.copy_rounded,
                                      size: 14,
                                      color: context.appColors.ink(0.3),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 按钮排的收藏入口：已收藏时亮星，点开显示收藏夹列表（单选，选新夹子 = 移动）。
class _FavoriteEntry extends ConsumerWidget {
  const _FavoriteEntry({required this.worldId});

  final String worldId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoritedWorldsProvider);
    FavoritedWorld? existing;
    for (final w in async.valueOrNull ?? const <FavoritedWorld>[]) {
      if (w.id == worldId) {
        existing = w;
        break;
      }
    }
    final isFavorite = existing != null;

    return InkWell(
      onTap: () => _showGroupPicker(context, ref, worldId, existing),
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        width: 52,
        height: 44,
        decoration: BoxDecoration(
          color: isFavorite
              ? const Color(0xFFFBBF24).withValues(alpha: 0.14)
              : context.appColors.ink(0.05),
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Icon(
          isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
          size: 23,
          color: isFavorite
              ? const Color(0xFFFBBF24)
              : context.appColors.ink(0.6),
        ),
      ),
    );
  }
}

/// 收藏夹选择（单选）。
///
/// VRChat 不允许一个世界同时待在多个夹子里：
/// - 点当前夹子 → 取消收藏
/// - 点其他夹子 → 先删旧记录再加入（等于「移动到」）
void _showGroupPicker(
  BuildContext context,
  WidgetRef ref,
  String worldId,
  FavoritedWorld? existing,
) {
  final groups = ref.read(favoriteGroupsProvider).valueOrNull;
  final favorites = ref.read(favoritedWorldsProvider).valueOrNull ?? const <FavoritedWorld>[];

  final counts = <String, int>{};
  for (final w in favorites) {
    final key = w.favoriteGroup;
    if (key != null) counts[key] = (counts[key] ?? 0) + 1;
  }

  var busy = false;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) {
        Future<void> pick(FavoriteGroup g) async {
          final groupName = g.name;
          setSheet(() => busy = true);
          final client = ref.read(vrcClientProvider);

          if (existing != null && existing.favoriteGroup == groupName) {
            final err =
                await client.removeWorldFavorite(existing.favoriteId ?? '');
            if (!sheetCtx.mounted) return;
            setSheet(() => busy = false);
            ref.invalidate(favoritedWorldsProvider);
            _toast(context, err ?? '已取消收藏');
            return;
          }

          if (existing != null) {
            await client.removeWorldFavorite(existing.favoriteId ?? '');
          }
          final err = await client.addWorldFavorite(worldId, groupName: groupName);
          if (!sheetCtx.mounted) return;
          setSheet(() => busy = false);
          ref.invalidate(favoritedWorldsProvider);
          _toast(context, err ?? '已加入「${favoriteGroupLabel(g)}」');
          if (err == null) Navigator.pop(sheetCtx);
        }

        Widget row(FavoriteGroup g) {
          final isCurrent = existing?.favoriteGroup == g.name;
          return ListTile(
            leading: Icon(
              Icons.folder_outlined,
              size: 20,
              color: context.appColors.accent.withValues(alpha: 0.8),
            ),
            title: Text(
              favoriteGroupLabel(g),
              style: TextStyle(
                fontSize: AppText.body,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                color: isCurrent
                    ? context.appColors.accent
                    : context.appColors.ink(0.85),
              ),
            ),
            subtitle: Text(
              '${counts[g.name] ?? 0} 个世界',
              style: TextStyle(
                fontSize: AppText.label,
                color: context.appColors.ink(0.35),
              ),
            ),
            trailing: isCurrent
                ? Icon(Icons.check_circle, size: 18, color: context.appColors.accent)
                : null,
            onTap: busy ? null : () => pick(g),
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: context.appColors.ink(0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  '收藏到哪个收藏夹',
                  style: TextStyle(
                    fontSize: AppText.body,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.ink(0.9),
                  ),
                ),
              ),
              if (groups == null)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 6, 20, 20),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                  child: Text(
                    '没有可用的收藏夹',
                    style: TextStyle(
                      fontSize: AppText.caption,
                      color: context.appColors.ink(0.35),
                    ),
                  ),
                )
              else
                for (final g in groups) row(g),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    ),
  );
}

/// 邀请指向的具体实例（公开实例列表里通常查不到，只能单独查）。
/// 展示：区域 · 类型 · 实例号 · 人数/容量，以及里面的成员。
class _InvitedInstanceCard extends ConsumerWidget {
  const _InvitedInstanceCard({
    required this.worldId,
    required this.instanceId,
  });

  final String worldId;
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      instanceDetailProvider((worldId: worldId, instanceId: instanceId)),
    );

    // 头部信息直接从 instanceId 解析（不依赖接口是否成功）
    var typeLabel = '';
    var region = '';
    if (instanceId.contains('private(')) {
      typeLabel = instanceId.contains('canRequestInvite') ? '邀请+' : '仅限邀请';
    } else if (instanceId.contains('friends(')) {
      typeLabel = '仅限好友';
    } else if (instanceId.contains('hidden(')) {
      typeLabel = '好友+';
    } else if (instanceId.contains('group(')) {
      typeLabel = '群组';
    } else if (instanceId.isNotEmpty) {
      typeLabel = '公开';
    }
    final regionMatch = RegExp(r'region\(([^)]+)\)').firstMatch(instanceId);
    if (regionMatch != null) region = regionMatch.group(1)!.toUpperCase();
    final number = instanceId.split('~').first;

    final data = async.valueOrNull;
    final occupants = (data?['occupants'] is List)
        ? List<Map<String, dynamic>>.from(
            (data!['occupants'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];
    final count = data?['n_users'] ?? data?['occupantCount'] ?? occupants.length;
    final capacity = data?['capacity'] ?? '?';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.appColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.appColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (typeLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.appColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: AppText.label,
                      fontWeight: FontWeight.w700,
                      color: context.appColors.accent,
                    ),
                  ),
                ),
              if (region.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  region,
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w700,
                    color: context.appColors.ink(0.45),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '#$number',
                  style: TextStyle(
                    fontSize: AppText.caption,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.ink(0.8),
                  ),
                ),
              ),
              Text(
                '$count/$capacity',
                style: TextStyle(
                  fontSize: AppText.label,
                  color: context.appColors.ink(0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InstanceOwner(
            instanceId: instanceId,
            worldId: worldId,
          ),
          _InstanceMembers(
            worldId: worldId,
            instanceId: instanceId,
            occupants: occupants,
            ownerId: data?['ownerId']?.toString() ?? '',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final err = await ref.read(vrcClientProvider).inviteMyself(
                    worldId: worldId,
                    instanceId: instanceId,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err ?? '邀请已发给自己，去 VRChat 客户端接受吧'),
                    ),
                  );
                },
                icon: const Icon(Icons.login, size: 15),
                label: const Text(
                  '邀请自己',
                  style: TextStyle(
                    fontSize: AppText.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: context.appColors.accent,
                  backgroundColor: context.appColors.accent.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 房间成员：先用好友列表里 location 匹配这个实例的好友（VRCX 的做法），
/// 再补上接口返回的 occupants（通常私有实例拿不到）。
class _InstanceMembers extends ConsumerWidget {
  const _InstanceMembers({
    required this.worldId,
    required this.instanceId,
    required this.occupants,
    required this.ownerId,
  });

  final String worldId;
  final String instanceId;
  final List<Map<String, dynamic>> occupants;
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider).friends;

    // 好友里正好在这个实例的，就是房间成员
    final roomFriends = friends
        .where((f) => f.parsedLocation.instanceId != null &&
            f.parsedLocation.instanceId == instanceId)
        .toList();

    final friendIds = roomFriends.map((f) => f.userId).toSet();
    final others = occupants
        .where((o) => !friendIds.contains((o['id'] ?? '').toString()))
        .toList();

    if (roomFriends.isEmpty && others.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        children: [
          for (final f in roomFriends.take(12))
            _MemberTile(
              name: f.displayName,
              avatar: f.avatarUrl ?? '',
              dot: f.statusColor,
              isOwner: f.userId == ownerId,
            ),
          for (final o in others.take(12))
            _MemberTile(
              name: (o['displayName'] ?? '').toString(),
              avatar: (o['iconUrl'] ??
                      o['currentAvatarThumbnailImageUrl'] ??
                      '')
                  .toString(),
              isOwner: (o['id'] ?? '').toString() == ownerId,
            ),
        ],
      ),
    );
  }
}

/// 一个成员头像 + 名字。`dot` 有值就画状态灯，`isOwner` 加皇冠。
class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.name,
    required this.avatar,
    this.dot,
    this.isOwner = false,
  });

  final String name;
  final String avatar;
  final Color? dot;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: avatar.isEmpty
                      ? ColoredBox(color: context.appColors.surfaceHigh)
                      : CachedNetworkImage(
                          imageUrl: avatar,
                          httpHeaders: ref.watch(imageHeadersProvider),
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              ColoredBox(color: context.appColors.surfaceHigh),
                        ),
                ),
              ),
              if (dot != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0B0F14),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              if (isOwner)
                Positioned(
                  left: -4,
                  top: -4,
                  child: Icon(
                    Icons.workspace_premium,
                    size: 14,
                    color: const Color(0xFFFFC94D),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppText.label,
              color: context.appColors.ink(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 实例房主：从 instanceId 的 `private(usr_xxx)` / `friends(usr_xxx)` / `hidden(usr_xxx)` 里
/// 取出 ownerId，查名字和头像。如果是好友，再带上在线状态灯和「在房间里」标记。
class _InstanceOwner extends ConsumerWidget {
  const _InstanceOwner({required this.instanceId, required this.worldId});

  final String instanceId;
  final String worldId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = RegExp(r'(?:private|friends|hidden|group)\(([^)]+)\)')
        .firstMatch(instanceId);
    final ownerId = m?.group(1) ?? '';
    if (ownerId.isEmpty) return const SizedBox.shrink();

    // 好友优先（能拿到状态和实时位置）
    final friends = ref.watch(friendsProvider).friends;
    FriendPresence? friend;
    for (final f in friends) {
      if (f.userId == ownerId) {
        friend = f;
        break;
      }
    }

    final brief = ref.watch(userBriefProvider(ownerId)).valueOrNull;
    final friendName = friend?.displayName ?? '';
    final friendIcon = friend?.avatarUrl ?? '';
    final name = friendName.isNotEmpty ? friendName : (brief?.name ?? '');
    final icon = friendIcon.isNotEmpty ? friendIcon : (brief?.icon ?? '');

    if (name.isEmpty && icon.isEmpty) return const SizedBox.shrink();

    // 好友状态：绿=在线 蓝=Web 橙=忙 红=请勿打扰 灰=离线
    Color? dot;
    if (friend != null) {
      dot = friend.statusColor;
    }
    final inThisRoom = friend != null &&
        friend.parsedLocation.instanceId != null &&
        friend.parsedLocation.instanceId == instanceId;

    return Row(
      children: [
        Icon(
          Icons.workspace_premium,
          size: 13,
          color: const Color(0xFFFFC94D).withValues(alpha: 0.9),
        ),
        const SizedBox(width: 5),
        Text(
          '房主',
          style: TextStyle(
            fontSize: AppText.label,
            fontWeight: FontWeight.w700,
            color: context.appColors.ink(0.4),
          ),
        ),
        const SizedBox(width: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: SizedBox(
                width: 24,
                height: 24,
                child: icon.isEmpty
                    ? ColoredBox(color: context.appColors.surfaceHigh)
                    : CachedNetworkImage(
                        imageUrl: icon,
                        httpHeaders: ref.watch(imageHeadersProvider),
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            ColoredBox(color: context.appColors.surfaceHigh),
                      ),
              ),
            ),
            if (dot != null)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0B0F14),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name.isEmpty ? ownerId : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.ink(0.8),
                  ),
                ),
              ),
              if (inThisRoom) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADE80).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '在房间里',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4ADE80),
                    ),
                  ),
                ),
              ],
              if (friend != null && !inThisRoom) ...[
                const SizedBox(width: 6),
                Text(
                  friend.isOnline ? '好友 · 其他房间' : '好友 · 离线',
                  style: TextStyle(
                    fontSize: 9,
                    color: context.appColors.ink(0.3),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 长文本折叠：超过 [collapsedLines] 行时显示「展开 / 收起」。
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text, this.collapsedLines = 4});

  final String text;
  final int collapsedLines;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: AppText.secondary,
      height: 1.65,
      color: context.appColors.ink(0.8),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.collapsedLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        final overflows = painter.didExceedMaxLines;
        if (!overflows) {
          return Text(widget.text, style: style);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: Text(
                widget.text,
                style: style,
                maxLines: _expanded ? null : widget.collapsedLines,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? '收起' : '展开全文',
                    style: TextStyle(
                      fontSize: AppText.caption,
                      fontWeight: FontWeight.w600,
                      color: context.appColors.accent,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: context.appColors.accent,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 平台信息：支持哪些平台、各自的设备分级、地图体积。
class _PlatformInfo extends ConsumerWidget {
  const _PlatformInfo({required this.world});

  final World world;

  static const _platformLabels = {
    'standalonewindows': 'PC',
    'android': 'Android',
    'ios': 'iOS',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packages = world.unityPackages ?? const [];
    if (packages.isEmpty) return const SizedBox.shrink();

    // 按平台去重（同一个平台可能有多个 variant）
    final byPlatform = <String, UnityPackage>{};
    for (final p in packages) {
      byPlatform.putIfAbsent(p.platform, () => p);
    }

    final platformText = byPlatform.keys
        .map((k) => _platformLabels[k] ?? k)
        .join(' / ');

    // 大小：PC 优先，拿不到再退到其它平台
    final sizePkg = byPlatform['standalonewindows'] ??
        (byPlatform.isNotEmpty ? byPlatform.values.first : null);
    final assetUrl = sizePkg?.assetUrl ?? '';

    return Column(
      children: [
        _Row(label: '平台', value: platformText),
        if (assetUrl.isNotEmpty)
          ref.watch(assetSizeProvider(assetUrl)).when(
                loading: () => const _Row(label: '地图大小', value: '查询中…'),
                error: (_, _) => const _Row(label: '地图大小', value: '—'),
                data: (mb) => _Row(
                  label: '地图大小',
                  value: mb == null
                      ? '—'
                      : '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB',
                ),
              ),
      ],
    );
  }
}
