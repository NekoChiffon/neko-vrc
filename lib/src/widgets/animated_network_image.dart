import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:native_animated_image/native_animated_image.dart';

/// 下载过的原始字节，避免同一次会话里反复拉同一张图。
final Map<String, Uint8List> _byteCache = <String, Uint8List>{};

/// 带鉴权头的图片 ImageProvider，可直接塞进 `DecorationImage`。
ImageProvider animatedImageProvider({
  required String url,
  required Map<String, String> headers,
}) {
  return NativeAnimatedImageProvider.fromBytesProvider(
    tag: url,
    loader: () async {
      // 内存 → 磁盘缓存（30 天，URL 不变就不再下载）→ 网络
      final cached = _byteCache[url];
      if (cached != null) return cached;

      try {
        final file = await DefaultCacheManager()
            .getSingleFile(url, headers: headers);
        final bytes = await file.readAsBytes();
        _byteCache[url] = bytes;
        return bytes;
      } catch (_) {
        // 磁盘缓存失败（比如没写权限）就退回直接下载
        final resp = await http.get(Uri.parse(url), headers: headers);
        if (resp.statusCode != 200) {
          throw Exception('图片下载失败（HTTP ${resp.statusCode}）');
        }
        _byteCache[url] = resp.bodyBytes;
        return resp.bodyBytes;
      }
    },
  );
}

/// 支持动图的网络图片。
///
/// Flutter 自带的 `Image` 只能解码 gif/webp，遇到 **APNG 只显示第一帧**
/// （VRChat 的头像框、名字牌、资料特效全是 APNG），所以这里换成
/// `native_animated_image` —— 用 Rust 解码，静态图也能正常走。
class AnimatedNetworkImage extends StatelessWidget {
  const AnimatedNetworkImage({
    super.key,
    required this.url,
    required this.headers,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.errorWidget,
    this.fallbackUrl,
  });

  final String url;
  final Map<String, String> headers;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final Widget? errorWidget;

  /// 动图解不出来时（比如格式是 webm）退回这张静态图。
  final String? fallbackUrl;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: animatedImageProvider(url: url, headers: headers),
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      errorBuilder: (_, _, _) {
        if (fallbackUrl != null && fallbackUrl!.isNotEmpty) {
          return Image.network(
            fallbackUrl!,
            headers: headers,
            fit: fit,
            width: width,
            height: height,
            alignment: alignment,
            errorBuilder: (_, _, _) => errorWidget ?? const SizedBox.shrink(),
          );
        }
        return errorWidget ?? const SizedBox.shrink();
      },
    );
  }
}
