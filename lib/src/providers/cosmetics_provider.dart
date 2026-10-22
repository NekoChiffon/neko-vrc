import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import 'friends_provider.dart';

/// VRChat 的装扮资源索引（头像框 / 资料特效 / 名字牌）。
///
/// 这些不是凭空画出来的：登录后请求 `cosmetics/index/*` 会拿到模板列表，
/// 每条的 `metadata.assets` 里带若干资源，`type` 分别是
/// `base`（静态底图）、`mainAnimation`（循环动画）、`introAnimation`（入场动画），
/// 每个都直接给 `url`。用户资料上的 `profileEffect` / `nameplateEffect` /
/// `iconFrame` 就是这个模板的 `id`，拿 id 回查即可。
class CosmeticsIndex {
  const CosmeticsIndex({
    this.profileEffects = const {},
    this.iconFrames = const {},
    this.nameplates = const {},
  });

  final Map<String, InventoryTemplate> profileEffects;
  final Map<String, InventoryTemplate> iconFrames;
  final Map<String, InventoryTemplate> nameplates;

  bool get isEmpty =>
      profileEffects.isEmpty && iconFrames.isEmpty && nameplates.isEmpty;

  /// 按优先级取某个模板里某一类资源的地址。
  static String? assetUrl(InventoryTemplate? template, List<String> types) {
    if (template == null) return null;
    final assets = template.metadata?.assets;
    if (assets == null || assets.isEmpty) return null;
    for (final type in types) {
      for (final asset in assets) {
        if (asset.type == type && asset.url.isNotEmpty) return asset.url;
      }
    }
    return null;
  }

  String? profileEffectUrl(String? id) {
    if (id == null || id.isEmpty) return null;
    return assetUrl(profileEffects[id], const ['mainAnimation', 'base']);
  }

  String? nameplateUrl(String? id) {
    if (id == null || id.isEmpty) return null;
    return assetUrl(nameplates[id], const ['mainAnimation', 'base']);
  }

  /// 头像框的两个地址：动画版和静态版。
  ///
  /// **不能**用 `template.imageUrl` —— 那是商品预览图，画了示例头像，
  /// 叠上去会把真实头像盖掉。只有 `metadata.assets` 是透明素材。
  ({String? main, String? base}) iconFrameAssets(String? id) {
    if (id == null || id.isEmpty) return (main: null, base: null);
    final frame = iconFrames[id];
    if (frame == null) return (main: null, base: null);

    final assets = frame.metadata?.assets ?? const <InventoryAsset>[];
    String? pick(String type) {
      for (final a in assets) {
        if (a.type == type && a.url.isNotEmpty) return a.url;
      }
      return null;
    }

    return (main: pick('mainAnimation'), base: pick('base'));
  }

  String? iconFrameUrl(String? id) {
    final assets = iconFrameAssets(id);
    return assets.main ?? assets.base;
  }
}

/// 三类装扮一次拉齐。单个类型失败不影响其它类型。
final cosmeticsProvider = FutureProvider<CosmeticsIndex>((ref) async {
  final api = ref.read(vrcClientProvider).api;

  Future<Map<String, InventoryTemplate>> load(String itemType) async {
    try {
      final resp = await api.rawApi.getInventoryApi().getCosmetics(itemType: itemType);
      final list = resp.data ?? const <InventoryTemplate>[];
      return {for (final item in list) item.id: item};
    } catch (e) {
      debugPrint('拉取 $itemType 失败（可能没有权限）: $e');
      return const <String, InventoryTemplate>{};
    }
  }

  final results = await Future.wait([
    load('profileEffect'),
    load('iconFrame'),
    load('nameplateEffect'),
  ]);

  return CosmeticsIndex(
    profileEffects: results[0],
    iconFrames: results[1],
    nameplates: results[2],
  );
});
