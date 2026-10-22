import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/friends_provider.dart';
import '../theme.dart';

/// 模型详情。
final avatarDetailProvider =
    FutureProvider.family<Avatar, String>((ref, avatarId) async {
  final resp = await ref
      .read(vrcClientProvider)
      .api
      .rawApi
      .getAvatarsApi()
      .getAvatar(avatarId: avatarId);
  final data = resp.data;
  if (data == null) throw Exception('模型不存在');
  return data;
});

class AvatarDetailPage extends ConsumerStatefulWidget {
  const AvatarDetailPage({super.key, required this.avatarId});

  final String avatarId;

  @override
  ConsumerState<AvatarDetailPage> createState() => _AvatarDetailPageState();
}

class _AvatarDetailPageState extends ConsumerState<AvatarDetailPage> {
  bool _switching = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(avatarDetailProvider(widget.avatarId));
    final auth = ref.watch(authProvider);
    final isCurrent =
        auth is AuthSignedIn && auth.user.currentAvatar == widget.avatarId;

    return Scaffold(
      appBar: AppBar(title: const Text('模型详情')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.caption,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
        data: (avatar) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // 大图
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: CachedNetworkImage(
                  imageUrl: avatar.imageUrl,
                  httpHeaders: ref.watch(imageHeadersProvider),
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const ColoredBox(color: AppTheme.surfaceHigh),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              avatar.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (avatar.authorName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'by ${avatar.authorName}',
                style: TextStyle(
                  fontSize: AppText.caption,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ],
            if (isCurrent) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Text(
                      '当前模型',
                      style: TextStyle(
                        fontSize: AppText.caption,
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 切换按钮
            if (!isCurrent)
              FilledButton.icon(
                onPressed: _switching ? null : () => _switchTo(avatar.name),
                icon: _switching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 17),
                label: const Text('设为当前模型'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),

            // 性能评级
            const SizedBox(height: 18),
            _Card(
              title: '性能',
              child: Column(
                children: [
                  _PerfRow(
                    platform: 'PC',
                    rank: avatar.performance.standalonewindows,
                  ),
                  _PerfRow(platform: '安卓', rank: avatar.performance.android),
                  _PerfRow(platform: 'iOS', rank: avatar.performance.ios),
                ],
              ),
            ),

            // 信息
            const SizedBox(height: 10),
            _Card(
              title: '信息',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (avatar.description.isNotEmpty) ...[
                    Text(
                      avatar.description,
                      style: TextStyle(
                        fontSize: AppText.caption,
                        height: 1.6,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _InfoRow(
                    label: '模型 ID',
                    value: avatar.id,
                    copiable: true,
                  ),
                  _InfoRow(
                    label: '版本',
                    value: 'v${avatar.version}',
                  ),
                  _InfoRow(
                    label: '发布状态',
                    value: _releaseLabel(avatar.releaseStatus),
                  ),
                  _InfoRow(label: '创建时间', value: _date(avatar.createdAt)),
                  _InfoRow(label: '更新时间', value: _date(avatar.updatedAt)),
                  _InfoRow(
                    label: 'VRChat 链接',
                    value: 'vrchat.com/home/avat/${widget.avatarId}',
                    copiable: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchTo(String name) async {
    setState(() => _switching = true);
    final err = await ref
        .read(vrcClientProvider)
        .selectAvatar(widget.avatarId);
    if (!mounted) return;
    setState(() => _switching = false);
    if (err == null) {
      ref.invalidate(avatarDetailProvider(widget.avatarId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到「$name」，下次进房生效')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  static String _releaseLabel(ReleaseStatus status) => switch (status) {
    ReleaseStatus.public => '公开',
    ReleaseStatus.private => '私密',
    ReleaseStatus.hidden => '隐藏',
    _ => '未知',
  };

  static String _date(DateTime t) =>
      '${t.year}/${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 评级颜色（和 VRChat 的蓝绿橙红一致）。
Color performanceColor(String? rank) => switch (rank?.toLowerCase()) {
  'excellent' => const Color(0xFF38BDF8),
  'good' => const Color(0xFF4ADE80),
  'medium' => const Color(0xFFFBBF24),
  'poor' => const Color(0xFFFB923C),
  'verypoor' => const Color(0xFFF87171),
  _ => Colors.white38,
};

String performanceLabel(String? rank) => switch (rank?.toLowerCase()) {
  'excellent' => '极佳',
  'good' => '优',
  'medium' => '中',
  'poor' => '差',
  'verypoor' => '极高负载',
  'none' => '无',
  _ => rank ?? '—',
};

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xE6151B23),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PerfRow extends StatelessWidget {
  const _PerfRow({required this.platform, required this.rank});

  final String platform;
  final String? rank;

  @override
  Widget build(BuildContext context) {
    final has = rank != null && rank!.isNotEmpty && rank != 'none';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              platform,
              style: TextStyle(
                fontSize: AppText.caption,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: performanceColor(rank).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              has ? performanceLabel(rank) : '—',
              style: TextStyle(
                fontSize: AppText.caption,
                fontWeight: FontWeight.w600,
                color: performanceColor(rank),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.copiable = false,
  });

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
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppText.caption,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: AppText.caption, color: Colors.white70),
            ),
          ),
          if (copiable)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制')),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
