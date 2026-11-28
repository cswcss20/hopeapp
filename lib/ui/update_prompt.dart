import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_device.dart';
import '../app_update.dart';
import '../core_bridge.dart';
import '../local_store.dart';
import 'app_scope.dart';
import 'modules/module_update_prompt.dart';
import 'widgets/focus_ring.dart';

var _checked = false;
const _manualCooldown = Duration(seconds: 30);
DateTime? _lastManualCheck;
AppUpdate? _lastManualUpdate;

enum _UpdateChoice { mute, skip, dismiss, download }

Future<void> runStartupChecks(
  BuildContext context,
  LocalStore store, {
  bool checkModules = true,
}) async {
  await _checkAppUpdateAtStartup(context, store);
  if (checkModules && context.mounted) {
    await checkModuleUpdatesAtStartup(context, store);
  }
}

Future<void> _checkAppUpdateAtStartup(
  BuildContext context,
  LocalStore store,
) async {
  if (_checked) return;
  _checked = true;
  final repository = AppScope.of(context).repository;
  final String current;
  final AppUpdate update;
  try {
    current = await currentAppVersion();
    if (!store.checkUpdates) return;
    final latest = await repository.checkUpdate(current);
    if (latest == null) return;
    update = latest;
  } catch (_) {
    return;
  }
  if (update.version == store.ignoredUpdate || !context.mounted) return;
  final choice = await _askUpdate(context, current, update, manual: false);
  switch (choice) {
    case _UpdateChoice.mute:
      await store.setCheckUpdates(false);
    case _UpdateChoice.skip:
      await store.setIgnoredUpdate(update.version);
    case _UpdateChoice.download:
      if (context.mounted) await _downloadAndInstall(context, update);
    case _UpdateChoice.dismiss || null:
      return;
  }
}

Future<void> checkUpdateManually(BuildContext context) async {
  final repository = AppScope.of(context).repository;
  final messenger = ScaffoldMessenger.of(context);
  final String current;
  final AppUpdate? update;
  try {
    current = await currentAppVersion();
    final last = _lastManualCheck;
    if (last != null && DateTime.now().difference(last) < _manualCooldown) {
      update = _lastManualUpdate;
    } else {
      update = await repository.checkUpdate(current);
      _lastManualCheck = DateTime.now();
      _lastManualUpdate = update;
    }
  } catch (failure) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure is AppFailure ? '检查更新失败：$failure' : '检查更新失败，请稍后再试',
        ),
      ),
    );
    return;
  }
  if (update == null) {
    messenger.showSnackBar(const SnackBar(content: Text('已是最新版本')));
    return;
  }
  if (!context.mounted) return;
  final choice = await _askUpdate(context, current, update, manual: true);
  if (choice == _UpdateChoice.download && context.mounted) {
    await _downloadAndInstall(context, update);
  }
}

Future<_UpdateChoice?> _askUpdate(
  BuildContext context,
  String current,
  AppUpdate update, {
  required bool manual,
}) {
  return showDialog<_UpdateChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('发现新版本 ${update.version}'),
      content: Text(
        manual ? '当前版本 $current。' : '当前版本 $current。选「不再提醒」后可在设置 › 关于中重新打开检查更新。',
      ),
      actions: [
        for (final (choice, label) in [
          if (!manual) (_UpdateChoice.mute, '不再提醒'),
          if (!manual) (_UpdateChoice.skip, '忽略此版本'),
          (_UpdateChoice.dismiss, '忽略'),
        ])
          FocusRing(
            radius: 20,
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, choice),
              child: Text(label),
            ),
          ),
        FocusRing(
          radius: 20,
          child: FilledButton(
            autofocus: true,
            onPressed: () =>
                Navigator.pop(dialogContext, _UpdateChoice.download),
            child: const Text('更新'),
          ),
        ),
      ],
    ),
  );
}

AppUpdateAsset? _platformAsset(AppUpdate update) {
  for (final asset in update.assets) {
    if (Platform.isWindows && asset.name.endsWith('-setup.exe')) return asset;
    if (Platform.isAndroid &&
        asset.name.contains('arm64-v8a') &&
        asset.name.endsWith('.apk')) {
      return asset;
    }
  }
  return null;
}

Future<void> _downloadAndInstall(BuildContext context, AppUpdate update) async {
  final asset = _platformAsset(update);
  if (asset == null) {
    // iOS and other platforms without an in-app installer asset fall back
    // to the release page.
    await _openRelease(context, update.url);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDownloadDialog(asset: asset),
  );
  if (result == null) {
    messenger.showSnackBar(const SnackBar(content: Text('已取消更新')));
    return;
  }
  if (result is _DownloadFailure) {
    messenger.showSnackBar(
      SnackBar(content: Text('更新失败：${result.failure}')),
    );
    return;
  }
  final file = result as File;
  try {
    if (Platform.isWindows) {
      await _installWindows(file);
    } else if (Platform.isAndroid) {
      await _installAndroid(file);
    }
  } catch (failure) {
    messenger.showSnackBar(SnackBar(content: Text('更新失败：$failure')));
  }
}

class _DownloadFailure {
  const _DownloadFailure(this.failure);
  final Object failure;
}

class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({required this.asset});
  final AppUpdateAsset asset;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  double? _progress;
  var _status = '正在下载…';
  HttpClientRequest? _request;
  var _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final file = await _download();
      if (!mounted) return;
      Navigator.pop(context, file);
    } catch (failure) {
      if (!mounted) return;
      Navigator.pop(context, _cancelled ? null : _DownloadFailure(failure));
    }
  }

  void _cancel() {
    _cancelled = true;
    _request?.abort();
  }

  Future<File> _download() async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}${widget.asset.name}',
    );
    final complete =
        widget.asset.size > 0 &&
        await file.exists() &&
        await file.length() == widget.asset.size;
    if (!complete) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(widget.asset.url));
        _request = request;
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw '下载失败：HTTP ${response.statusCode}';
        }
        final total = response.contentLength > 0
            ? response.contentLength
            : widget.asset.size;
        final sink = file.openWrite();
        var received = 0;
        try {
          await for (final chunk in response) {
            if (_cancelled) throw '已取消';
            sink.add(chunk);
            received += chunk.length;
            if (mounted) {
              setState(
                () => _progress = total > 0 ? received / total : null,
              );
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      } finally {
        client.close(force: true);
      }
      if (_cancelled) {
        await file.delete().catchError((_) => file);
        throw '已取消';
      }
    }
    if (widget.asset.size > 0 && await file.length() != widget.asset.size) {
      await file.delete().catchError((_) => file);
      throw '下载文件大小不符，请重试';
    }
    final digest = widget.asset.digest;
    if (digest.startsWith('sha256:')) {
      if (mounted) setState(() => _status = '正在验证…');
      final actual = await sha256.bind(file.openRead()).first;
      if (actual.toString() !=
          digest.substring('sha256:'.length).toLowerCase()) {
        await file.delete().catchError((_) => file);
        throw '下载文件验证失败，请重试';
      }
    }
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return AlertDialog(
      title: const Text('正在更新'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text(
            progress == null
                ? _status
                : '$_status ${(progress * 100).toStringAsFixed(0)}%',
          ),
        ],
      ),
      actions: [
        FocusRing(
          radius: 20,
          child: TextButton(onPressed: _cancel, child: const Text('取消')),
        ),
      ],
    );
  }
}

Future<void> _installWindows(File setup) async {
  // Wait briefly so this process has exited (the installer checks an app
  // mutex), then run the Inno Setup installer silently. The installer
  // relaunches the app afterwards (see windows/installer/setup.iss).
  // A hidden PowerShell does the waiting/launching so no console window
  // ever appears (the previous .bat + cmd approach flashed a CMD window).
  final setupPath = setup.path.replaceAll("'", "''");
  await Process.start('powershell', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-Command',
    "Start-Sleep -Seconds 2; Start-Process -FilePath '$setupPath' "
        "-ArgumentList '/SILENT','/SUPPRESSMSGBOXES','/NORESTART'",
  ], mode: ProcessStartMode.detached);
  exit(0);
}

Future<void> _installAndroid(File apk) async {
  try {
    await AppDevice.channel.invokeMethod('installApk', {'path': apk.path});
  } on PlatformException catch (failure) {
    if (failure.code == 'install_permission') {
      throw '请先允许本应用安装未知应用，然后再按更新';
    }
    rethrow;
  }
}

Future<void> _openRelease(BuildContext context, String url) async {
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (opened) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开浏览器，链接已复制')));
  }
}
