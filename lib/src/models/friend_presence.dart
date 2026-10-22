import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../core/location_parser.dart';

/// 好友的「此刻状态」。
///
/// 同时来自两个通道：
/// * REST `/auth/user/friends` —— 冷启动时的全量快照
/// * Pipeline `friend-*` 事件 —— 之后的增量变化
///
/// 两边的字段不完全一致（例如 `friend-online` 只给 userId + location），
/// 所以这里用 copyWith 做合并，缺失的字段保持原值。
@immutable
class FriendPresence {
  const FriendPresence({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.status = UserStatus.offline,
    this.statusDescription = '',
    this.location = 'offline',
    this.travelingToLocation = '',
    this.platform = '',
    this.lastActivity,
    this.tags = const [],
    this.trustRank,
    this.locationSince,
    this.nameplateEffect,
    this.iconFrame,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final UserStatus status;
  final String statusDescription;

  /// 原始 location 字符串，例如 `wrld_xxx:12345~region(us)`。
  final String location;

  /// 传送途中的目标位置，空串表示没在传送。
  final String travelingToLocation;

  final String platform;
  final DateTime? lastActivity;
  final List<String> tags;

  /// 从 tags 推出来的信任等级（VRChat 用 tag 表示）。
  final String? trustRank;

  /// 进入当前实例的时间。VRChat 不提供这个值，是本地从 Pipeline 事件推出来的，
  /// 首次启动时等于启动时刻。
  final DateTime? locationSince;

  /// 名字牌装扮的 id（`nameplateEffect`），拿去 cosmetics 里回查图片。
  final String? nameplateEffect;

  /// 头像框装扮的 id（`iconFrame`）。
  final String? iconFrame;

  factory FriendPresence.fromFriend(LimitedUserFriend friend) {
    return FriendPresence(
      userId: friend.id,
      displayName: friend.displayName,
      // VRChat 对离线好友常常不给 currentAvatarImageUrl，退回用户头像（iconUrl）。
      avatarUrl: friend.currentAvatarImageUrl ?? friend.iconUrl,
      status: friend.status,
      statusDescription: friend.statusDescription,
      location: friend.location,
      platform: friend.platform,
      lastActivity: friend.lastActivity,
      tags: friend.tags,
      trustRank: _trustRankFromTags(friend.tags),
      nameplateEffect: friend.nameplateEffect,
      iconFrame: friend.iconFrame,
    );
  }

  /// 搜索结果只有很薄的一层字段，拿来当详情页的初始快照刚好够用。
  factory FriendPresence.fromSearch(LimitedUserSearch user) {
    return FriendPresence(
      userId: user.id,
      displayName: user.displayName,
      avatarUrl: user.iconUrl,
      status: user.status,
      statusDescription: user.statusDescription,
      platform: user.lastPlatform,
      tags: user.tags,
      trustRank: _trustRankFromTags(user.tags),
      nameplateEffect: user.nameplateEffect,
      iconFrame: user.iconFrame,
    );
  }

  /// 只有一个 id 时的空壳，等详情接口把资料填进来。
  factory FriendPresence.placeholder(String userId) =>
      FriendPresence(userId: userId, displayName: '');

  /// 注意：新版 `User` 模型里没有头像字段（头像只在 `LimitedUserFriend`
  /// 等列表模型上），所以这里刻意不填 avatarUrl —— 合并时由 copyWith 保留旧值。
  factory FriendPresence.fromUser(User user) {
    return FriendPresence(
      userId: user.id,
      displayName: user.displayName,
      status: user.status,
      statusDescription: user.statusDescription,
      location: user.location ?? 'offline',
      travelingToLocation: user.travelingToLocation ?? '',
      platform: user.platform ?? '',
      lastActivity: DateTime.tryParse(user.lastActivity),
      tags: user.tags,
      trustRank: _trustRankFromTags(user.tags),
      nameplateEffect: user.nameplateEffect,
    );
  }

  FriendPresence copyWith({
    String? displayName,
    String? avatarUrl,
    UserStatus? status,
    String? statusDescription,
    String? location,
    String? travelingToLocation,
    String? platform,
    DateTime? lastActivity,
    List<String>? tags,
    String? trustRank,
    DateTime? locationSince,
    String? nameplateEffect,
    String? iconFrame,
  }) {
    return FriendPresence(
      userId: userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      statusDescription: statusDescription ?? this.statusDescription,
      location: location ?? this.location,
      travelingToLocation: travelingToLocation ?? this.travelingToLocation,
      platform: platform ?? this.platform,
      lastActivity: lastActivity ?? this.lastActivity,
      tags: tags ?? this.tags,
      trustRank: trustRank ?? this.trustRank,
      locationSince: locationSince ?? this.locationSince,
      nameplateEffect: nameplateEffect ?? this.nameplateEffect,
      iconFrame: iconFrame ?? this.iconFrame,
    );
  }

  ParsedLocation get parsedLocation =>
      ParsedLocation.parse(location, isTraveling: travelingToLocation.isNotEmpty && travelingToLocation != 'offline');

  /// 信任等级对应的颜色，跟 VRChat 里的那几档一致。
  Color get trustColor => trustColorFromTags(tags);

  /// VRChat 的 VRC+ 订阅者 tag。
  bool get isSupporter => tags.contains('system_supporter');

  /// 注意：在线与否只看 status，不看 location。
  ///
  /// Web 客户端（浏览器版）的好友 status 是 active，但 location 往往不落在
  /// 任何世界里，早先把它俩绑在一起会把人误判成离线。
  bool get isOnline => status != UserStatus.offline;

  /// 在浏览器里玩的那批人（VRChat Web 客户端）。
  bool get isWebPlatform => platform.toLowerCase().contains('web');

  /// 在线且位置对好友可见（即能知道在哪个世界）。
  bool get hasVisibleWorld => isOnline && parsedLocation.hasWorld;

  /// 是否在私密/隐藏世界里（知道在线，但看不到具体房间）。
  bool get isInPrivateInstance =>
      isOnline && (parsedLocation.isPrivate || parsedLocation.instanceType == InstancePrivacy.hidden);

  /// 分组键：**同一个实例**的人聚到一起（同世界不同房间要分开）。
  /// Web 在线、私密、离线各自成组。
  String get groupKey {
    if (!isOnline) return '__offline__';
    final loc = parsedLocation;
    if (loc.hasWorld && loc.instanceId != null) {
      return '${loc.worldId}:${loc.instanceId}';
    }
    if (isWebPlatform) return '__web__';
    if (loc.isPrivate) return '__private__';
    return '__unknown__';
  }

  String get statusLabel => userStatusLabel(status);

  Color get statusColor => userStatusColor(status);

  /// VRChat 的信任等级是藏在 tags 里的。顺序有意义：劣迹优先于其他所有等级。
  static String? trustRankFromTags(List<String> tags) {
    const table = [
      ('system_trust_negative', '劣迹玩家'),
      ('system_trust_troll', '劣迹玩家'),
      ('system_flagged', '劣迹玩家'),
      ('system_trust_veteran', '资深玩家'),
      ('system_trust_trusted', '长期玩家'),
      ('system_trust_known', '玩家'),
      ('system_trust_basic', '萌新'),
      ('system_trust_visitor', '游客'),
    ];
    for (final (tag, label) in table) {
      if (tags.contains(tag)) return label;
    }
    return null;
  }

  static String? _trustRankFromTags(List<String> tags) => trustRankFromTags(tags);
}

/// 信任等级的颜色。官方那套：
/// 游客灰、新用户蓝、用户绿、已知用户橙、受信任用户紫，劣迹红。
Color trustColorFromTags(List<String> tags) {
  const table = [
    ('system_trust_negative', Color(0xFFF52D2D)),
    ('system_trust_troll', Color(0xFFF52D2D)),
    ('system_flagged', Color(0xFFF52D2D)),
    ('system_trust_veteran', Color(0xFF8143E6)),
    ('system_trust_trusted', Color(0xFFFF7B42)),
    ('system_trust_known', Color(0xFF2BCE5C)),
    ('system_trust_basic', Color(0xFF1778FF)),
    ('system_trust_visitor', Color(0xFFB2B2B2)),
  ];
  for (final (tag, color) in table) {
    if (tags.contains(tag)) return color;
  }
  return const Color(0xFFB2B2B2);
}

/// 状态的中文名。集中放一处，界面和状态选择器都用它。
String userStatusLabel(UserStatus status) => switch (status) {
  UserStatus.joinMe => '欢迎加入',
  UserStatus.active => '在线',
  // VRChat 的 Ask Me 是橙色、Busy 是红色。中文习惯里橙色对应「忙碌」，
  // 所以这两个的文案和色值都按颜色对齐，不按英文直译。
  UserStatus.askMe => '忙碌',
  UserStatus.busy => '请勿打扰',
  UserStatus.offline => '离线',
};

Color userStatusColor(UserStatus status) => switch (status) {
  UserStatus.active => const Color(0xFF4ADE80),
  UserStatus.joinMe => const Color(0xFF60A5FA),
  UserStatus.askMe => const Color(0xFFFB923C),
  UserStatus.busy => const Color(0xFFF87171),
  UserStatus.offline => const Color(0xFF6B7280),
};

/// 好友所在世界可以直接拼成 VRChat 的深链，粘到电脑端就能进。
///
/// 格式来自官网「Join」按钮：`vrchat://launch?id=<worldId>:<instanceId>`。
String buildLaunchLink(String worldId, String instanceId) =>
    'vrchat://launch?id=$worldId:$instanceId';
