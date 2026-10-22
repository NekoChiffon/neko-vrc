import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';

/// 群组详情：横幅、成员数、公告、简介、规则。
class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupDetailProvider(groupId));
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppText.secondary, color: Colors.white.withValues(alpha: 0.45)),
            ),
          ),
        ),
        data: (group) => Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SizedBox(
                            height: 160,
                            child: _Banner(url: group.bannerUrl),
                          ),
                          Positioned(
                            left: 16,
                            top: 160 - 32,
                            child: _GroupIcon(url: group.iconUrl),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32 + 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              group.name ?? '未命名群组',
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              children: [
                                _Stat(
                                  icon: Icons.people_outline,
                                  text: '${group.memberCount ?? 0} 成员',
                                ),
                                if ((group.onlineMemberCount ?? 0) > 0)
                                  _Stat(
                                    icon: Icons.circle,
                                    text: '${group.onlineMemberCount} 在线',
                                    color: const Color(0xFF4ADE80),
                                  ),
                                if ((group.shortCode ?? '').isNotEmpty)
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(text: group.shortCode!),
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('已复制群组短码 ${group.shortCode}')),
                                      );
                                    },
                                    child: _Stat(
                                      icon: Icons.tag,
                                      text: group.shortCode!,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _Announcement(groupId: groupId),
                            if ((group.description ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _Card(
                                title: '简介',
                                child: Text(
                                  group.description!.trim(),
                                  style: TextStyle(
                                    fontSize: AppText.secondary,
                                    height: 1.65,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ],
                            if ((group.rules ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _Card(
                                title: '规则',
                                child: Text(
                                  group.rules!.trim(),
                                  style: TextStyle(
                                    fontSize: AppText.caption,
                                    height: 1.7,
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            _Card(
                              title: '信息',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Row(label: '群组 ID', value: groupId, copiable: true),
                                  _Row(label: '隐私', value: _privacy(group.privacy)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: topInset + 8,
              left: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back, size: 19, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _privacy(GroupPrivacy? privacy) =>
      privacy == GroupPrivacy.private ? '私密' : '公开';
}

class _Banner extends StatelessWidget {
  const _Banner({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2630), Color(0xFF0B0F14)],
        ),
      ),
    );

    if (url == null || url!.isEmpty) return fallback;

    return Consumer(
      builder: (context, ref, _) => CachedNetworkImage(
        imageUrl: url!,
        httpHeaders: ref.watch(imageHeadersProvider),
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

class _GroupIcon extends ConsumerWidget {
  const _GroupIcon({this.url});

  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const size = 64.0;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Icon(Icons.groups, color: Colors.white24),
    );

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.canvas,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: url == null || url!.isEmpty
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: CachedNetworkImage(
                imageUrl: url!,
                httpHeaders: ref.watch(imageHeadersProvider),
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

class _Announcement extends ConsumerWidget {
  const _Announcement({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupAnnouncementProvider(groupId));
    final a = async.valueOrNull;
    final title = (a?.title ?? '').trim();
    final text = (a?.text ?? '').trim();
    if (a == null || (title.isEmpty && text.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Card(
        title: '公告',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
              ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: AppText.caption,
                  height: 1.65,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (a.imageUrl != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.field),
                child: CachedNetworkImage(
                  imageUrl: a.imageUrl!,
                  httpHeaders: ref.watch(imageHeadersProvider),
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: AppText.caption,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 66,
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
                  const SnackBar(content: Text('已复制群组 ID')),
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
