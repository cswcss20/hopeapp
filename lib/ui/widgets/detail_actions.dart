import 'package:flutter/material.dart';

import '../../models.dart';
import '../../zh_script.dart';
import '../app_scope.dart';
import 'focus_ring.dart';

/// 詳情頁自訂動作掣（manifest detailActions 申報）：按申報逐個
/// 出掣，撳後呼叫模組 detailAction(id, drama)，回 {ok, message}
/// 彈 snackbar。冇申報時唔渲染任何嘢。
class DetailActionPills extends StatelessWidget {
  const DetailActionPills({
    super.key,
    required this.drama,
    this.height = 40,
    this.radius,
  });

  final Drama drama;
  final double height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final actions = SourceSite.byId(drama.source).detailActions;
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final action in actions)
          _DetailActionPill(
            action: action,
            drama: drama,
            height: height,
            radius: radius,
          ),
      ],
    );
  }
}

class _DetailActionPill extends StatefulWidget {
  const _DetailActionPill({
    required this.action,
    required this.drama,
    required this.height,
    this.radius,
  });

  final ModuleDetailAction action;
  final Drama drama;
  final double height;
  final double? radius;

  @override
  State<_DetailActionPill> createState() => _DetailActionPillState();
}

class _DetailActionPillState extends State<_DetailActionPill> {
  var _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await AppScope.of(context).repository.detailAction(
        widget.drama.source,
        widget.action.id,
        widget.drama,
      );
      if (!mounted) return;
      final message = result['message'] as String? ?? '';
      final ok = result['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh(message.isNotEmpty ? message : (ok ? '已完成' : '操作失敗')),
          ),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final height = widget.height;
    final corner = widget.radius ?? height / 2;
    return FocusRing(
      radius: corner,
      child: FilledButton.tonal(
        onPressed: _busy ? null : _run,
        style: FilledButton.styleFrom(
          minimumSize: Size(0, height),
          padding: EdgeInsets.symmetric(horizontal: height * 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(corner),
          ),
          textStyle: TextStyle(
            fontSize: height >= 44 ? 15 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(zh(widget.action.label)),
      ),
    );
  }
}
