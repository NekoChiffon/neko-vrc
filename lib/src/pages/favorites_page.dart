import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';
import 'world_detail_page.dart';

/// 收藏的世界，按收藏夹分区显示。
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key, this.groupKey});

  /// 只显示某一个收藏夹（从资料页的卡片点进来时用）。
  final String? groupKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoritedWorldsProvider);
    final all = ref.watch(favoriteSectionsProvider);
    final sections = groupKey == null
        ? all
        : all.where((s) => s.key == groupKey).toList();
    final pageTitle = groupKey == null
        ? '收藏的世界'
        : (sections.isEmpty ? '收藏的世界' : sections.first.title);

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              ref.invalidate(favoritedWorldsProvider);
              ref.invalidate(favoriteGroupsProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
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
        data: (_) {
          if (sections.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_border,
                      size: 42,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '还没有收藏任何世界',
                      style: TextStyle(
                        fontSize: AppText.secondary,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '在世界详情页右上角点星标就能收藏',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final children = <Widget>[];
          for (final section in sections) {
            children.add(
              _SectionHeader(title: section.title, count: section.worlds.length),
            );
            for (final w in section.worlds) {
              children.add(_FavoriteRow(world: w));
            }
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(favoritedWorldsProvider);
              ref.invalidate(favoriteGroupsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: children,
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
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
            '$count 个',
            style: TextStyle(
              fontSize: AppText.label,
              color: Colors.white.withValues(alpha: 0.32),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteRow extends ConsumerStatefulWidget {
  const _FavoriteRow({required this.world});

  final FavoritedWorld world;

  @override
  ConsumerState<_FavoriteRow> createState() => _FavoriteRowState();
}

class _FavoriteRowState extends ConsumerState<_FavoriteRow> {
  bool _busy = false;

  Future<void> _unfavorite() async {
    final favoriteId = widget.world.favoriteId;
    if (favoriteId == null) return;
    setState(() => _busy = true);
    final err = await ref.read(vrcClientProvider).removeWorldFavorite(favoriteId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      ref.invalidate(favoritedWorldsProvider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.world;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorldDetailPage(worldId: w.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: CachedNetworkImage(
                imageUrl: w.thumbnailImageUrl,
                httpHeaders: ref.watch(imageHeadersProvider),
                width: 72,
                height: 54,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  width: 72,
                  height: 54,
                  color: AppTheme.surfaceHigh,
                  child: const Icon(Icons.public, size: 18, color: Colors.white24),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${w.authorName} · ${w.occupants} 人在此',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.label,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '取消收藏',
              onPressed: _busy ? null : _unfavorite,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.star, size: 19, color: Color(0xFFFBBF24)),
            ),
          ],
        ),
      ),
    );
  }
}
