import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/profile_backgrounds.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';
import 'cosmetics_picker_page.dart';

/// 编辑自己的资料：简介、状态语、代词。
///
/// 简介走 `/profile`，状态语和代词走 `/users` —— VRChat 把这两块分开管，
/// 所以保存时要打两次。
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final TextEditingController _bio;
  late final TextEditingController _statusText;
  late final TextEditingController _pronouns;
  bool _saving = false;
  bool _initialized = false;

  /// 资料背景：default / texture（预设）/ gradient（只读，不在 App 内编辑）。
  String _bgType = 'default';
  String _bgTextureId = '';
  bool _bgInitialized = false;
  bool _bgDirty = false;

  @override
  void initState() {
    super.initState();
    _bio = TextEditingController();
    _statusText = TextEditingController();
    _pronouns = TextEditingController();
  }

  @override
  void dispose() {
    _bio.dispose();
    _statusText.dispose();
    _pronouns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(userDetailProvider(widget.userId)).valueOrNull;

    // 第一次拿到数据时填充输入框（之后不再覆盖用户正在输入的内容）。
    if (!_initialized && detail != null) {
      _initialized = true;
      _bio.text = detail.bio ?? '';
      _statusText.text = detail.statusDescription ?? '';
      _pronouns.text = detail.pronouns;
    }

    final bg = ref.watch(profileBackgroundProvider(widget.userId)).valueOrNull;
    if (!_bgInitialized && bg != null) {
      _bgInitialized = true;
      if (bg.isGradient) {
        _bgType = 'gradient';
      } else if (bg.isTexture) {
        _bgType = 'texture';
        _bgTextureId = bg.textureId;
      } else if (bg.isPreset) {
        _bgType = 'preset';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: detail == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CosmeticsPickerPage(userId: widget.userId),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.appColors.accent,
                    side: BorderSide(
                      color: context.appColors.accent.withValues(alpha: 0.35),
                    ),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  label: const Text('个人资料装饰'),
                ),
                const SizedBox(height: 18),
                _Field(
                  label: 'ABOUT ME',
                  hint: '介绍一下自己，别人在资料页能看到',
                  controller: _bio,
                  maxLines: 8,
                  maxLength: 512,
                ),
                const SizedBox(height: 18),
                _Field(
                  label: '状态语',
                  hint: '显示在头像下面，比如「休息ing…」',
                  controller: _statusText,
                  maxLines: 2,
                  maxLength: 140,
                ),
                const SizedBox(height: 18),
                _Field(
                  label: '代词',
                  hint: '比如 她/他、TA，可以留空',
                  controller: _pronouns,
                  maxLines: 1,
                  maxLength: 32,
                ),
                const SizedBox(height: 26),
                Text(
                  '背景',
                  style: TextStyle(
                    fontSize: AppText.label,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: context.appColors.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _bgChip('默认', 'default'),
                    if (_bgType == 'texture') ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          profileBackgroundPreset(_bgTextureId)?.label ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppText.caption,
                            color: context.appColors.ink(0.45),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_bgType == 'gradient' || _bgType == 'preset') ...[
                  const SizedBox(height: 6),
                  Text(
                    '当前背景 App 内不支持编辑；选下面的预设或「默认」会覆盖它。',
                    style: TextStyle(
                      fontSize: AppText.label,
                      height: 1.5,
                      color: context.appColors.ink(0.3),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.7,
                      ),
                  itemCount: profileBackgroundPresets.length,
                  itemBuilder: (context, i) =>
                      _presetTile(profileBackgroundPresets[i]),
                ),
              ],
            ),
    );
  }

  Widget _bgChip(String label, String type) {
    final active = _bgType == type;
    return GestureDetector(
      onTap: () => setState(() {
        _bgType = type;
        _bgDirty = true;
        if (type == 'default') _bgTextureId = '';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? context.appColors.accent.withValues(alpha: 0.16)
              : context.appColors.ink(0.05),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: active
                ? context.appColors.accent.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppText.caption,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active
                ? context.appColors.accent
                : context.appColors.ink(0.5),
          ),
        ),
      ),
    );
  }

  Widget _presetTile(ProfileBackgroundPreset preset) {
    final selected =
        _bgType == 'texture' && _bgTextureId == preset.id;
    final radius = BorderRadius.circular(AppRadius.field);

    return GestureDetector(
      onTap: () => setState(() {
        _bgType = 'texture';
        _bgTextureId = preset.id;
        _bgDirty = true;
      }),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: preset.thumbnailUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  ColoredBox(color: context.appColors.surfaceHigh),
              errorWidget: (_, _, _) =>
                  ColoredBox(color: context.appColors.surfaceHigh),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.45, 1],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Text(
                preset.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            if (preset.isVrcPlus)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'VRC+',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2A1C00),
                    ),
                  ),
                ),
              ),
            if (selected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: context.appColors.accent,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.appColors.accent,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final client = ref.read(vrcClientProvider);

    final bioErr = await client.updateProfile(
      userId: widget.userId,
      bio: _bio.text.trim(),
    );
    final aboutErr = await client.updateAbout(
      userId: widget.userId,
      statusDescription: _statusText.text.trim(),
      pronouns: _pronouns.text.trim(),
    );

    // 只有真的动过背景才发，避免把 VRC+ 预设背景覆盖掉。
    String? bgErr;
    if (_bgDirty) {
      bgErr = await client.updateProfileBackground(
        userId: widget.userId,
        type: _bgType == 'texture' ? 'texture' : 'default',
        textureId: _bgType == 'texture' ? _bgTextureId : '',
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);

    final err = bioErr ?? aboutErr ?? bgErr;
    if (err == null) {
      ref.invalidate(userDetailProvider(widget.userId));
      ref.invalidate(profileBackgroundProvider(widget.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.maxLines,
    required this.maxLength,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppText.label,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: context.appColors.accent,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: maxLines > 3 ? 4 : null,
          maxLength: maxLength,
          style: const TextStyle(fontSize: AppText.secondary, height: 1.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: AppText.caption,
              color: context.appColors.ink(0.25),
            ),
            counterStyle: TextStyle(
              fontSize: 10,
              color: context.appColors.ink(0.2),
            ),
          ),
        ),
      ],
    );
  }
}
