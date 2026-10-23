import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/location_parser.dart';
import '../models/friend_presence.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';
import '../widgets/profile_view.dart';

/// 好友（或任意用户）的资料页。
///
/// 主体交给 [ProfileView]，这里补好友专属的部分：
/// 备注卡片、当前所在房间、邀请操作、右上角更多菜单。
class FriendDetailPage extends ConsumerStatefulWidget {
  const FriendDetailPage({super.key, required this.presence});

  final FriendPresence presence;

  @override
  ConsumerState<FriendDetailPage> createState() => _FriendDetailPageState();
}

class _FriendDetailPageState extends ConsumerState<FriendDetailPage> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendsProvider);

    // 优先用 provider 里的最新状态，这样 Pipeline 推来变化时这里也会跟着刷新。
    var current = widget.presence;
    for (final f in state.friends) {
      if (f.userId == widget.presence.userId) {
        current = f;
        break;
      }
    }

    final detail = ref.watch(userDetailProvider(current.userId)).valueOrNull;
    final note = (detail?.note ?? '').trim();

    return Scaffold(
      body: ProfileView(
        userId: current.userId,
        presence: current,
        onOpenMenu: () => _showMenu(current),
        footer: [
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            _NoteCard(note: note, onEdit: () => _editNote(current.userId, note)),
          ],
          const SizedBox(height: 10),
          _LocationSection(presence: current),
          const SizedBox(height: 10),
          _InviteActions(userId: current.userId),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 菜单
  // -------------------------------------------------------------------------

  void _showMenu(FriendPresence friend) {
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
            _MenuTile(
              icon: Icons.touch_app_outlined,
              label: '戳一戳',
              onTap: () {
                Navigator.pop(ctx);
                _boop(friend.userId);
              },
            ),
            _MenuTile(
              icon: Icons.edit_note,
              label: '设置备注',
              hint: '只有你自己能看到',
              onTap: () {
                Navigator.pop(ctx);
                _editNote(friend.userId, '');
              },
            ),
            _MenuTile(
              icon: Icons.copy_rounded,
              label: '复制用户 ID',
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: friend.userId));
                _toast('已复制 ${friend.userId}');
              },
            ),
            _MenuTile(
              icon: Icons.flag_outlined,
              label: '举报',
              hint: '复制举报页链接，用浏览器打开',
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(
                  ClipboardData(
                    text: 'https://vrchat.com/home/user/${friend.userId}',
                  ),
                );
                _toast('已复制对方主页链接，可在网页端点举报');
              },
            ),
            const Divider(height: 20),
            _MenuTile(
              icon: Icons.person_remove_outlined,
              label: '删除好友',
              danger: true,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(friend);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _boop(String userId) async {
    final err = await ref.read(vrcClientProvider).boopUser(userId);
    if (!mounted) return;
    _toast(err ?? '戳了一下');
  }

  Future<void> _editNote(String userId, String current) async {
    final controller = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置备注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          maxLength: 256,
          decoration: InputDecoration(
            hintText: '只有你自己看得到',
            counterStyle: TextStyle(fontSize: 10, color: context.appColors.ink(0.24)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;

    final err = await ref.read(vrcClientProvider).setUserNote(userId, saved);
    if (!mounted) return;
    if (err == null) {
      ref.invalidate(userDetailProvider(userId));
      ref.invalidate(friendNotesProvider);
      _toast(saved.trim().isEmpty ? '备注已清空' : '备注已保存');
    } else {
      _toast(err);
    }
  }

  Future<void> _confirmDelete(FriendPresence friend) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友？'),
        content: Text('「${friend.displayName}」会从好友列表里移除，这个操作不能撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF87171)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final err = await ref.read(vrcClientProvider).removeFriend(friend.userId);
    if (!mounted) return;
    if (err == null) {
      await ref.read(friendsProvider.notifier).refresh();
      if (mounted) Navigator.of(context).maybePop();
      _toast('已删除好友');
    } else {
      _toast(err);
    }
  }
}

/// 备注卡片。只有自己能看到，所以单独标一下。
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onEdit});

  final String note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '备注',
                style: TextStyle(
                  fontSize: AppText.label,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: context.appColors.accent,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '仅自己可见',
                style: TextStyle(
                  fontSize: 10,
                  color: context.appColors.ink(0.28),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onEdit,
                child: Icon(Icons.edit_outlined, size: 15, color: context.appColors.ink(0.38)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: TextStyle(
              fontSize: AppText.secondary,
              height: 1.6,
              color: context.appColors.ink(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? hint;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? const Color(0xFFFCA5A5)
        : context.appColors.ink(1);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color.withValues(alpha: danger ? 0.9 : 0.55)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppText.body,
                      color: color.withValues(alpha: 0.9),
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

/// 当前所在房间。
class _LocationSection extends ConsumerWidget {
  const _LocationSection({required this.presence});

  final FriendPresence presence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = presence.parsedLocation;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '所在世界',
            style: TextStyle(
              fontSize: AppText.label,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.appColors.accent,
            ),
          ),
          const SizedBox(height: 10),
          if (!loc.hasWorld)
            Text(
              !presence.isOnline
                  ? '离线'
                  : loc.isPrivate
                  ? '私密世界'
                  : presence.isWebPlatform
                  ? 'Web 在线'
                  : '位置不可见',
              style: TextStyle(
                fontSize: AppText.secondary,
                color: context.appColors.ink(0.55),
              ),
            )
          else
            Row(
              children: [
                Icon(
                  Icons.meeting_room_outlined,
                  size: 15,
                  color: context.appColors.accent.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WorldName(
                    worldId: loc.worldId!,
                    type: loc.instanceType.label,
                  ),
                ),
                if (loc.instanceId != null) _Occupants(location: loc),
                if (loc.instanceId != null)
                  _CopyLaunchLink(worldId: loc.worldId!, instanceId: loc.instanceId!),
              ],
            ),
        ],
      ),
    );
  }
}

class _WorldName extends ConsumerWidget {
  const _WorldName({required this.worldId, required this.type});

  final String worldId;
  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(worldNameProvider(worldId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        async.when(
          loading: () => Text(
            '载入世界名…',
            style: TextStyle(fontSize: AppText.secondary, color: context.appColors.ink(0.4)),
          ),
          error: (_, _) => Text(
            worldId,
            style: TextStyle(fontSize: AppText.caption, color: context.appColors.ink(0.4)),
          ),
          data: (name) => Text(
            name ?? worldId,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          type,
          style: TextStyle(fontSize: AppText.label, color: context.appColors.ink(0.35)),
        ),
      ],
    );
  }
}

class _Occupants extends ConsumerWidget {
  const _Occupants({required this.location});

  final ParsedLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worldId = location.worldId;
    final instanceId = location.instanceId;
    if (worldId == null || instanceId == null) return const SizedBox.shrink();

    final async = ref.watch(
      instanceOccupantsProvider((worldId: worldId, instanceId: instanceId)),
    );

    return async.maybeWhen(
      data: (n) => n == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '$n 人在此',
                style: TextStyle(
                  fontSize: AppText.label,
                  color: context.appColors.ink(0.4),
                ),
              ),
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 把「好友所在实例」拼成 VRChat 深链复制走。
class _CopyLaunchLink extends StatelessWidget {
  const _CopyLaunchLink({required this.worldId, required this.instanceId});

  final String worldId;
  final String instanceId;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final link = buildLaunchLink(worldId, instanceId);
        Clipboard.setData(ClipboardData(text: link));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已复制：$link'),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          Icons.link_rounded,
          size: 16,
          color: context.appColors.ink(0.4),
        ),
      ),
    );
  }
}

/// 邀请 / 请求加入。只在对方确实是好友时出现。
class _InviteActions extends ConsumerStatefulWidget {
  const _InviteActions({required this.userId});

  final String userId;

  @override
  ConsumerState<_InviteActions> createState() => _InviteActionsState();
}

class _InviteActionsState extends ConsumerState<_InviteActions> {
  bool _busy = false;

  Future<void> _run(
    String Function(String? error) message,
    Future<String?> Function() action,
  ) async {
    setState(() => _busy = true);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message(err))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(userDetailProvider(widget.userId));
    final isFriend = detail.valueOrNull?.isFriend ?? false;
    if (!isFriend) return const SizedBox.shrink();

    final client = ref.read(vrcClientProvider);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    (err) => err ?? '邀请已发出，等 TA 进来吧',
                    () => client.inviteFriendToMe(widget.userId),
                  ),
            icon: const Icon(Icons.mail_outline, size: 17),
            label: const Text('邀请 TA 过来'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    (err) => err ?? '已请求对方邀请你',
                    () => client.requestInviteFrom(widget.userId),
                  ),
            icon: const Icon(Icons.pan_tool_alt_outlined, size: 17),
            label: const Text('请求加入'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: context.appColors.ink(0.7),
              side: BorderSide(color: context.appColors.ink(0.15)),
            ),
          ),
        ),
      ],
    );
  }
}
