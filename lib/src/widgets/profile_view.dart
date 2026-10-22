import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/friend_presence.dart';

import '../providers/cosmetics_provider.dart';
import '../providers/discovery_provider.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';
import '../pages/group_detail_page.dart';
import '../pages/favorites_page.dart';
import '../pages/avatar_list_page.dart';
import '../pages/edit_profile_page.dart';
import '../pages/group_list_page.dart';
import '../pages/world_list_page.dart';
import 'animated_network_image.dart';
import 'status_sheet.dart';

/// 个人资料页。
///
/// 结构对齐 VRChat 官网的主页：横幅 + 头像 + 状态气泡 + 名字徽章行 + 当前模型，
/// 然后是 ABOUT ME / BADGES / LANGUAGES / MY AVATAR / WORLDS / GROUPS。
/// 好友页和「我」页共用这一套，差异通过 [footer] 和 [selfMode] 注入。
class ProfileView extends ConsumerWidget {
  const ProfileView({
    super.key,
    required this.userId,
    this.presence,
    this.showBackButton = true,
    this.selfMode = false,
    this.footer = const [],
    this.onOpenSettings,
    this.onOpenMenu,
  });

  final String userId;

  /// 好友列表传进来的实时状态；自己的页面不传。
  final FriendPresence? presence;

  final bool showBackButton;

  /// 自己的资料页：按钮变成「改状态」，且不显示邀请相关的东西。
  final bool selfMode;

  /// 追加在最后的自定义区块。
  final List<Widget> footer;

  /// 自己的页面右上角多一个齿轮。
  final VoidCallback? onOpenSettings;

  /// 好友页右上角的「更多」菜单。
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userDetailProvider(userId));
    final detail = async.valueOrNull;
    final p = presence;

    // 群组走单独的接口：profile 里的 groups 字段经常整个是 null，
    // 只靠它会导致「我」页连 GROUPS 区块都不出现。
    final groupsAsync = ref.watch(userGroupsProvider(userId));
    final groups = groupsAsync.valueOrNull ?? const <LimitedUserGroups>[];

    // 装扮资源（头像框 / 资料特效 / 名字牌），一次拉齐。
    final cosmetics = ref.watch(cosmeticsProvider).valueOrNull;
    final bannerEffectUrl = cosmetics?.profileEffectUrl(detail?.profileEffectId);
    final nameplateUrl = cosmetics?.nameplateUrl(detail?.nameplateEffectId);
    final frameAssets = cosmetics?.iconFrameAssets(detail?.iconFrameId);
    final iconFrameUrl = frameAssets?.main ?? frameAssets?.base;

    final displayName = detail?.displayName.isNotEmpty == true
        ? detail!.displayName
        : (p?.displayName ?? '');
    // 官网的头像位置优先显示用户自己设的头像（VRC+ 自定义图），
    // 没设才退回当前模型的缩略图。之前直接用模型图，所以 VRC+ 用户的头像看起来是模型。
    final avatarUrl = detail?.userIcon ??
        detail?.iconUrl ??
        p?.avatarUrl ??
        detail?.avatarThumbnailUrl ??
        detail?.avatarImageUrl;

    // 自己的页面 profile 里经常不带 status，从登录态兜底，否则气泡连颜色圆点都没有。
    UserStatus? selfStatus;
    if (selfMode) {
      final auth = ref.watch(authProvider);
      if (auth is AuthSignedIn) selfStatus = auth.user.status;
    }
    final status = p?.status ?? detail?.status ?? selfStatus;
    final desc = (p?.statusDescription ?? '').trim().isNotEmpty
        ? p!.statusDescription.trim()
        : (detail?.statusDescription ?? '').trim();
    final bubbleText = desc.isNotEmpty ? desc : (status == null ? '' : userStatusLabel(status));
    final bubbleColor = status == null ? Colors.white54 : userStatusColor(status);

    final trustTags = detail?.trustTags ?? p?.tags ?? const <String>[];
    final trust = FriendPresence.trustRankFromTags(trustTags);
    // 盾的颜色跟着信任等级走：游客灰 / 萌新蓝 / 玩家绿 / 长期橙 / 资深紫 / 劣迹红
    final trustColor = trustColorFromTags(trustTags);

    const avatarSize = 78.0;
    const bannerHeight = 180.0;
    // 头像一半压在横幅上、一半露在下面。
    const overlap = avatarSize / 2;
    final topInset = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        CustomScrollView(
          // 内容不满屏时也能下拉刷新
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 横幅 + 头像放在同一个 Stack 里，否则头像会被横幅盖住。
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        height: bannerHeight,
                        child: _Banner(
                          url: detail?.bannerUrl,
                          color: detail?.bannerColor,
                          effectUrl: bannerEffectUrl,
                        ),
                      ),
                      Positioned(
                        left: 16,
                        top: bannerHeight - overlap,
                        child: _Avatar(
                          url: avatarUrl,
                          name: displayName,
                          frameUrl: iconFrameUrl,
                          frameFallback: frameAssets?.base,
                        ),
                      ),
                    ],
                  ),
                  // 头像露出来的那半个身位，右侧放状态气泡。
                  SizedBox(
                    height: overlap,
                    child: Row(
                      children: [
                        const SizedBox(width: 16 + avatarSize + 10),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _StatusBubble(
                              text: bubbleText,
                              color: bubbleColor,
                              // 自己的页面点气泡直接改状态。
                              onTap: selfMode ? () => showStatusSheet(context) : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 10),
                        _Identity(
                          displayName: displayName.isEmpty ? '加载中…' : displayName,
                          nameplateUrl: nameplateUrl,
                          hasVrcPlus: detail?.hasVrcPlus ?? false,
                          ageVerified: detail?.ageVerified ?? false,
                          trustRank: trust,
                          trustColor: trustColor,
                          pronouns: detail?.pronouns ?? '',
                          avatarName: detail?.avatarName,
                          onPrimary: selfMode
                              ? () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => EditProfilePage(userId: userId),
                                    ),
                                  )
                              : null,
                          primaryLabel: selfMode ? '编辑个人资料' : null,
                          primaryIcon: selfMode ? Icons.edit_outlined : null,
                        ),

                        // 自己页：账号级 presence 里的游戏端位置。
                        if (selfMode) ...[
                          const SizedBox(height: 10),
                          const _SelfLocationSection(),
                        ],

                        if (async.isLoading && detail == null) ...[
                          const SizedBox(height: 20),
                          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ],

                        if ((detail?.bio ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _Section(
                            title: 'ABOUT ME',
                            child: _ExpandableText(text: detail!.bio!.trim()),
                          ),
                        ],

                        if ((detail?.badges ?? const []).isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _Section(title: 'BADGES', child: _Badges(badges: detail!.badges)),
                        ],

                        if ((detail?.languages ?? const []).isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _Section(
                            title: 'LANGUAGES',
                            child: _Languages(items: detail!.languages),
                          ),
                        ],

                        if ((detail?.avatarImageUrl ?? '').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _Section(
                            title: 'MY AVATAR',
                            action: selfMode
                                ? GestureDetector(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => AvatarListPage(userId: userId),
                                      ),
                                    ),
                                    child: Text(
                                      '查看更多',
                                      style: TextStyle(
                                        fontSize: AppText.label,
                                        color: Colors.white.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  )
                                : null,
                            child: _MyAvatar(
                              imageUrl: detail!.avatarImageUrl!,
                              name: detail.avatarName,
                              author: detail.avatarAuthorName,
                              avatarId: detail.currentAvatarId,
                              onTap: selfMode
                                  ? () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => AvatarListPage(
                                            userId: userId,
                                          ),
                                        ),
                                      )
                                  : null,
                            ),
                          ),
                        ],

                        if (selfMode || (detail?.publicWorlds ?? const []).isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _Section(
                            title: 'WORLDS',
                            child: _Worlds(
                              uploaded: detail?.publicWorlds ?? const [],
                              ownerName: displayName,
                              showFavorites: selfMode,
                            ),
                          ),
                        ],

                        if (groups.isNotEmpty || (detail?.groupCount ?? 0) > 0) ...[
                          const SizedBox(height: 10),
                          _Section(
                            title: 'GROUPS',
                            child: _Groups(
                              groups: groups,
                              count: detail?.groupCount ?? groups.length,
                              userId: userId,
                            ),
                          ),
                        ],

                        ...footer,
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // 按钮固定在顶部，不随内容滚走。
        if (showBackButton)
          Positioned(
            top: topInset + 8,
            left: 10,
            child: _CircleButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        if (!selfMode) ...[
          if (onOpenMenu != null)
            Positioned(
              top: topInset + 8,
              right: 54,
              child: _CircleButton(icon: Icons.more_horiz, onTap: onOpenMenu!),
            ),
          Positioned(
            top: topInset + 8,
            right: 10,
            child: _CircleButton(
              icon: Icons.ios_share,
              onTap: () {
                final link = 'https://vrchat.com/home/user/$userId';
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制主页链接：$link')),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 顶部
// ---------------------------------------------------------------------------

class _Banner extends StatelessWidget {
  const _Banner({this.url, this.color, this.effectUrl});

  final String? url;
  final String? color;

  /// 资料特效（profileEffect）的底图，铺在横幅下面。
  final String? effectUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _parseColor(color) ?? const Color(0xFF1E2630),
            const Color(0xFF0B0F14),
          ],
        ),
      ),
    );

    return Consumer(
      builder: (context, ref, _) {
        final headers = ref.watch(imageHeadersProvider);
        final hasBanner = url != null && url!.isNotEmpty;

        return Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            if (hasBanner)
              CachedNetworkImage(
                imageUrl: url!,
                httpHeaders: headers,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            // 底部压暗，保证头像和状态气泡看得清。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x22000000), Color(0xCC0B0F14)],
                  stops: [0.3, 1.0],
                ),
              ),
            ),
            // 特效叠在最上层：它是带透明通道的边框图。放底层会被横幅盖住，
            // 靠降横幅透明度去补救只会让横幅发灰，边框依旧看不清。
            // 用 fill 而不是 cover：手机横幅比网页宽，cover 会把特效上下裁掉。
            if (effectUrl != null && effectUrl!.isNotEmpty)
              AnimatedNetworkImage(
                url: effectUrl!,
                headers: headers,
                fit: BoxFit.fill,
              ),
          ],
        );
      },
    );
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(cleaned.length <= 6 ? 0xFF000000 | value : value);
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 19, color: Colors.white),
        ),
      ),
    );
  }
}

class _Avatar extends ConsumerWidget {
  const _Avatar({
    required this.url,
    required this.name,
    this.frameUrl,
    this.frameFallback,
  });

  final String? url;
  final String name;

  /// 头像框（iconFrame）的动画图，叠在头像上面。
  final String? frameUrl;

  /// 动画解不出来时的静态兜底。
  final String? frameFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const size = 78.0;
    final headers = ref.watch(imageHeadersProvider);

    final inner = Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.canvas),
      child: ClipOval(
        child: SizedBox.expand(
          child: url == null || url!.isEmpty
              ? _fallback(name)
              : CachedNetworkImage(
                  imageUrl: url!,
                  httpHeaders: headers,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => _fallback(name),
                  errorWidget: (_, _, _) => _fallback(name),
                ),
        ),
      ),
    );

    // 只留一圈很淡的中性边；真正的框由官方的 iconFrame 图提供。
    final ring = Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.10),
      ),
      child: inner,
    );

    // 有官方头像框时，把框叠上去（框通常是比头像大一圈的透明图）。
    if (frameUrl == null || frameUrl!.isEmpty) return ring;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ring,
          // 和 VRCX 一样按 130% 放大叠上去，框的装饰通常画在头像外圈。
          Positioned(
            left: -size * 0.15,
            top: -size * 0.15,
            width: size * 1.3,
            height: size * 1.3,
            child: IgnorePointer(
              child: AnimatedNetworkImage(
                url: frameUrl!,
                fallbackUrl: frameFallback,
                headers: headers,
                fit: BoxFit.fill,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _fallback(String name) => Container(
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: [AppTheme.accent, AppTheme.accentAlt]),
    ),
    alignment: Alignment.center,
    child: Text(
      name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0B0F14),
      ),
    ),
  );
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble({required this.text, required this.color, this.onTap});

  final String text;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE61E2630),
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppText.caption, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return bubble;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppRadius.sheet), child: bubble);
  }
}

class _Identity extends ConsumerWidget {
  const _Identity({
    required this.displayName,
    required this.hasVrcPlus,
    required this.ageVerified,
    required this.trustRank,
    required this.trustColor,
    required this.pronouns,
    required this.avatarName,
    this.nameplateUrl,
    this.onPrimary,
    this.primaryLabel,
    this.primaryIcon,
  });

  final String displayName;
  final bool hasVrcPlus;
  final bool ageVerified;
  final String? trustRank;

  /// 信任等级的配色（盾的颜色）。
  final Color trustColor;
  final String pronouns;
  final String? avatarName;

  /// 名字牌（nameplateEffect）的图。拿不到时退回纯渐变底。
  final String? nameplateUrl;

  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final IconData? primaryIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNameplate = nameplateUrl != null && nameplateUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: Stack(
            children: [
              if (hasNameplate)
                Positioned.fill(
                  child: AnimatedNetworkImage(
                    url: nameplateUrl!,
                    headers: ref.watch(imageHeadersProvider),
                    fit: BoxFit.cover,
                  ),
                )
              else
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFFA78BFA).withValues(alpha: 0.22),
                          const Color(0xFF7DD3FC).withValues(alpha: 0.07),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (hasVrcPlus) ...[
                      const SizedBox(width: 8),
                      const _Pill(text: 'VRC+', color: Color(0xFFFBBF24)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (ageVerified)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_user_outlined, size: 13, color: Color(0xFF60A5FA)),
                  const SizedBox(width: 4),
                  Text(
                    '已验证 18+',
                    style: TextStyle(
                      fontSize: AppText.caption,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            if (trustRank != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 13, color: trustColor),
                  const SizedBox(width: 4),
                  Text(
                    trustRank!,
                    style: TextStyle(
                      fontSize: AppText.caption,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            if (pronouns.isNotEmpty)
              Text(
                pronouns,
                style: TextStyle(
                  fontSize: AppText.caption,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
        if (avatarName != null && avatarName!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_pin_circle_outlined, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    avatarName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.caption,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (onPrimary != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onPrimary,
            icon: Icon(primaryIcon ?? Icons.edit, size: 17),
            label: Text(primaryLabel ?? '编辑'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 区块
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});

  final String title;
  final Widget child;

  /// 标题右侧的小操作（比如「查看更多」）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xE6151B23),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: AppText.label,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppTheme.accent,
                ),
              ),
              const Spacer(),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppText.label, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: AppText.secondary, height: 1.65, color: Colors.white70);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 4,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : 4,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: style,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _expanded ? '收起' : '展开',
                    style: const TextStyle(
                      fontSize: AppText.caption,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Badges extends ConsumerWidget {
  const _Badges({required this.badges});

  final List<Badge> badges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(imageHeadersProvider);

    // 图片没到之前也要有东西占位，否则整块会是空白。
    Widget placeholder() => Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: const Icon(Icons.workspace_premium, size: 22, color: Colors.white24),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: badges.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final b = badges[i];
              return Tooltip(
                message: b.badgeName,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  child: b.badgeImageUrl.isEmpty
                      ? placeholder()
                      : CachedNetworkImage(
                          imageUrl: b.badgeImageUrl,
                          httpHeaders: headers,
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => placeholder(),
                          errorWidget: (_, _, _) => placeholder(),
                        ),
                ),
              );
            },
          ),
        ),
        if (badges.length > 4) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _showAll(context, headers),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white60,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              minimumSize: const Size.fromHeight(36),
              textStyle: const TextStyle(fontSize: AppText.caption),
            ),
            child: const Text('查看全部'),
          ),
        ],
      ],
    );
  }

  void _showAll(BuildContext context, Map<String, String> headers) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('全部徽章', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final b in badges)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.field),
                          child: b.badgeImageUrl.isEmpty
                              ? const SizedBox(width: 64, height: 64)
                              : CachedNetworkImage(
                                  imageUrl: b.badgeImageUrl,
                                  httpHeaders: headers,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          width: 72,
                          child: Text(
                            b.badgeName,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _Languages extends StatelessWidget {
  const _Languages({required this.items});

  final List<String> items;

  /// VRChat 存的是 ISO 639 代码（`zho`、`eng`…），直接显示出来没人看得懂。
  static const _names = {
    'zho': '中文',
    'chi': '中文',
    'cmn': '普通话',
    'yue': '粤语',
    'eng': 'English',
    'jpn': '日本語',
    'kor': '한국어',
    'fra': 'Français',
    'fre': 'Français',
    'deu': 'Deutsch',
    'ger': 'Deutsch',
    'spa': 'Español',
    'por': 'Português',
    'rus': 'Русский',
    'ita': 'Italiano',
    'nld': 'Nederlands',
    'dut': 'Nederlands',
    'pol': 'Polski',
    'swe': 'Svenska',
    'nor': 'Norsk',
    'dan': 'Dansk',
    'fin': 'Suomi',
    'ces': 'Čeština',
    'cze': 'Čeština',
    'hun': 'Magyar',
    'ron': 'Română',
    'rum': 'Română',
    'tur': 'Türkçe',
    'ukr': 'Українська',
    'ara': 'العربية',
    'hin': 'हिन्दी',
    'tha': 'ไทย',
    'vie': 'Tiếng Việt',
    'ind': 'Bahasa Indonesia',
    'msa': 'Bahasa Melayu',
    'tgl': 'Tagalog',
    'fil': 'Filipino',
    'heb': 'עברית',
    'ell': 'Ελληνικά',
    'gre': 'Ελληνικά',
    'sqi': 'Shqip',
  };

  static String label(String code) => _names[code.toLowerCase()] ?? code;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final l in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              label(l),
              style: TextStyle(
                fontSize: AppText.caption,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
      ],
    );
  }
}

class _MyAvatar extends ConsumerWidget {
  const _MyAvatar({
    required this.imageUrl,
    this.name,
    this.author,
    this.avatarId,
    this.onTap,
  });

  final String imageUrl;
  final String? name;
  final String? author;
  final String? avatarId;
  final VoidCallback? onTap;

  /// 模型名：profile 给了就用，没给就按 id 查一次，都拿不到才显示兜底文案。
  String _title(WidgetRef ref) {
    final given = (name ?? '').trim();
    if (given.isNotEmpty) return given;

    final id = avatarId;
    if (id == null || id.isEmpty) return '当前使用中的模型';

    return ref.watch(avatarNameProvider(id)).maybeWhen(
          data: (resolved) =>
              (resolved ?? '').trim().isEmpty ? '当前使用中的模型' : resolved!.trim(),
          orElse: () => '正在查模型名…',
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          httpHeaders: ref.watch(imageHeadersProvider),
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => const ColoredBox(color: AppTheme.surfaceHigh),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onTap != null)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: image,
          )
        else
          image,
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _title(ref),
                style: const TextStyle(
                  fontSize: AppText.secondary,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if ((author ?? '').isNotEmpty)
                TextSpan(
                  text: ' by ${author!}',
                  style: TextStyle(
                    fontSize: AppText.caption,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniWorld {
  const _MiniWorld({required this.id, required this.thumb});
  final String id;
  final String thumb;
}

/// WORLDS：横向滚动的卡片。第一张是「上传的公开世界」，后面每张是一个收藏夹。
class _Worlds extends ConsumerWidget {
  const _Worlds({
    required this.uploaded,
    required this.ownerName,
    this.showFavorites = false,
  });

  final List<LimitedWorld> uploaded;
  final String ownerName;

  /// 只有自己的资料页才带上收藏夹 —— VRChat 的收藏不对外公开，
  /// 看别人的页面时如果读 favoriteSectionsProvider，看到的会是「我」自己的收藏。
  final bool showFavorites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 自己的页面：改成上下排列的收藏夹卡片，「创建的世界」放在最前。
    if (showFavorites) return _selfFolders(context, ref);

    final cards = <Widget>[
      if (uploaded.isNotEmpty)
        _WorldCard(
          title: '$ownerName 的公开世界',
          worlds: uploaded
              .take(4)
              .map((w) => _MiniWorld(id: w.id, thumb: w.thumbnailImageUrl))
              .toList(),
          countText: '${uploaded.length}',
          onOpenAll: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WorldListPage(
                title: '$ownerName 的公开世界',
                worlds: uploaded,
              ),
            ),
          ),
        ),
    ];

    if (cards.isEmpty) {
      return Text(
        '还没有公开世界',
        style: TextStyle(fontSize: AppText.caption, color: Colors.white.withValues(alpha: 0.35)),
      );
    }

    return SizedBox(
      height: 208,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: cards,
      ),
    );
  }

  /// 「我」页面的世界卡片：创建的世界 + 每个收藏夹各一张，纵向排列。
  ///
  /// 参考图里右侧显示的是世界名，这里按需求换成收藏夹名字和数量，
  /// 点进去才是这个夹子里的世界列表。
  Widget _selfFolders(BuildContext context, WidgetRef ref) {
    final created =
        ref.watch(myCreatedWorldsProvider).valueOrNull ?? const <LimitedWorld>[];
    final sections = ref.watch(favoriteSectionsProvider);

    final cards = <Widget>[
      if (created.isNotEmpty)
        _WorldFolderCard(
          title: '创建的世界',
          coverUrl: created.first.thumbnailImageUrl,
          count: created.length,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WorldListPage(
                title: '创建的世界',
                worlds: created,
              ),
            ),
          ),
        ),
      for (final section in sections)
        _WorldFolderCard(
          title: section.title,
          coverUrl: section.worlds.first.thumbnailImageUrl,
          count: section.worlds.length,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FavoritesPage(groupKey: section.key),
            ),
          ),
        ),
    ];

    if (cards.isEmpty) {
      return Text(
        '还没有创建或收藏的世界',
        style: TextStyle(
          fontSize: AppText.caption,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cards,
    );
  }
}

/// 一张收藏夹 / 创建世界的入口卡片：左封面，右边名字 + 数量。
class _WorldFolderCard extends ConsumerWidget {
  const _WorldFolderCard({
    required this.title,
    required this.coverUrl,
    required this.count,
    required this.onTap,
  });

  final String title;
  final String coverUrl;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(imageHeadersProvider);
    final cover = coverUrl.isEmpty
        ? Container(
            color: const Color(0xFF1A212B),
            child: const Icon(Icons.public, size: 22, color: Colors.white24),
          )
        : CachedNetworkImage(
            imageUrl: coverUrl,
            httpHeaders: headers,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(
              color: const Color(0xFF1A212B),
              child: const Icon(Icons.public, size: 22, color: Colors.white24),
            ),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A212B),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 92,
          child: Row(
            children: [
              SizedBox(width: 120, height: 92, child: cover),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppText.body,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: AppText.caption,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldCard extends ConsumerWidget {
  const _WorldCard({
    required this.title,
    required this.worlds,
    required this.countText,
    this.onOpenAll,
  });

  final String title;
  final List<_MiniWorld> worlds;
  final String countText;
  final VoidCallback? onOpenAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(imageHeadersProvider);

    return InkWell(
      onTap: onOpenAll,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 130,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _tile(context, ref, headers, 0)),
                      const SizedBox(width: 3),
                      Expanded(child: _tile(context, ref, headers, 1)),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _tile(context, ref, headers, 2)),
                      const SizedBox(width: 3),
                      Expanded(child: _tile(context, ref, headers, 3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.link,
                size: 11,
                color: Colors.white.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 4),
              Text(
                countText,
                style: TextStyle(
                  fontSize: AppText.label,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    Map<String, String> headers,
    int index,
  ) {
    const radius = BorderRadius.all(Radius.circular(8));

    if (index >= worlds.length) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF1A212B), borderRadius: radius),
      );
    }

    final w = worlds[index];
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: w.thumb,
        httpHeaders: headers,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) =>
            const DecoratedBox(decoration: BoxDecoration(color: Color(0xFF1A212B))),
      ),
    );
  }
}

class _Groups extends ConsumerWidget {
  const _Groups({required this.groups, required this.count, required this.userId});

  final List<LimitedUserGroups> groups;
  final int count;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(imageHeadersProvider);
    // 自己「代表」的群组排在最前，和官网一致。
    final sorted = [...groups]..sort((a, b) {
      final ar = a.isRepresenting == true ? 0 : 1;
      final br = b.isRepresenting == true ? 0 : 1;
      return ar.compareTo(br);
    });
    final shown = sorted.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in shown)
          InkWell(
            onTap: () {
              final groupId = g.groupId ?? g.id;
              if (groupId == null || groupId.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GroupDetailPage(groupId: groupId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.field),
                    child: (g.iconUrl ?? '').isEmpty
                        ? Container(
                            width: 34,
                            height: 34,
                            color: AppTheme.surfaceHigh,
                            child: const Icon(Icons.groups, size: 16, color: Colors.white24),
                          )
                        : CachedNetworkImage(
                            imageUrl: g.iconUrl!,
                            httpHeaders: headers,
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => Container(
                              width: 34,
                              height: 34,
                              color: AppTheme.surfaceHigh,
                            ),
                          ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      g.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (g.isRepresenting == true)
                    const Icon(Icons.bookmark, size: 15, color: Color(0xFF60A5FA)),
                ],
              ),
            ),
          ),
        if (count > shown.length || shown.isEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => GroupListPage(userId: userId)),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white60,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              minimumSize: const Size.fromHeight(36),
              textStyle: const TextStyle(fontSize: AppText.caption),
            ),
            child: const Text('查看全部'),
          ),
        ],
      ],
    );
  }
}

/// 自己页的「所在世界」。
///
/// 数据源是 `CurrentUser.presence` —— 账号级 presence，会跟着游戏客户端走。
/// 注意 `presence.world` 里装的是 **worldId**（`wrld_xxx`），不是世界名，
/// 要拿 `worldDetailProvider` 换成名字 + 封面。
class _SelfLocationSection extends ConsumerWidget {
  const _SelfLocationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final me = auth is AuthSignedIn ? auth.user : null;
    final presence = me?.presence;

    final rawWorld = (presence?.world ?? '').trim();
    if (presence == null || rawWorld.isEmpty) return const SizedBox.shrink();

    final isWorldId = rawWorld.startsWith('wrld_');
    final world = isWorldId
        ? ref.watch(worldDetailProvider(rawWorld)).valueOrNull
        : null;

    final displayName = world?.name ??
        (isWorldId ? '读取中…' : rawWorld);

    final coverUrl = world == null
        ? ''
        : (world.thumbnailImageUrl.isNotEmpty
            ? world.thumbnailImageUrl
            : world.imageUrl);

    final instanceRaw = (presence.instance ?? '').trim();
    final hasWorldIdInInstance = instanceRaw.contains(':');
    final worldId = hasWorldIdInInstance
        ? instanceRaw.split(':').first
        : (isWorldId ? rawWorld : null);
    final instanceTail = hasWorldIdInInstance
        ? instanceRaw.substring(instanceRaw.indexOf(':') + 1)
        : instanceRaw;

    var region = '';
    final m = RegExp(r'region\(([^)]+)\)').firstMatch(instanceTail);
    if (m != null) region = m.group(1)!.toUpperCase();

    // VRChat 的 presence.instanceType 取值：public / friends / hidden / private / group
    var typeLabel = switch ((presence.instanceType ?? '').toLowerCase()) {
      'public' => '公开',
      'friends' => '仅限好友',
      'hidden' => '好友+',
      'private' => '仅限邀请',
      'group' => '群组',
      final other => other,
    };
    // private + canRequestInvite 其实是「邀请+」
    if (typeLabel == '仅限邀请' && instanceTail.contains('canRequestInvite')) {
      typeLabel = '邀请+';
    }

    final platformLabel = switch ((presence.platform ?? '').toLowerCase()) {
      'standalonewindows' => 'PC',
      'android' => '安卓',
      'ios' => 'iOS',
      'web' => 'Web',
      final other => other,
    };

    final meta = [
      if (typeLabel.isNotEmpty) typeLabel,
      if (platformLabel.isNotEmpty) platformLabel,
      if (region.isNotEmpty) region,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: SizedBox(
              width: 82,
              height: 58,
              child: coverUrl.isEmpty
                  ? ColoredBox(
                      color: AppTheme.surfaceHigh,
                      child: Center(
                        child: Icon(
                          Icons.public,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: coverUrl,
                      httpHeaders: ref.watch(imageHeadersProvider),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: AppTheme.surfaceHigh,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '所在世界',
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppText.secondary,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    style: TextStyle(
                      fontSize: AppText.label,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (worldId != null)
            IconButton(
              tooltip: '复制房间链接',
              onPressed: () {
                Clipboard.setData(ClipboardData(
                  text: buildLaunchLink(worldId, instanceTail),
                ));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制房间链接')),
                );
              },
              icon: Icon(
                Icons.copy_rounded,
                size: 15,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }
}
