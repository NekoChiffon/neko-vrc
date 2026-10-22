/// VRChat 的 `location` 字段解析。
///
/// 该字段的形态（这是社区整理出来的约定，官方没有文档）：
///
/// ```
/// offline
/// private
/// traveling
/// wrld_1b3b0d2f-xxxx:12345~region(us)
/// wrld_1b3b0d2f-xxxx:12345~private(usr_xxx)~canRequestInvite
/// wrld_1b3b0d2f-xxxx:12345~friends(usr_xxx)
/// wrld_1b3b0d2f-xxxx:12345~hidden(usr_xxx)
/// wrld_1b3b0d2f-xxxx:12345~group(grp_xxx)~groupAccessType(public)
/// ```
///
/// `:` 前面是世界 ID，后面整体是实例 ID —— 调
/// `/instances/{worldId}:{instanceId}` 查实例人数时，实例 ID 要带着 `~` 后缀。
class ParsedLocation {
  const ParsedLocation({
    required this.raw,
    this.worldId,
    this.instanceId,
    this.instanceType = InstancePrivacy.unknown,
    this.ownerId,
    this.isTraveling = false,
    this.canRequestInvite = false,
  });

  final String raw;
  final String? worldId;
  final String? instanceId;
  final InstancePrivacy instanceType;

  /// private / friends / hidden 这类实例后面的所有者 ID。
  final String? ownerId;

  /// 好友正在传送途中，此时 location 还是旧值。
  final bool isTraveling;

  /// 带 `~canRequestInvite` 的 private 实例，也就是「邀请+」。
  final bool canRequestInvite;

  /// 界面上显示的实例类型文案。
  String get privacyLabel =>
      instanceType == InstancePrivacy.private && canRequestInvite
          ? '邀请+'
          : instanceType.label;

  bool get isOffline => raw.isEmpty || raw == 'offline';
  bool get isPrivate => raw == 'private';
  bool get hasWorld => worldId != null && worldId!.startsWith('wrld_');

  static const ParsedLocation offline = ParsedLocation(raw: 'offline');

  factory ParsedLocation.parse(String? location, {bool isTraveling = false}) {
    final raw = (location ?? '').trim();
    if (raw.isEmpty || raw == 'offline') {
      return const ParsedLocation(raw: 'offline');
    }
    if (raw == 'private') {
      return ParsedLocation(raw: raw, isTraveling: isTraveling);
    }
    if (raw == 'traveling') {
      return const ParsedLocation(raw: 'traveling', isTraveling: true);
    }

    final sep = raw.indexOf(':');
    if (sep <= 0) {
      return ParsedLocation(raw: raw, isTraveling: isTraveling);
    }

    final worldId = raw.substring(0, sep);
    final instanceId = raw.substring(sep + 1);
    final parts = instanceId.split('~');

    var type = InstancePrivacy.public;
    for (final p in parts.skip(1)) {
      if (p.startsWith('private(')) {
        // ~private(usr) = 仅限邀请
        type = InstancePrivacy.private;
      } else if (p.startsWith('friends(')) {
        // ~friends(usr) = 仅限好友
        type = InstancePrivacy.friends;
      } else if (p.startsWith('hidden(')) {
        // ~hidden(usr) 其实是「好友+」（Friends+），不是隐藏
        type = InstancePrivacy.friendsPlus;
      } else if (p.startsWith('group(')) {
        type = InstancePrivacy.group;
      }
      // 注意：**不要**处理 region(...) —— 之前这里会把已经解析出的
      // private/friends 覆盖回 public，导致所有房间都显示「公开」。
    }

    String? ownerId;
    final ownerMatch = RegExp(r'\((usr_[^)]+|grp_[^)]+)\)').firstMatch(instanceId);
    ownerId = ownerMatch?.group(1);

    return ParsedLocation(
      raw: raw,
      worldId: worldId,
      instanceId: instanceId,
      instanceType: type,
      ownerId: ownerId,
      isTraveling: isTraveling,
      canRequestInvite: instanceId.contains('~canRequestInvite'),
    );
  }
}

enum InstancePrivacy {
  public('公开'),
  friends('仅限好友'),
  friendsPlus('好友+'),
  private('仅限邀请'),
  hidden('隐藏'),
  group('群组'),
  unknown('未知');

  const InstancePrivacy(this.label);
  final String label;
}

/// 好友所在位置的展示文案（不含世界名，世界名由界面另行查表补上）。
String locationSuffixLabel(ParsedLocation loc) => loc.instanceType.label;
