import 'dart:convert';

/// 相册里的一张图（VRChat `File` 对象的精简版）。
///
/// 不用 SDK 的 `File` 模型：它的 `versions` 层级很深且字段强类型，
/// VRChat 返回偶尔缺字段会整条解析失败。这里只挑展示需要的几个值。
class AlbumFile {
  const AlbumFile({
    required this.id,
    required this.name,
    required this.thumbUrl,
    required this.fullUrl,
    required this.createdAt,
    required this.tag,
    this.worldName = '',
    this.location = '',
  });

  final String id;
  final String name;
  final String thumbUrl;
  final String fullUrl;
  final DateTime createdAt;
  final String tag;

  /// 拍立得的拍摄信息（Print 实体自带）。
  final String worldName;
  final String location;

  /// `file_xxx` / `icon` / `print`
  static AlbumFile? fromJson(Map<String, dynamic> json, String tag) {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty) return null;

    final versions = json['versions'];
    if (versions is! List || versions.isEmpty) return null;

    // 取版本号最大的那个（最新上传的）
    Map<dynamic, dynamic>? latest;
    var maxVersion = -1;
    for (final v in versions) {
      if (v is! Map) continue;
      final n = (v['version'] as num?)?.toInt() ?? 0;
      if (n >= maxVersion) {
        maxVersion = n;
        latest = v;
      }
    }
    final file = latest?['file'];
    if (file is! Map) return null;

    // 已删除的文件接口也会返回，但最新版本的 status 是 deleted；
    // 上传中断的是 uploading —— 这些都不该显示。
    final status = (latest?['status'] ?? '').toString();
    if (status != 'complete') return null;

    final fullUrl = (file['url'] ?? '').toString();
    if (fullUrl.isEmpty) return null;

    // 缩略图：子版本里有 /256 和 /512，优先 512
    var thumb = fullUrl;
    final subVersions = file['versions'];
    if (subVersions is List) {
      String? small;
      String? medium;
      for (final s in subVersions) {
        if (s is! Map) continue;
        final sf = s['file'];
        if (sf is! Map) continue;
        final url = (sf['url'] ?? '').toString();
        if (url.isEmpty) continue;
        if (url.endsWith('/256')) small = url;
        if (url.endsWith('/512')) medium = url;
      }
      thumb = medium ?? small ?? fullUrl;
    }

    DateTime createdAt;
    final rawCreated = (json['created_at'] ?? '').toString();
    createdAt = DateTime.tryParse(rawCreated)?.toLocal() ?? DateTime.now();

    return AlbumFile(
      id: id,
      name: (json['name'] ?? '').toString(),
      thumbUrl: thumb,
      fullUrl: fullUrl,
      createdAt: createdAt,
      tag: tag,
    );
  }

  /// 拍立得是独立实体（`GET /prints/user/{userId}`），结构和 File 完全不同：
  /// 图片 URL 直接在 `files.image`（VRCX 的 Gallery.vue 也是这么取的，无缩略图）。
  static AlbumFile? fromPrintJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty) return null;

    final filesField = decodeIfNeeded(json['files']);
    final fullUrl = filesField == null
        ? ''
        : (filesField['image'] ?? '').toString();
    if (fullUrl.isEmpty) return null;

    final name = _firstOf([json['printName'], json['title']]);
    final createdAt =
        DateTime.tryParse(_str2(json['timestamp']))?.toLocal() ?? DateTime.now();

    return AlbumFile(
      id: id,
      name: name,
      thumbUrl: fullUrl,
      fullUrl: fullUrl,
      createdAt: createdAt,
      tag: 'print',
    );
  }

  static String _str2(dynamic v) => v == null ? '' : v.toString();

  static String _firstOf(List<dynamic> values) {
    for (final v in values) {
      final s = _str2(v);
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  /// 有些端点的字段是 JSON 字符串，统一解码一下。
  static Map<String, dynamic>? decodeIfNeeded(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // 忽略
      }
    }
    return null;
  }
}
