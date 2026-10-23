import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/cosmetics_provider.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';

/// 换头像框 / 名字牌 / 资料特效。
///
/// 列表来自 `cosmetics/index/*`（VRChat 的全部模板），选中后提交给 `/profile`。
/// 没买过的装饰服务端会拒绝，这里没法提前过滤 —— 接口不告诉你「我拥有哪些」。
class CosmeticsPickerPage extends ConsumerStatefulWidget {
  const CosmeticsPickerPage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<CosmeticsPickerPage> createState() => _CosmeticsPickerPageState();
}

class _CosmeticsPickerPageState extends ConsumerState<CosmeticsPickerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _saving = false;

  static const _kinds = [
    (key: 'iconFrame', label: '头像框'),
    (key: 'nameplateEffect', label: '名字牌'),
    (key: 'profileEffect', label: '资料特效'),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _kinds.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(userDetailProvider(widget.userId)).valueOrNull;
    final cosmetics = ref.watch(cosmeticsProvider).valueOrNull;

    final current = {
      'iconFrame': detail?.iconFrameId ?? '',
      'nameplateEffect': detail?.nameplateEffectId ?? '',
      'profileEffect': detail?.profileEffectId ?? '',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('个人资料装饰'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: context.appColors.accent,
          labelColor: context.appColors.accent,
          unselectedLabelColor: context.appColors.ink(0.54),
          labelStyle: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: AppText.secondary),
          tabs: [for (final k in _kinds) Tab(text: k.label)],
        ),
      ),
      body: cosmetics == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                for (final kind in _kinds)
                  _Grid(
                    items: _itemsFor(cosmetics, kind.key),
                    selectedId: current[kind.key] ?? '',
                    saving: _saving,
                    onPick: (id) => _apply(kind.key, id),
                  ),
              ],
            ),
    );
  }

  List<InventoryTemplate> _itemsFor(CosmeticsIndex index, String kind) {
    final map = switch (kind) {
      'iconFrame' => index.iconFrames,
      'nameplateEffect' => index.nameplates,
      _ => index.profileEffects,
    };
    final list = map.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> _apply(String kind, String id) async {
    setState(() => _saving = true);
    final client = ref.read(vrcClientProvider);
    final err = await client.updateProfile(
      userId: widget.userId,
      profileEffect: kind == 'profileEffect' ? id : null,
      nameplateEffect: kind == 'nameplateEffect' ? id : null,
      iconFrame: kind == 'iconFrame' ? id : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (err == null) {
      ref.invalidate(userDetailProvider(widget.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(id.isEmpty ? '已取消' : '已换上')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err（可能你还没拥有这一款）')),
      );
    }
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.items,
    required this.selectedId,
    required this.saving,
    required this.onPick,
  });

  final List<InventoryTemplate> items;
  final String selectedId;
  final bool saving;
  final void Function(String id) onPick;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final headers = ref.watch(imageHeadersProvider);

        return GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, i) {
            // 第一格是「不使用」
            if (i == 0) {
              return _Tile(
                label: '不使用',
                selected: selectedId.isEmpty,
                onTap: saving ? null : () => onPick(''),
                child: Icon(
                  Icons.block,
                  size: 28,
                  color: context.appColors.ink(0.2),
                ),
              );
            }

            final item = items[i - 1];
            return _Tile(
              label: item.name,
              selected: item.id == selectedId,
              onTap: saving ? null : () => onPick(item.id),
              child: item.imageUrl.isEmpty
                  ? Icon(
                      Icons.auto_awesome,
                      size: 26,
                      color: context.appColors.ink(0.2),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      httpHeaders: headers,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        size: 24,
                        color: context.appColors.ink(0.2),
                      ),
                    ),
            );
          },
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? context.appColors.accent.withValues(alpha: 0.12)
              : context.appColors.ink(0.04),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? context.appColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: child,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.label,
                height: 1.3,
                color: selected
                    ? context.appColors.accent
                    : context.appColors.ink(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
