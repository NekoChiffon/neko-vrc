import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/friends_provider.dart';
import '../theme.dart';
import 'world_detail_page.dart';

/// 一组世界的列表（比如「某人上传的公开世界」）。
class WorldListPage extends ConsumerWidget {
  const WorldListPage({super.key, required this.title, required this.worlds});

  final String title;
  final List<LimitedWorld> worlds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(imageHeadersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: worlds.isEmpty
          ? Center(
              child: Text(
                '这里还是空的',
                style: TextStyle(
                  fontSize: AppText.caption,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 16 / 11,
              ),
              itemCount: worlds.length,
              itemBuilder: (context, i) {
                final w = worlds[i];
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WorldDetailPage(worldId: w.id),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.field),
                          child: CachedNetworkImage(
                            imageUrl: w.thumbnailImageUrl,
                            httpHeaders: headers,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const ColoredBox(
                              color: AppTheme.surfaceHigh,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
