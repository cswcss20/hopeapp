import 'package:flutter/material.dart';

import '../../core_bridge.dart';
import '../../library_login.dart';
import '../../models.dart';
import '../../zh_script.dart';
import '../app_scope.dart';
import '../widgets/focus_ring.dart';
import '../widgets/form_text_field.dart';

/// 泛用表格登入（模組 manifest auth type='form'）：按申報欄位
/// 生成表格，值經 sourceAccount(source, 'login', {fieldId: value})
/// 交模組；狀態經 sourceAccount(source, '', {}) 攞
/// {loggedIn, name}，退出經 'logout'。泛用於任何申報此登入方式
/// 的模組，唔綁死個別站源。
Future<Map<String, dynamic>?> showModuleFormLogin(
  BuildContext context,
  String source,
) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ModuleFormLoginDialog(source: source),
);
class ModuleFormLoginButton extends StatefulWidget {
  const ModuleFormLoginButton({
    super.key,
    required this.source,
    required this.admin,
    this.style,
    this.onSaved,
  });

  final String source;
  final bool admin;
  final ButtonStyle? style;
  final VoidCallback? onSaved;

  @override
  State<ModuleFormLoginButton> createState() => _ModuleFormLoginButtonState();
}

class _ModuleFormLoginButtonState extends State<ModuleFormLoginButton> {
  Map<String, dynamic>? _status;
  var _busy = false;

  AppRepository get _repository => AppScope.of(context).repository;

  bool get _loggedIn => _status?['loggedIn'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final status = await _repository.sourceAccount(widget.source, '', {});
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _status = const {});
    }
  }

  Future<void> _login() async {
    final status = await showModuleFormLogin(context, widget.source);
    if (status != null && mounted) {
      setState(() => _status = status);
      LibraryLogin.invalidate(widget.source);
      widget.onSaved?.call();
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      final status = await _repository.sourceAccount(
        widget.source,
        'logout',
        {},
      );
      LibraryLogin.invalidate(widget.source);
      if (mounted) setState(() => _status = status);
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$failure')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle() {
    if (_status == null || _busy) return;
    _loggedIn ? _logout() : _login();
  }

  @override
  Widget build(BuildContext context) {
    final name = _status?['name'] as String? ?? '';
    final label = _loggedIn
        ? (name.isNotEmpty ? '${zh('退出')} · $name' : zh('退出登录'))
        : zh('登录');
    return FocusRing(
      radius: 20,
      child: FilledButton.tonalIcon(
        style: widget.style,
        onPressed: widget.admin && _status != null && !_busy ? _toggle : null,
        icon: Icon(_loggedIn ? Icons.logout_rounded : Icons.login_rounded),
        label: Text(label),
      ),
    );
  }
}

class _ModuleFormLoginDialog extends StatefulWidget {
  const _ModuleFormLoginDialog({required this.source});

  final String source;

  @override
  State<_ModuleFormLoginDialog> createState() => _ModuleFormLoginDialogState();
}

class _ModuleFormLoginDialogState extends State<_ModuleFormLoginDialog> {
  final _controllers = <String, TextEditingController>{};
  var _busy = false;
  String? _error;

  AppRepository get _repository => AppScope.of(context).repository;

  List<ModuleAuthField> get _fields =>
      SourceSite.byId(widget.source).effectiveAuth?.fields ?? const [];

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      _controllers[field.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final payload = <String, dynamic>{};
    for (final field in _fields) {
      final value = _controllers[field.id]?.text.trim() ?? '';
      if (field.required && value.isEmpty) {
        setState(() => _error = zh('请填写${field.label}'));
        return;
      }
      payload[field.id] = value;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await _repository.sourceAccount(
        widget.source,
        'login',
        payload,
      );
      if (mounted) Navigator.pop(context, status);
    } catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$failure';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = SourceSite.byId(widget.source);
    return AlertDialog(
      title: Text(zh('登录 ${site.name}')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            for (final (index, field) in _fields.indexed)
              FormTextField(
                controller: _controllers[field.id]!,
                autofocus: index == 0,
                obscure: field.isSecret,
                maxLength: 256,
                decoration: InputDecoration(
                  labelText: zh(field.label),
                  hintText: field.hint.isEmpty ? null : zh(field.hint),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(zh('取消')),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(zh('登录')),
        ),
      ],
    );
  }
}
