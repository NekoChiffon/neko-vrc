import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/vrc_client.dart';
import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';

/// 玩家管理：自己点过的屏蔽 / 禁言记录，可以在这里解除。
class PlayerManagePage extends ConsumerWidget {
  const PlayerManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playerModerationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('玩家管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(playerModerationsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(playerModerationsProvider),
        child: async.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => _Hint(
            icon: Icons.cloud_off,
            text: e.toString().replaceFirst('Exception: ', ''),
          ),
          data: (records) {
            if (records.isEmpty) {
              return const _Hint(
                icon: Icons.shield_outlined,
                text: '还没有屏蔽或禁言的记录',
              );
            }
            final sorted = [...records]..sort(
              (a, b) => (b.created ?? DateTime(1970)).compareTo(
                a.created ?? DateTime(1970),
              ),
            );

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = sorted[i];
                return _ModerationRow(
                  record: r,
                  onDelete: () => _confirmDelete(context, ref, r),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PlayerModerationRecord record,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('解除「${record.label}」？'),
        content: Text(record.targetDisplayName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final err =
        await ref.read(vrcClientProvider).deletePlayerModeration(record.id);
    ref.invalidate(playerModerationsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '已解除')),
    );
  }
}

class _ModerationRow extends StatelessWidget {
  const _ModerationRow({required this.record, required this.onDelete});

  final PlayerModerationRecord record;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _visual(context);
    final created = record.created;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.appColors.ink(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.targetDisplayName.isEmpty
                            ? '未知玩家'
                            : record.targetDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.secondary,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.ink(0.9),
                        ),
                      ),
                    ),
                    if (created != null)
                      Text(
                        _stamp(created),
                        style: TextStyle(
                          fontSize: AppText.label,
                          color: context.appColors.ink(0.28),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  record.sourceDisplayName.isEmpty
                      ? record.label
                      : '${record.label} · 来源 ${record.sourceDisplayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.label,
                    color: context.appColors.ink(0.42),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '解除',
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 19,
              color: context.appColors.ink(0.4),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _visual(BuildContext context) {
    if (record.isBlock) return (Icons.block, const Color(0xFFF87171));
    if (record.type.contains('mute')) {
      return (Icons.volume_off, const Color(0xFFFBBF24));
    }
    if (record.type == 'hideAvatar' || record.type == 'showAvatar') {
      return (Icons.visibility_off_outlined, const Color(0xFFA78BFA));
    }
    if (record.type.startsWith('interact')) {
      return (Icons.pan_tool_alt_outlined, const Color(0xFF60A5FA));
    }
    return (Icons.shield_outlined, context.appColors.ink(0.6));
  }

  static String _stamp(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.month}/${t.day} $hh:$mm';
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.24),
        Icon(icon, size: 42, color: context.appColors.ink(0.2)),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppText.secondary,
              height: 1.6,
              color: context.appColors.ink(0.45),
            ),
          ),
        ),
      ],
    );
  }
}
