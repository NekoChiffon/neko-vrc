import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/friend_presence.dart';
import '../providers/friends_provider.dart';
import '../theme.dart';

/// 打开"改状态"的底部弹层。
Future<void> showStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _StatusSheet(),
  );
}

class _StatusSheet extends ConsumerStatefulWidget {
  const _StatusSheet();

  @override
  ConsumerState<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends ConsumerState<_StatusSheet> {
  late UserStatus _status;
  late final TextEditingController _desc;
  bool _saving = false;
  bool _showHistory = false;
  List<String> _history = const [];
  String? _error;

  // 离线不能手动选（那等于隐身），所以只给这四项。
  static const _options = [
    UserStatus.joinMe,
    UserStatus.active,
    UserStatus.askMe, // 橙，显示为「忙碌」
    UserStatus.busy, // 红，显示为「请勿打扰」
  ];

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    final user = auth is AuthSignedIn ? auth.user : null;
    _status = user?.status ?? UserStatus.active;
    _desc = TextEditingController(text: user?.statusDescription ?? '');
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await ref.read(authProvider.notifier).updateStatus(_status, _desc.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('状态已改为「${userStatusLabel(_status)}」')),
    );
  }

  void _toggleHistory() {
    if (_showHistory) {
      setState(() => _showHistory = false);
      return;
    }
    // 历史就在登录数据里（CurrentUser.statusHistory），不需要发请求。
    final auth = ref.read(authProvider);
    final user = auth is AuthSignedIn ? auth.user : null;
    setState(() {
      _showHistory = true;
      _history = user?.statusHistory ?? const <String>[];
    });
  }

  /// 历史状态语。点一条直接填回输入框。
  Widget _historyList() {
    final history = _history;
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Text(
          'VRChat 还没有记录过你的状态语',
          style: TextStyle(
            fontSize: AppText.label,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      constraints: const BoxConstraints(maxHeight: 210),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: history.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          indent: 14,
          endIndent: 14,
          color: Colors.white.withValues(alpha: 0.05),
        ),
        itemBuilder: (context, i) {
          final text = history[i];
          return InkWell(
            onTap: () {
              _desc.text = text;
              setState(() => _showHistory = false);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.secondary,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.north_west,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '我的状态',
                style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            ..._options.map((s) => _OptionRow(
                  status: s,
                  selected: _status == s,
                  onTap: () => setState(() => _status = s),
                )),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _desc,
                maxLength: 32,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saving ? null : _save(),
                decoration: InputDecoration(
                  hintText: '状态语，比如「挂机充电」',
                  counterStyle: const TextStyle(fontSize: 10, color: Colors.white24),
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.history,
                      size: 19,
                      color: _showHistory
                          ? AppTheme.accent
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                    // 历史是 VRChat 服务端记的（最近 10 条），每次展开都现拉。
                    onPressed: _toggleHistory,
                  ),
                ),
              ),
            ),
            if (_showHistory) _historyList(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: AppText.label, color: Color(0xFFFCA5A5)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final UserStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: userStatusColor(status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                userStatusLabel(status),
                style: TextStyle(
                  fontSize: AppText.body,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: Colors.white.withValues(alpha: selected ? 0.95 : 0.65),
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 17, color: AppTheme.accent),
          ],
        ),
      ),
    );
  }
}
