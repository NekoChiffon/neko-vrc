import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:dio/dio.dart' as dio;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album_file.dart';
import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';

/// 图库：相册 / 拍立得 / 头像 / 表情 / 贴纸（浏览版，暂不支持上传）。
///
/// 分类用横向滚动的胶囊（对齐 VRCX-0 的样式），切换不整页重建。
class AlbumPage extends ConsumerStatefulWidget {
  const AlbumPage({super.key});

  @override
  ConsumerState<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<AlbumPage> {
  static const _categories = [
    (tag: 'gallery', label: '相册', cap: 64),
    (tag: 'print', label: '拍立得', cap: 64),
    (tag: 'icon', label: '头像', cap: 64),
    (tag: 'emoji', label: '表情', cap: 32),
    (tag: 'sticker', label: '贴纸', cap: 32),
  ];

  String _selected = 'gallery';
  bool _uploading = false;
  final ValueNotifier<double> _progress = ValueNotifier(0);

  final _picker = ImagePicker();

  /// 选图（支持多选）→ 逐张上传 → 刷新当前分类。
  Future<void> _upload() async {
    if (_uploading) return;
    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 90,
        // VRChat 要求 <10MB、≥64x64，超过 2048 会被自动缩放 —— 我们提前缩好
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (picked.isEmpty) return; // 用户取消

      setState(() => _uploading = true);
      _progress.value = 0;
      final client = ref.read(vrcClientProvider);
      var done = 0;
      String? firstError;

      for (var i = 0; i < picked.length; i++) {
        final err = await client.uploadAlbumImage(
          path: picked[i].path,
          tag: _selected,
          onSendProgress: (sent, total) {
            if (total > 0) {
              // 进度按「已完成张数 + 当前这张的比例」折算成整体百分比。
              _progress.value = (i + sent / total) / picked.length;
            }
          },
        );
        if (err == null) {
          done++;
        } else {
          firstError ??= err;
        }
      }

      if (!mounted) return;
      ref.invalidate(albumFilesProvider(_selected));
      final message = picked.length == 1
          ? (firstError ?? '上传完成，缩略图可能要等几秒才生成')
          : '已上传 $done/${picked.length} 张'
              '${firstError == null ? '' : '（${firstError.split('\n').first}）'}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _categories.firstWhere((c) => c.tag == _selected);

    return Scaffold(
      appBar: AppBar(title: const Text('图库')),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploading ? null : _upload,
        backgroundColor: context.appColors.accent,
        child: _uploading
            ? ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (_, value, _) => Text(
                  '${(value * 100).round()}%',
                  style: TextStyle(
                    fontSize: AppText.caption,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              )
            : Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: 6,
              ),
              children: [
                for (final c in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CategoryChip(
                      label: c.label,
                      cap: c.cap,
                      selected: c.tag == _selected,
                      // 计数只在拉过该分类后显示（没点过的分类不发请求）
                      count: ref.watch(albumFilesProvider(c.tag)).valueOrNull?.length,
                      onTap: () => setState(() => _selected = c.tag),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _AlbumGrid(
                key: ValueKey(_selected),
                tag: _selected,
                round: selected.tag == 'icon',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类胶囊：选中的是 accent 底，右边带 `n/容量` 计数。
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.cap,
    required this.selected,
    required this.count,
    this.onTap,
  });

  final String label;
  final int cap;
  final bool selected;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? context.appColors.accent
        : context.appColors.ink(0.06);
    final fg = selected
        ? Theme.of(context).colorScheme.onPrimary
        : context.appColors.ink(0.65);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppText.secondary,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text(
                  '$count/$cap',
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Theme.of(
                            context,
                          ).colorScheme.onPrimary.withValues(alpha: 0.65)
                        : context.appColors.ink(0.32),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumGrid extends ConsumerWidget {
  const _AlbumGrid({super.key, required this.tag, this.round = false});

  final String tag;

  /// 头像用圆形展示。
  final bool round;

  int _columnsFor(String tag) => tag == 'icon' ? 3 : 2;

  double _aspectFor(String tag) =>
      tag == 'gallery' || tag == 'print' ? 16 / 9 : 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(imageHeadersProvider);
    final async = ref.watch(albumFilesProvider(tag));

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: _GridSkeleton(tag: tag),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '读不到相册：$e',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppText.caption,
              color: context.appColors.ink(0.4),
            ),
          ),
        ),
      ),
      data: (files) {
        if (files.isEmpty) {
          final diag = tag == 'print'
              ? ref.watch(printDiagProvider)
              : '';
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 40,
                  color: context.appColors.ink(0.14),
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  '这个分类还是空的',
                  style: TextStyle(
                    fontSize: AppText.caption,
                    color: context.appColors.ink(0.4),
                  ),
                ),
                if (diag.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      diag,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppText.label,
                        height: 1.5,
                        color: context.appColors.ink(0.3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(albumFilesProvider(tag)),
          child: GridView.builder(
            padding: const EdgeInsets.all(AppSpace.xs),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columnsFor(tag),
              childAspectRatio: _aspectFor(tag),
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: files.length,
            itemBuilder: (context, i) => _AlbumTile(
                  file: files[i],
                  index: i,
                  headers: headers,
                  round: round,
                ),
          ),
        );
      },
    );
  }
}

class _AlbumTile extends StatefulWidget {
  const _AlbumTile({
    required this.file,
    required this.index,
    required this.headers,
    required this.round,
  });

  final AlbumFile file;
  final int index;
  final Map<String, String> headers;
  final bool round;

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );

  late final Animation<double> _anim =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // 依次浮现：第 i 张延迟 i * 35ms，进页面像涟漪一样铺开
    Future.delayed(Duration(milliseconds: widget.index * 35), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = ColoredBox(
      color: context.appColors.surfaceHigh,
      child: CachedNetworkImage(
        imageUrl: widget.file.thumbUrl,
        httpHeaders: widget.headers,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 260),
        fadeOutDuration: const Duration(milliseconds: 120),
        errorWidget: (_, _, _) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 18,
            color: context.appColors.ink(0.2),
          ),
        ),
      ),
    );

    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(_anim),
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _AlbumViewer(file: widget.file),
            ),
          ),
          // Hero：点开全屏时图从网格位置飞过去
          child: Hero(
            tag: 'album-${widget.file.id}',
            child: widget.round
                ? ClipOval(child: image)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.field),
                    child: image,
                  ),
          ),
        ),
      ),
    );
  }
}

/// 全屏看图：双指缩放，可保存到手机 / 删除 / 复制链接。
class _AlbumViewer extends ConsumerWidget {
  const _AlbumViewer({required this.file});

  final AlbumFile file;

  Future<void> _saveToDevice(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resp = await ref.read(vrcClientProvider).api.rawApi.dio.get<List<int>>(
            file.fullUrl,
            options: dio.Options(responseType: dio.ResponseType.bytes),
          );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('下载失败')));
        return;
      }
      await Gal.putImageBytes(
        Uint8List.fromList(bytes),
        name: 'vrchat_${DateTime.now().millisecondsSinceEpoch}',
        album: 'VRChat',
      );
      messenger.showSnackBar(const SnackBar(content: Text('已保存到相册的 VRChat 分区')));
    } on GalException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：${e.type.message}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这张？'),
        content: Text(
          file.tag == 'print'
              ? '拍立得删除后无法恢复。'
              : '删除后 VRChat 里的这个分类会少一张，无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final err = await ref
        .read(vrcClientProvider)
        .deleteAlbumEntry(tag: file.tag, id: file.id);
    if (!context.mounted) return;
    if (err == null) {
      ref.invalidate(albumFilesProvider(file.tag));
      Navigator.of(context).pop(); // 删完回网格
    }
    messenger.showSnackBar(
      SnackBar(content: Text(err ?? '已删除')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          file.name.isEmpty ? '图片' : file.name,
          style: const TextStyle(fontSize: AppText.body),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '保存到手机相册',
            onPressed: () => _saveToDevice(context, ref),
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: '复制图片链接',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.fullUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制图片链接')),
              );
            },
            icon: const Icon(Icons.link),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Hero(
                  tag: 'album-${file.id}',
                  child: CachedNetworkImage(
                    imageUrl: file.fullUrl,
                    httpHeaders: ref.watch(imageHeadersProvider),
                    fit: BoxFit.contain,
                    fadeInDuration: const Duration(milliseconds: 240),
                    placeholder: (_, _) => const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (_, _, _) => Text(
                      '图片加载失败',
                      style: TextStyle(
                        color: context.appColors.ink(0.4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 拍立得：底部渐变上叠拍摄信息
          if (file.worldName.isNotEmpty || file.location.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, 10, AppSpace.lg, AppSpace.xl,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (file.worldName.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.public_outlined,
                            size: 14,
                            color: context.appColors.ink(0.55),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              file.worldName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppText.secondary,
                                fontWeight: FontWeight.w600,
                                color: context.appColors.ink(0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (file.location.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        file.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.label,
                          color: context.appColors.ink(0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: tag == 'icon' ? 3 : 2,
        childAspectRatio:
            tag == 'gallery' || tag == 'print' ? 16 / 9 : 1,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: tag == 'icon' ? 9 : 6,
      itemBuilder: (_, _) => const SkeletonBox(
        height: double.infinity,
        radius: BorderRadius.all(Radius.circular(AppRadius.field)),
      ),
    );
  }
}
