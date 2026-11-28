import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../captcha_account.dart';
import '../../core_bridge.dart';
import '../../models.dart';
import '../../zh_script.dart';
import '../app_scope.dart';
import '../widgets/focus_ring.dart';
import '../widgets/form_text_field.dart';

/// 滑塊驗證碼登入（模組 manifest auth type='captcha'）：先填
/// 帳號密碼，再完成滑塊拼圖驗證，經模組 account 的
/// captcha/login/logout 指令行。泛用於任何申報此登入方式的
/// 模組，唔綁死個別站源。
Future<CaptchaAccount?> showCaptchaLogin(
  BuildContext context,
  String source,
) => showDialog<CaptchaAccount>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CaptchaLoginDialog(
    repository: AppScope.of(context).repository,
    source: source,
  ),
);

bool captchaAccountAvailable(String source) {
  final site = SourceSite.byId(source);
  return site.available && site.account && (site.effectiveAuth?.isCaptcha ?? false);
}

class CaptchaAccountButton extends StatefulWidget {
  const CaptchaAccountButton({
    super.key,
    required this.source,
    required this.admin,
    this.style,
  });
  final String source;
  final bool admin;
  final ButtonStyle? style;

  @override
  State<CaptchaAccountButton> createState() => _CaptchaAccountButtonState();
}

class _CaptchaAccountButtonState extends State<CaptchaAccountButton> {
  CaptchaAccount? _account;
  var _busy = false;

  AppRepository get _repository => AppScope.of(context).repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final account = await _repository.captchaAccount(widget.source).catchError(
      (_) => const CaptchaAccount(),
    );
    if (mounted) setState(() => _account = account);
  }

  Future<void> _login() async {
    final account = await showCaptchaLogin(context, widget.source);
    if (account != null && mounted) setState(() => _account = account);
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      final account = await _repository.captchaLogout(widget.source);
      if (mounted) setState(() => _account = account);
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
    final account = _account;
    if (account == null || _busy) return;
    account.loggedIn ? _logout() : _login();
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _account?.loggedIn ?? false;
    return FocusRing(
      radius: 20,
      child: FilledButton.tonalIcon(
        style: widget.style,
        onPressed: widget.admin && _account != null && !_busy ? _toggle : null,
        icon: Icon(loggedIn ? Icons.logout_rounded : Icons.login_rounded),
        label: Text(zh(loggedIn ? '退出登录' : '登录')),
      ),
    );
  }
}

class _CaptchaLoginDialog extends StatefulWidget {
  const _CaptchaLoginDialog({required this.repository, required this.source});
  final AppRepository repository;
  final String source;

  @override
  State<_CaptchaLoginDialog> createState() => _CaptchaLoginDialogState();
}

class _CaptchaLoginDialogState extends State<_CaptchaLoginDialog> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  var _verifying = false;
  var _busy = false;
  CaptchaChallenge? _captcha;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _next() {
    if (_identifier.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = zh('请输入用户名或邮箱和密码'));
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _captcha = null);
    try {
      final captcha = await widget.repository.captchaChallenge(widget.source);
      if (mounted) setState(() => _captcha = captcha);
    } catch (failure) {
      if (mounted) setState(() => _error = '$failure');
    }
  }

  Future<void> _submit(CaptchaTrack track) async {
    final captcha = _captcha;
    if (captcha == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await widget.repository.captchaLogin(
        widget.source,
        identifier: _identifier.text.trim(),
        password: _password.text,
        captchaId: captcha.id,
        track: track,
      );
      if (mounted) Navigator.pop(context, account);
      return;
    } catch (failure) {
      if (!mounted) return;
      final message = '$failure';
      setState(() {
        _busy = false;
        _error = message;
        if (!message.contains('安全验证')) _verifying = false;
      });
      if (_verifying) await _reload();
    }
  }

  Future<void> _register() async {
    final site = SourceSite.byId(widget.source);
    final auth = site.effectiveAuth;
    final registerUrl = auth != null && auth.registerUrl.isNotEmpty
        ? auth.registerUrl
        : site.baseUrl;
    if (registerUrl.isEmpty) return;
    final opened = await launchUrl(
      Uri.parse(registerUrl),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: registerUrl));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(zh('无法打开浏览器，链接已复制'))));
    }
  }

  Widget _form() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      FormTextField(
        controller: _identifier,
        autofocus: true,
        maxLength: 128,
        onSubmitted: (_) => _passwordFocus.requestFocus(),
        decoration: InputDecoration(labelText: zh('用户名或邮箱')),
      ),
      FormTextField(
        controller: _password,
        focusNode: _passwordFocus,
        obscure: true,
        maxLength: 128,
        onSubmitted: (_) => _next(),
        decoration: InputDecoration(labelText: zh('密码'), errorText: _error),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FocusRing(
          radius: 20,
          child: TextButton(
            onPressed: _register,
            child: Text(zh('没有账号？在浏览器中注册')),
          ),
        ),
      ),
    ],
  );

  Widget _verification() {
    final captcha = _captcha;
    final error = _error;
    final television = AppScope.of(context).television;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        Text(zh(television ? '按左右方向键移动拼图块，对齐后按确定键' : '拖动下方滑块，让拼图块与缺口重合')),
        if (captcha == null && error == null)
          const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (captcha != null)
          _SliderCaptcha(
            key: ValueKey(captcha.id),
            captcha: captcha,
            enabled: !_busy,
            onTrack: _submit,
          ),
        if (error != null)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      zh(_verifying ? '安全验证' : '登录 ${SourceSite.byId(widget.source).name}'),
    ),
    content: SizedBox(
      width: 352,
      child: SingleChildScrollView(
        child: _verifying ? _verification() : _form(),
      ),
    ),
    actions: [
      FocusRing(
        radius: 20,
        child: TextButton(
          onPressed: _busy
              ? null
              : _verifying
              ? () => setState(() {
                  _verifying = false;
                  _error = null;
                })
              : () => Navigator.pop(context),
          child: Text(zh(_verifying ? '返回' : '取消')),
        ),
      ),
      if (_verifying)
        FocusRing(
          radius: 20,
          child: TextButton(
            onPressed: _busy ? null : _reload,
            child: Text(zh('换一张')),
          ),
        )
      else
        FocusRing(
          radius: 20,
          child: FilledButton(onPressed: _next, child: Text(zh('下一步'))),
        ),
    ],
  );
}

class _SliderCaptcha extends StatefulWidget {
  const _SliderCaptcha({
    super.key,
    required this.captcha,
    required this.enabled,
    required this.onTrack,
  });
  final CaptchaChallenge captcha;
  final bool enabled;
  final ValueChanged<CaptchaTrack> onTrack;

  @override
  State<_SliderCaptcha> createState() => _SliderCaptchaState();
}

class _SliderCaptchaState extends State<_SliderCaptcha> {
  static const _maxPoints = 4000;
  static const _keyStep = 4.0;
  final _points = <CaptchaPoint>[];
  final _focus = FocusNode();
  Offset? _origin;
  DateTime? _started;
  double _offset = 0;
  bool _keyboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AppScope.of(context).television) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _keyMove(double delta, double limit) {
    if (_origin == null) {
      _keyboard = true;
      _points.clear();
      _origin = Offset.zero;
      _started = DateTime.now();
      _record(Offset.zero, 'down', limit);
    } else if (!_keyboard) {
      return;
    }
    final x = (_offset + delta).clamp(0.0, limit);
    setState(() => _record(Offset(x, 0), 'move', limit));
  }

  KeyEventResult _keyEvent(
    KeyEvent event,
    Size background,
    Size template,
    double limit,
  ) {
    if (!widget.enabled || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _keyMove(
        key == LogicalKeyboardKey.arrowRight ? _keyStep : -_keyStep,
        limit,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (_origin != null && _keyboard) {
        _up(Offset(_offset, 0), background, template, limit);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _record(Offset position, String type, double limit) {
    final origin = _origin!;
    final delta = position - origin;
    final x = delta.dx.clamp(0.0, limit);
    _offset = x;
    if (_points.length < _maxPoints || type == 'up') {
      _points.add(
        CaptchaPoint(
          x.round(),
          delta.dy.round(),
          type,
          DateTime.now().difference(_started!).inMilliseconds,
        ),
      );
    }
  }

  void _down(PointerDownEvent event, double limit) {
    if (!widget.enabled || _origin != null) return;
    _keyboard = false;
    _points.clear();
    _origin = event.position;
    _started = DateTime.now();
    setState(() => _record(event.position, 'down', limit));
  }

  void _move(PointerMoveEvent event, double limit) {
    if (_origin == null || _keyboard) return;
    setState(() => _record(event.position, 'move', limit));
  }

  void _pointerUp(
    PointerUpEvent event,
    Size background,
    Size template,
    double limit,
  ) {
    if (_keyboard) return;
    _up(event.position, background, template, limit);
  }

  void _pointerCancel() {
    if (_origin == null || _keyboard) return;
    setState(() {
      _origin = null;
      _offset = 0;
    });
  }

  void _up(Offset position, Size background, Size template, double limit) {
    if (_origin == null) return;
    _record(position, 'up', limit);
    final started = _started!;
    _origin = null;
    if (_offset < 2 || _points.length < 2) {
      setState(() => _offset = 0);
      return;
    }
    setState(() {});
    widget.onTrack(
      CaptchaTrack(
        backgroundWidth: background.width.round(),
        backgroundHeight: background.height.round(),
        templateWidth: template.width.round(),
        templateHeight: template.height.round(),
        startTime: started.millisecondsSinceEpoch,
        stopTime: DateTime.now().millisecondsSinceEpoch,
        points: List.of(_points),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final captcha = widget.captcha;
      final width = math.min(300.0, constraints.maxWidth).floorToDouble();
      final scale = width / captcha.backgroundWidth;
      final background = Size(width, captcha.backgroundHeight * scale);
      final template = Size(
        captcha.templateWidth * scale,
        captcha.templateHeight * scale,
      );
      final limit = width - template.width;
      final colors = Theme.of(context).colorScheme;
      return FocusRing(
        radius: 12,
        scale: 1,
        child: Focus(
          focusNode: _focus,
          onKeyEvent: (_, event) =>
              _keyEvent(event, background, template, limit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.fromSize(
                  size: background,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.memory(
                          captcha.background,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                      Positioned(
                        left: _offset,
                        top: 0,
                        width: template.width,
                        height: template.height,
                        child: Image.memory(
                          captcha.template,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                      if (!widget.enabled)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x66000000),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: width,
                height: 44,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: _offset + template.width,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),
                    Positioned(
                      left: _offset,
                      top: 0,
                      bottom: 0,
                      width: template.width,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) => _down(event, limit),
                        onPointerMove: (event) => _move(event, limit),
                        onPointerUp: (event) =>
                            _pointerUp(event, background, template, limit),
                        onPointerCancel: (_) => _pointerCancel(),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.enabled
                                ? colors.primary
                                : colors.onSurface.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: colors.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
