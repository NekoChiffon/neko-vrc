import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/friend_presence.dart';
import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';
import 'friend_detail_page.dart';
import 'group_detail_page.dart';
import 'world_detail_page.dart';

enum _Scope { users, worlds, groups }

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  _Scope _scope = _Scope.users;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // 让清除按钮跟着输入框一起出现/消失。
    setState(() {});
    _debounce?.cancel();
    // 打字时别每敲一个字就打一次接口，VRChat 会不高兴。
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            controller: _controller,
            // 不要关掉输入法的联想：vivo / iQOO 会把「无联想」的输入框
            // 当成密码框，换成无法输入中文的安全键盘。
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: switch (_scope) {
                _Scope.users => '搜 VRChat 用户',
                _Scope.worlds => '搜世界',
                _Scope.groups => '搜群组',
              },
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _scopeChip('用户', _Scope.users),
              const SizedBox(width: 8),
              _scopeChip('世界', _Scope.worlds),
              const SizedBox(width: 8),
              _scopeChip('群组', _Scope.groups),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _query.isEmpty
              ? const _Hint(icon: Icons.manage_search, text: '输入关键词开始搜索')
              : switch (_scope) {
                  _Scope.users => _userResults(),
                  _Scope.worlds => _worldResults(),
                  _Scope.groups => _groupResults(),
                },
        ),
      ],
    );
  }

  Widget _scopeChip(String label, _Scope scope) {
    final active = _scope == scope;
    return GestureDetector(
      onTap: () => setState(() => _scope = scope),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          border: Border.all(
            color: active ? AppTheme.accent.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppText.caption,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppTheme.accent : Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _userResults() {
    final async = ref.watch(userSearchProvider(_query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => _Hint(
        icon: Icons.error_outline,
        text: _friendly(e),
      ),
      data: (users) {
        if (users.isEmpty) {
          return const _Hint(icon: Icons.person_off_outlined, text: '没有找到这个用户');
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: users.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            indent: 74,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          itemBuilder: (context, i) => _UserRow(user: users[i]),
        );
      },
    );
  }

  Widget _worldResults() {
    final async = ref.watch(worldSearchProvider(_query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => _Hint(icon: Icons.error_outline, text: _friendly(e)),
      data: (worlds) {
        if (worlds.isEmpty) {
          return const _Hint(icon: Icons.public_off, text: '没有找到相关世界');
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: worlds.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            indent: 100,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          itemBuilder: (context, i) => _WorldRow(world: worlds[i]),
        );
      },
    );
  }

  Widget _groupResults() {
    final async = ref.watch(groupSearchProvider(_query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => _Hint(icon: Icons.error_outline, text: _friendly(e)),
      data: (groups) {
        if (groups.isEmpty) {
          return const _Hint(icon: Icons.groups_outlined, text: '没有找到相关群组');
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: groups.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            indent: 74,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          itemBuilder: (context, i) => _GroupRow(group: groups[i]),
        );
      },
    );
  }

  String _friendly(Object e) {
    final t = e.toString();
    if (t.contains('429')) return '搜太频繁了，等一会儿再试';
    if (t.contains('SocketException') || t.contains('Timeout')) {
      return '连不上 VRChat，检查网络';
    }
    return t.replaceFirst('Exception: ', '');
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user});

  final LimitedUserSearch user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trust = FriendPresence.trustRankFromTags(user.tags);
    final avatar = user.iconUrl;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FriendDetailPage(presence: FriendPresence.fromSearch(user)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _Circle(url: avatar, name: user.displayName, headers: ref.watch(imageHeadersProvider)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppText.body,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (user.isFriend) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '好友',
                            style: TextStyle(fontSize: AppText.label, color: AppTheme.accent),
                          ),
                        ),
                      ],
                      if (trust != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          trust,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (user.statusDescription.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      user.statusDescription.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: Colors.white.withValues(alpha: 0.35),
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

class _WorldRow extends ConsumerWidget {
  const _WorldRow({required this.world});

  final LimitedWorld world;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorldDetailPage(worldId: world.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: CachedNetworkImage(
                imageUrl: world.thumbnailImageUrl,
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
                    world.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${world.authorName} · ${world.occupants} 人在此 · 容量 ${world.capacity}',
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
          ],
        ),
      ),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  const _GroupRow({required this.group});

  final LimitedGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = group.id ?? '';
    final name = (group.name ?? '').trim();
    final desc = (group.description ?? '').trim();
    final members = group.memberCount ?? 0;
    final code = (group.shortCode ?? '').trim();
    final icon = group.iconUrl ?? '';

    final fallback = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: const Icon(Icons.groups, size: 20, color: Colors.white24),
    );

    return InkWell(
      onTap: id.isEmpty
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GroupDetailPage(groupId: id),
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: icon.isEmpty
                  ? fallback
                  : CachedNetworkImage(
                      imageUrl: icon,
                      httpHeaders: ref.watch(imageHeadersProvider),
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => fallback,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? '未命名群组' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppText.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.label,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    code.isEmpty ? '$members 成员' : '$members 成员 · $code',
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
          ],
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.url, required this.name, required this.headers});

  final String? url;
  final String name;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    const size = 46.0;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surfaceHigh,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white54),
      ),
    );

    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        httpHeaders: headers,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.caption,
                height: 1.6,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
