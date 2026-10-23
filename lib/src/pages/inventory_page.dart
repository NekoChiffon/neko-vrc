import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/vrc_client.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';

/// 库存：表情、贴纸、道具、各种皮肤和礼包。
///
/// 接口是 `/inventory`，按页取（每页 60），支持类型 / 归档 / 排序三种筛选。
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  static const _types = <({String key, String label})>[
    (key: 'all', label: '全部'),
    (key: 'bundle', label: '礼包'),
    (key: 'droneskin', label: '无人机皮肤'),
    (key: 'portalskin', label: '传送门皮肤'),
    (key: 'prop', label: '道具'),
    (key: 'warpeffect', label: '传送特效'),
  ];

  static const _orders = <({String key, String label})>[
    (key: 'newest', label: '最近更新'),
    (key: 'newest_created', label: '最近获得'),
    (key: 'oldest', label: '最早更新'),
    (key: 'oldest_created', label: '最早获得'),
  ];

  String _type = 'all';
  String _order = 'newest';

  final List<InventoryItem> _items = [];

  /// 已经消费掉的服务端条数（不是展示条数：表情/贴纸会被过滤掉）。
  int _offset = 0;
  int _lastBatchSize = 0;
  int? _total;
  int? _balance;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load(reset: true);
      _loadBalance();
    });
  }

  Future<void> _loadBalance() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSignedIn) return;
    final balance = await ref
        .read(vrcClientProvider)
        .fetchCreditsBalance(auth.user.id);
    if (mounted) setState(() => _balance = balance);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final start = reset ? 0 : _offset;
      final result = await ref.read(vrcClientProvider).fetchInventory(
        n: 60,
        offset: start,
        type: _type == 'all' ? null : _type,
        // 没有归档筛选了，只看当前的，已归档的不占列表。
        archived: false,
        order: _order,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items.clear();
          _offset = 0;
        }
        // 相册里已经有表情和贴纸了，这里不再重复展示。
        _items.addAll(
          result.items.where(
            (e) => e.itemType != 'emoji' && e.itemType != 'sticker',
          ),
        );
        _lastBatchSize = result.items.length;
        _offset = start + result.items.length;
        _total = result.totalCount;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e;
      });
    }
  }

  bool get _hasMore {
    final total = _total;
    if (total != null) return _offset < total;
    // 没有总数时，只能靠上一页是不是满的来判断。
    return _lastBatchSize >= 60;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('库存'),
        actions: [
          if (_balance != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.toll_outlined,
                    size: 17,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_balance',
                    style: TextStyle(
                      fontSize: AppText.secondary,
                      fontWeight: FontWeight.w700,
                      color: context.appColors.ink(0.75),
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              _load(reset: true);
              _loadBalance();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            children: [
              _menu(
                label: '类型：${_labelOf(_types, _type)}',
                values: _types,
                selected: _type,
                onSelected: (v) {
                  setState(() => _type = v);
                  _load(reset: true);
                },
              ),
              _menu(
                label: '排序：${_labelOf(_orders, _order)}',
                values: _orders,
                selected: _order,
                onSelected: (v) {
                  setState(() => _order = v);
                  _load(reset: true);
                },
              ),
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_items.isEmpty) {
      // 这一页可能刚好全是表情/贴纸被过滤掉了，还能继续翻。
      if (_hasMore && _error == null) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Center(child: _loadMoreButton()),
          ],
        );
      }
      return _hint(
        icon: _error != null ? Icons.cloud_off : Icons.inventory_2_outlined,
        text: _error != null
            ? _error.toString().replaceFirst('Exception: ', '')
            : '这个分类下还没有物品',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _loadMoreButton(),
            );
          }
          return _ItemCard(item: _items[i]);
        },
      ),
    );
  }

  Widget _loadMoreButton() {
    return OutlinedButton(
      onPressed: _loadingMore ? null : () => _load(),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.appColors.accent,
        side: BorderSide(
          color: context.appColors.accent.withValues(alpha: 0.35),
        ),
        minimumSize: const Size.fromHeight(42),
      ),
      child: _loadingMore
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('加载更多'),
    );
  }

  Widget _hint({required IconData icon, required String text}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
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

  static String _labelOf(List<({String key, String label})> list, String key) {
    for (final e in list) {
      if (e.key == key) return e.label;
    }
    return list.first.label;
  }

  Widget _menu({
    required String label,
    required List<({String key, String label})> values,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      tooltip: label,
      color: context.appColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final v in values)
          PopupMenuItem(value: v.key, child: Text(v.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: context.appColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppText.caption,
                color: context.appColors.ink(0.65),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: context.appColors.ink(0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Center(child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(imageHeadersProvider);
    final image = item.imageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.appColors.ink(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: image == null || image.isEmpty
                  ? ColoredBox(
                      color: context.appColors.surfaceHigh,
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 22,
                        color: context.appColors.ink(0.3),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: image,
                      httpHeaders: headers,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          ColoredBox(color: context.appColors.surfaceHigh),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name.isEmpty ? '未命名物品' : item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.secondary,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.ink(0.9),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.isArchived ? '${item.typeLabel} · 已归档' : item.typeLabel,
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.accent,
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.label,
                      height: 1.45,
                      color: context.appColors.ink(0.42),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
