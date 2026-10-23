import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';
import 'group_detail_page.dart';

/// 某个用户加入的全部群组。
class GroupListPage extends ConsumerWidget {
  const GroupListPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userGroupsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('群组'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(userGroupsProvider(userId)),
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
              style: TextStyle(fontSize: AppText.caption, color: context.appColors.ink(0.45)),
            ),
          ),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return Center(
              child: Text(
                '还没有加入任何群组',
                style: TextStyle(fontSize: AppText.caption, color: context.appColors.ink(0.4)),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: groups.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 66,
              color: context.appColors.ink(0.05),
            ),
            itemBuilder: (context, i) => _GroupRow(group: groups[i]),
          );
        },
      ),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  const _GroupRow({required this.group});

  final LimitedUserGroups group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupId = group.groupId ?? group.id;
    final icon = group.iconUrl;

    return InkWell(
      onTap: (groupId == null || groupId.isEmpty)
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GroupDetailPage(groupId: groupId),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: (icon ?? '').isEmpty
                  ? Container(
                      width: 40,
                      height: 40,
                      color: context.appColors.surfaceHigh,
                      child: Icon(Icons.groups, size: 18, color: context.appColors.ink(0.24)),
                    )
                  : CachedNetworkImage(
                      imageUrl: icon!,
                      httpHeaders: ref.watch(imageHeadersProvider),
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        width: 40,
                        height: 40,
                        color: context.appColors.surfaceHigh,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (group.isRepresenting == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: context.appColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '代表',
                            style: TextStyle(fontSize: AppText.label, color: context.appColors.accent),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if ((group.memberCount ?? 0) > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${group.memberCount} 成员',
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: context.appColors.ink(0.35),
                      ),
                    ),
                  ],
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
