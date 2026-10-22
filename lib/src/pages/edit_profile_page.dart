import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/friends_provider.dart';
import '../theme.dart';

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
                const SizedBox(height: 22),
                Text(
                  '提示：状态（欢迎加入 / 在线 / 忙碌 / 请勿打扰）不在这里改，'
                  '资料页上的「改状态」按钮才是。',
                  style: TextStyle(
                    fontSize: AppText.label,
                    height: 1.7,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ],
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

    if (!mounted) return;
    setState(() => _saving = false);

    final err = bioErr ?? aboutErr;
    if (err == null) {
      ref.invalidate(userDetailProvider(widget.userId));
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
          style: const TextStyle(
            fontSize: AppText.label,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppTheme.accent,
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
              color: Colors.white.withValues(alpha: 0.25),
            ),
            counterStyle: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
      ],
    );
  }
}
