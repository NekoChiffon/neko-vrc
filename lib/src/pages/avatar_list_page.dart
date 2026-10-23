import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/friends_provider.dart';
import '../theme.dart';
import 'avatar_detail_page.dart';

/// 自己（或别人）的模型列表，按更新时间从新到旧。
///
/// 单页最多 100 个，模型多的话要翻页 —— 只拉一页会「显示不全」。
final avatarListProvider =
    FutureProvider.family<List<Avatar>, String>((ref, userId) async {
  final api = ref.read(vrcClientProvider).api.rawApi.getAvatarsApi();
  final out = <Avatar>[];
  var offset = 0;
  for (var page = 0; page < 10; page++) {
    final resp = await api.searchAvatars(
      userId: userId,
      n: 100,
      offset: offset,
      releaseStatus: ReleaseStatus.all,
    );
    final batch = resp.data ?? <Avatar>[];
    out.addAll(batch);
    if (batch.length < 100) break;
    offset += 100;
  }
  // 新的在前：SDK 没给「按用户列模型」的默认排序，本地排最稳。
  out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return out;
});

class AvatarListPage extends ConsumerWidget {
  const AvatarListPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(avatarListProvider(userId));
    final auth = ref.watch(authProvider);
    final currentAvatar =
        auth is AuthSignedIn ? auth.user.currentAvatar : null;

    return Scaffold(
      appBar: AppBar(title: const Text('我的模型')),
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
                color: context.appColors.ink(0.45),
              ),
            ),
          ),
        ),
        data: (avatars) {
          if (avatars.isEmpty) {
            return Center(
              child: Text(
                '还没有上传过模型',
                style: TextStyle(
                  fontSize: AppText.caption,
                  color: context.appColors.ink(0.4),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(avatarListProvider(userId)),
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 16 / 12,
              ),
              itemCount: avatars.length,
              itemBuilder: (context, i) {
                final a = avatars[i];
                final isCurrent = a.id == currentAvatar;
                return _AvatarCard(
                  name: a.name,
                  imageUrl: a.thumbnailImageUrl.isNotEmpty
                      ? a.thumbnailImageUrl
                      : a.imageUrl,
                  isCurrent: isCurrent,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AvatarDetailPage(avatarId: a.id),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AvatarCard extends ConsumerWidget {
  const _AvatarCard({
    required this.name,
    required this.imageUrl,
    required this.isCurrent,
    required this.onTap,
  });

  final String name;
  final String imageUrl;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(
            color: isCurrent
                ? context.appColors.accent
                : context.appColors.ink(0.06),
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                httpHeaders: ref.watch(imageHeadersProvider),
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => ColoredBox(
                  color: context.appColors.surfaceHigh,
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 26,
                      color: context.appColors.ink(0.24),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xE60B0F14)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppText.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: context.appColors.accent,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
