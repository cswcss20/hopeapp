import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core_bridge.dart';
import '../../library_login.dart';
import '../../models.dart';
import '../../webview_bridge.dart';
import '../app_scope.dart';
import '../widgets/focus_ring.dart';

/// 模組瀏覽器登入/驗證入口（manifest auth type='browser'）。
/// 用戶在此頁完成站方驗證或登入後，讀取 Cookie 與實際 UA，通過
/// 通用的 sourceAccount(source, 'setCookies', ...) 寫回模組狀態。
/// 登入頁地址、保存模式、登記橋接與否全部由模組申報決定
/// （SourceSite.effectiveAuth，含舊模組 fallback）：
/// saveMode 'auto'＝cf_clearance 出現即自動保存（Cloudflare
/// 驗證型），'manual'＝只手動保存（帳號登入型，cookie 要等
/// 登入後先擷取）；bridge=true 保存後登記 WebView 橋接抓頁。
const _fallbackUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Future<void> showBrowserAuth(
  BuildContext context,
  String source, {
  VoidCallback? onSaved,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => BrowserAuthView(source: source, onSaved: onSaved),
  ),
);

class BrowserAuthButton extends StatelessWidget {
  const BrowserAuthButton({
    super.key,
    required this.source,
    this.style,
    this.onSaved,
  });

  final String source;
  final ButtonStyle? style;
  final VoidCallback? onSaved;

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      radius: 20,
      child: FilledButton.tonalIcon(
        style: style,
        onPressed: () => showBrowserAuth(context, source, onSaved: onSaved),
        icon: const Icon(Icons.public_rounded),
        label: const Text('浏览器验证'),
      ),
    );
  }
}

class BrowserAuthView extends StatefulWidget {
  const BrowserAuthView({super.key, required this.source, this.onSaved});

  final String source;
  final VoidCallback? onSaved;

  @override
  State<BrowserAuthView> createState() => _BrowserAuthViewState();
}

class _BrowserAuthViewState extends State<BrowserAuthView> {
  InAppWebViewController? _controller;
  Timer? _poll;
  bool _busy = false;
  bool _saved = false;
  late String _status;

  AppRepository get _repository => AppScope.of(context).repository;

  SourceSite get _site => SourceSite.byId(widget.source);

  /// 生效的登入申報（冇申報行舊模組 fallback，見
  /// SourceSite.effectiveAuth）。入口只會喺 browser 型先出，
  /// 呢度 null 只係防禦。
  ModuleAuth? get _auth => _site.effectiveAuth;

  /// 自動保存模式（Cloudflare 驗證型）；false 係手動保存模式
  /// （帳號登入型）。
  bool get _autoSave => _auth?.autoSave ?? false;

  /// 登入/驗證頁地址（申報 url／舊 authUrl／baseUrl fallback）。
  String get _authUrl => _auth?.url ?? '';

  String get _title =>
      _autoSave ? '${_site.name} 浏览器验证' : '${_site.name} 登录验证';

  String get _initialStatus => _autoSave
      ? '请在下方页面完成 Cloudflare 验证；通过后会自动保存。'
            '若页面已正常打开却没有自动保存，可点「保存验证结果」手动保存。'
      : '请在下方页面登录账号；登录后点「保存验证结果」保存登录状态。';

  @override
  void initState() {
    super.initState();
    _status = _initialStatus;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _status = text);
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _capture(auto: true));
  }

  Future<void> _capture({required bool auto}) async {
    final controller = _controller;
    if (controller == null || _busy) return;
    // 手動保存模式（帳號登入）停用自動保存：cf_clearance 會喺用戶
    // 登入之前出現，自動保存會存低冇 session 嘅 cookie；必須等
    // 用戶登入後手動保存。
    if (auto && !_autoSave) return;
    // _saved 只擋自動保存；手動模式下手動保存可重複擷取更新
    // cookie。自動模式維持原有 guard，行為不變。
    if (_saved && (auto || _autoSave)) return;
    setState(() => _busy = true);
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(_authUrl),
      );
      final pairs = <String>[];
      for (final cookie in cookies) {
        final name = cookie.name.trim();
        if (name.isEmpty) continue;
        pairs.add('$name=${cookie.value}');
      }
      final cookieHeader = pairs.join('; ');
      final hasClearance = cookieHeader.contains('cf_clearance=');
      // 自动保存仍要求拿到 cf_clearance；手动保存则照样保存当前 Cookie 与
      // UA —— 有些站直接放行浏览器、不发 cf_clearance，之后靠桥接抓页即可。
      if (!hasClearance && auto) return;

      var ua = _fallbackUA;
      try {
        final jsUa = await controller.evaluateJavascript(
          source: 'navigator.userAgent',
        );
        var text = jsUa == null ? '' : jsUa.toString().trim();
        if (text.startsWith('"') && text.endsWith('"') && text.length > 2) {
          text = text.substring(1, text.length - 1);
        }
        if (text.isNotEmpty) ua = text;
      } catch (_) {
        try {
          final settings = await controller.getSettings();
          if (settings?.userAgent != null && settings!.userAgent!.isNotEmpty) {
            ua = settings.userAgent!;
          }
        } catch (_) {}
      }

      await _repository.sourceAccount(widget.source, 'setCookies', {
        'cookie': cookieHeader,
        'ua': ua,
      });
      LibraryLogin.invalidate(widget.source);
      // 申報 bridge=true 時同時登記 WebView 桥接：之后该域名的主机
      // 请求改走真浏览器抓页，直连被 Cloudflare 挡时也能拿到页面。
      // 登记失败不影响上面的保存。帳號登入來源唔申報 bridge：
      // 它們直連本身可用，登記會讓所有取頁改走串行的無頭 WebView
      // 桥接 fetch，慢很多；真撞 Cloudflare 時自愈驗證流程會再登記。
      var bridged = false;
      try {
        if (WebViewBridge.supported && (_auth?.bridge ?? false)) {
          await WebViewBridge.registerVerified(
            _repository,
            url: _authUrl,
            source: widget.source,
            cookies: cookieHeader,
            userAgent: ua,
          );
          bridged = true;
        }
      } catch (_) {}
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _saved = true;
          _status =
              '已保存 ${pairs.length} 个 Cookie'
              '${hasClearance ? '（含 cf_clearance）' : ''}和浏览器 UA'
              '${bridged ? '，并已启用浏览器桥接抓页' : ''}。'
              '可以返回模块正常使用了。';
        });
      }
      widget.onSaved?.call();
    } catch (error) {
      if (!auto) _setStatus('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await _repository.sourceAccount(widget.source, 'clearCookies', {});
      LibraryLogin.invalidate(widget.source);
      await CookieManager.instance().deleteCookies(url: WebUri(_authUrl));
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _saved = false;
          _status = '已清除保存的 Cookie 与 UA，可重新验证。';
        });
      }
    } catch (error) {
      _setStatus('清除失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            onPressed: _busy ? null : () => _capture(auto: false),
            tooltip: '立即保存',
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                _status,
                style: TextStyle(
                  color: _saved ? Colors.green : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Expanded(
              child: _authUrl.isEmpty
                  ? const Center(child: Text('该站源未申报名登录页地址'))
                  : InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(_authUrl)),
                      initialSettings: InAppWebViewSettings(
                        userAgent: _fallbackUA,
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        supportZoom: true,
                      ),
                      onWebViewCreated: (controller) {
                        _controller = controller;
                        _startPolling();
                      },
                      onLoadStop: (controller, url) {
                        _capture(auto: true);
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: FocusRing(
                      radius: 20,
                      child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _capture(auto: false),
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('保存验证结果'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FocusRing(
                      radius: 20,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _clear,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('清除'),
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
  }
}
