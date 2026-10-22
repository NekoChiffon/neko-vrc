import 'dart:convert';

/// 一条通知的「宽容」模型。
///
/// 不用 SDK 的 `NotificationV2`：它把 `details` 声明成强类型对象，
/// 而 VRChat 实际返回的形态经常对不上（有时是 String、有时字段缺失），
/// `fromJson` 一抛异常整条通知就没了 —— 之前「好友申请收不到」就是这么发生的。
/// 这里只从原始 JSON 里挑展示需要的字段，缺什么就留空，绝不整条丢弃。
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.senderUserId,
    required this.senderUsername,
    required this.title,
    required this.message,
    required this.imageUrl,
    required this.createdAt,
    required this.seen,
    required this.responses,
    this.worldId = '',
    this.worldName = '',
    this.instanceId = '',
    this.inviteMessage = '',
    this.detailsRaw = const {},
  });

  final String id;

  /// `friendRequest` / `invite` / `requestInvite` / `boop` / `group.*` …
  final String type;
  final String senderUserId;
  final String senderUsername;
  final String title;
  final String message;
  final String? imageUrl;
  final DateTime createdAt;
  final bool seen;
  final List<AppNotificationResponse> responses;

  /// 邀请类通知带的房间信息（来自 details）。
  final String worldId;
  final String worldName;
  final String instanceId;
  final String inviteMessage;

  /// 原始 details（排查用）。
  final Map<String, dynamic> detailsRaw;

  /// 邀请（对方邀请你去他那）。`requestInvite` 是反过来的，不算。
  bool get isInvite => lowerType == 'invite';

  String get lowerType => type.toLowerCase();

  bool get isFriendRequest => lowerType.contains('friendrequest');
  bool get isBoop => lowerType.contains('boop');
  bool get isUnread => !seen;

  /// 从原始 JSON 解析。只有拿不到 id 时才算失败。
  static AppNotification? fromJson(Map<String, dynamic> json) {
    final id = _str(json['id']);
    if (id.isEmpty) return null;

    final type = _str(json['type']);

    // details 可能是 Map，也可能是 JSON 字符串（两个通知端点的格式不一致），
    // 不解码的话 worldId / worldName 全都拿不到 —— 表现就是「未知世界」。
    var detailsMap = <String, dynamic>{};
    final details = json['details'];
    if (details is Map) {
      detailsMap = Map<String, dynamic>.from(details);
    } else if (details is String && details.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map) detailsMap = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // 不是 JSON 就当没有
      }
    }

    // 标题：优先 message，其次类型自带文案，最后退回类型名。
    var title = _str(json['message']);
    if (title.isEmpty) title = _str(detailsMap['message']);
    if (title.isEmpty) title = _fallbackTitle(type);

    final responses = <AppNotificationResponse>[];
    final rawResponses = json['responses'];
    if (rawResponses is List) {
      for (final r in rawResponses) {
        if (r is! Map) continue;
        final t = _str(r['type']);
        if (t.isEmpty) continue;
        responses.add(
          AppNotificationResponse(type: t, data: _str(r['data'])),
        );
      }
    }

    var image = _str(json['imageUrl']);
    if (image.isEmpty) image = _str(detailsMap['imageUrl']);

    DateTime createdAt;
    final rawCreated = _str(json['createdAt']);
    createdAt = DateTime.tryParse(rawCreated)?.toLocal() ?? DateTime.now();

    // 有些端点的 details 里只给一个完整 location（`wrld_xxx:12345~region(jp)~...`），
    // 没有单独的 worldId / instanceId —— 从它拆出来。
    final location = _firstOf([
      detailsMap['location'],
      json['location'],
      detailsMap['instance'],
    ]);
    var locWorldId = '';
    var locInstanceId = '';
    if (location.contains(':')) {
      final sep = location.indexOf(':');
      locWorldId = location.substring(0, sep);
      locInstanceId = location.substring(sep + 1);
    } else if (location.isNotEmpty && !location.startsWith('wrld_')) {
      locInstanceId = location;
    }

    final resolvedWorldId = _firstOf([
      detailsMap['worldId'],
      json['worldId'],
      (detailsMap['invite'] is Map) ? (detailsMap['invite'] as Map)['worldId'] : null,
      locWorldId,
    ]);
    final resolvedInstanceId = _firstOf([
      detailsMap['instanceId'],
      json['instanceId'],
      (detailsMap['invite'] is Map) ? (detailsMap['invite'] as Map)['instanceId'] : null,
      locInstanceId,
    ]);

    // `details.worldId` 有时是 `wrld_xxx:12345~region(jp)~...`（带了实例部分），
    // 直接拿去请求 /worlds/{id} 会 404 —— 拆成干净的 worldId + instanceId。
    var finalWorldId = resolvedWorldId;
    var finalInstanceId = resolvedInstanceId;
    if (finalWorldId.contains(':')) {
      final sep = finalWorldId.indexOf(':');
      if (finalInstanceId.isEmpty) {
        finalInstanceId = finalWorldId.substring(sep + 1);
      }
      finalWorldId = finalWorldId.substring(0, sep);
    }

    return AppNotification(
      id: id,
      type: type.isEmpty ? 'unknown' : type,
      senderUserId: _str(json['senderUserId']),
      senderUsername: _str(json['senderUsername']),
      title: title,
      message: _str(json['message']),
      imageUrl: image.isEmpty ? null : image,
      createdAt: createdAt,
      seen: json['seen'] == true,
      responses: responses,
      worldId: finalWorldId,
      worldName: _firstOf([
        detailsMap['worldName'],
        json['worldName'],
        (detailsMap['invite'] is Map) ? (detailsMap['invite'] as Map)['worldName'] : null,
      ]),
      instanceId: finalInstanceId,
      inviteMessage: _firstOf([
        detailsMap['inviteMessage'],
        detailsMap['message'],
      ]),
      detailsRaw: detailsMap,
    );
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static String _firstOf(List<dynamic> values) {
    for (final v in values) {
      final s = _str(v);
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  static String _fallbackTitle(String type) {
    final t = type.toLowerCase();
    if (t.contains('friendrequest')) return '好友申请';
    if (t.contains('requestinvite')) return '请求加入';
    if (t.contains('invite')) return '邀请';
    if (t.contains('boop')) return '戳了戳你';
    if (t.contains('group.announcement')) return '群公告';
    if (t.contains('group')) return '群组通知';
    if (t.contains('message')) return '新消息';
    if (t.contains('votekick')) return '投票踢人';
    return type.isEmpty ? '通知' : type;
  }

  /// 挑「接受 / 拒绝」两个响应。VRChat 不写死值，只能按关键字猜。
  ({AppNotificationResponse? accept, AppNotificationResponse? reject})
      get acceptReject {
    AppNotificationResponse? find(List<String> keywords) {
      for (final r in responses) {
        final t = r.type.toLowerCase();
        if (keywords.any(t.contains)) return r;
      }
      return null;
    }

    return (
      accept: find(['accept', 'approve', 'yes']),
      reject: find(['reject', 'decline', 'ignore', 'deny', 'no']),
    );
  }

  @override
  String toString() => 'AppNotification($type, $id)';
}

class AppNotificationResponse {
  const AppNotificationResponse({required this.type, this.data = ''});

  final String type;
  final String data;
}

/// 调试用：统计解析失败的条数（release 包里 debugPrint 不输出，靠这个能在界面上看到）。
class NotificationParseStats {
  static int total = 0;
  static int failed = 0;
  static String? lastError;

  static void reset() {
    total = 0;
    failed = 0;
    lastError = null;
  }

  static void record({required bool ok, Object? error}) {
    total++;
    if (!ok) {
      failed++;
      lastError = error?.toString();
    }
  }
}
