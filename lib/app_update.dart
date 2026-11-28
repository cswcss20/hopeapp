import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    this.digest = '',
  });

  factory AppUpdateAsset.fromJson(Map<String, dynamic> json) =>
      AppUpdateAsset(
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        digest: json['digest'] as String? ?? '',
      );

  final String name;
  final String url;
  final int size;
  final String digest;
}

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.url,
    this.assets = const [],
  });
  final String version;
  final String url;
  final List<AppUpdateAsset> assets;
}

int baseBuildNumber(String buildNumber) =>
    (int.tryParse(buildNumber) ?? 0) % 1000;

Future<String> currentAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${baseBuildNumber(info.buildNumber)}';
}
