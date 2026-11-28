import 'package:flutter/material.dart';

import '../../local_store.dart';
import '../../models.dart';
import '../../zh_script.dart';
import '../app_scope.dart';
import '../settings/settings_rows.dart';
import '../widgets/focus_ring.dart';
import '../widgets/form_text_field.dart';

/// 泛用模組設定頁（manifest settings 申報）：按申報逐項出
/// text/toggle/select 控件，值按站源存入 LocalStore（入備份），
/// 每次改動同步入核心供模組經 host.settings() 讀取。
class ModuleSettingsButton extends StatelessWidget {
  const ModuleSettingsButton({
    super.key,
    required this.source,
    required this.store,
    this.style,
  });

  final String source;
  final LocalStore store;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      radius: 20,
      child: FilledButton.tonalIcon(
        style: style,
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ModuleSettingsPage(source: source, store: store),
          ),
        ),
        icon: const Icon(Icons.tune_rounded),
        label: Text(zh('设置')),
      ),
    );
  }
}

class ModuleSettingsPage extends StatefulWidget {
  const ModuleSettingsPage({super.key, required this.source, required this.store});

  final String source;
  final LocalStore store;

  @override
  State<ModuleSettingsPage> createState() => _ModuleSettingsPageState();
}

class _ModuleSettingsPageState extends State<ModuleSettingsPage> {
  LocalStore get _store => widget.store;

  List<ModuleSetting> get _settings =>
      SourceSite.byId(widget.source).settings;

  Object? _value(ModuleSetting setting) =>
      _store.moduleSettingValues(widget.source)[setting.id] ??
      setting.defaultValue;

  Future<void> _save(ModuleSetting setting, Object? value) async {
    await _store.setModuleSetting(widget.source, setting.id, value);
    await AppScope.of(context).repository.syncModuleSettings(
      _store.moduleSettingsMap,
    );
    if (mounted) setState(() {});
  }

  Future<void> _editText(ModuleSetting setting) async {
    final current = _value(setting)?.toString() ?? '';
    final controller = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(zh(setting.label)),
        content: FormTextField(
          controller: controller,
          autofocus: true,
          maxLength: 512,
          decoration: InputDecoration(
            hintText: setting.defaultValue?.toString() ?? '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(zh('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(zh('保存')),
          ),
        ],
      ),
    );
    if (saved != null) {
      await saveSetting(context, () => _save(setting, saved));
    }
  }

  Widget _tile(ModuleSetting setting) {
    final value = _value(setting);
    if (setting.isToggle) {
      return SwitchTile(
        title: setting.label,
        value: value == true,
        onChanged: (next) => saveSetting(context, () => _save(setting, next)),
      );
    }
    if (setting.isSelect) {
      final selected = value?.toString();
      return ValueTile<String>(
        title: setting.label,
        options: {for (final option in setting.options) option.id: option.name},
        value: setting.options.any((option) => option.id == selected)
            ? selected
            : null,
        onChanged: (next) {
          if (next != null) {
            saveSetting(context, () => _save(setting, next));
          }
        },
      );
    }
    return TileFocus(
      builder: (focusNode) => ListTile(
        focusNode: focusNode,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(zh(setting.label)),
        subtitle: Text(
          value?.toString().isNotEmpty == true
              ? value.toString()
              : zh('未设置'),
        ),
        trailing: const Icon(Icons.edit_rounded),
        onTap: () => _editText(setting),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final site = SourceSite.byId(widget.source);
    return Scaffold(
      appBar: AppBar(title: Text(zh('${site.name} 设置'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            SettingsCard(children: [for (final setting in _settings) _tile(setting)]),
          ],
        ),
      ),
    );
  }
}
