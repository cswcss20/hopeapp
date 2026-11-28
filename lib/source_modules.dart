import 'models.dart';

class SourceModule {
  const SourceModule({
    required this.id,
    required this.name,
    this.version = '',
    this.description = '',
    this.hosts = const [],
    this.capabilities = const [],
    this.adult = false,
    this.coverAlign = '',
    this.authUrl = '',
    this.libraryKinds = const [],
    this.auth,
    this.settings = const [],
    this.detailActions = const [],
    this.browserFetch = false,
    this.verifyUrl = '',
    this.coverAspect = '',
    this.live = false,
    this.livePublic = false,
    this.baseUrl = '',
    this.installed = false,
    this.previous = '',
    this.token = '',
    this.error = '',
  });
  factory SourceModule.fromJson(Map<String, dynamic> json) => SourceModule(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '',
    description: json['description'] as String? ?? '',
    hosts: (json['hosts'] as List? ?? const []).whereType<String>().toList(),
    capabilities: (json['capabilities'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    adult: json['adult'] == true,
    coverAlign: json['coverAlign'] as String? ?? '',
    authUrl: json['authUrl'] as String? ?? '',
    libraryKinds: LibraryKind.listFromJson(json['libraryKinds']),
    auth: ModuleAuth.fromJsonOrNull(json['auth']),
    settings: ModuleSetting.listFromJson(json['settings']),
    detailActions: ModuleDetailAction.listFromJson(json['detailActions']),
    browserFetch: json['browserFetch'] == true,
    verifyUrl: json['verifyUrl'] as String? ?? '',
    coverAspect: switch ((json['coverAspect'] as String? ?? '').trim()) {
      'portrait' => 'portrait',
      'landscape' => 'landscape',
      _ => '',
    },
    live: json['live'] == true,
    livePublic: json['live'] == true && json['livePublic'] == true,
    baseUrl: json['baseUrl'] as String? ?? '',
    installed: json['installed'] == true,
    previous: json['previous'] as String? ?? '',
    token: json['token'] as String? ?? '',
    error: json['error'] as String? ?? '',
  );
  final String id;
  final String name;
  final String version;
  final String description;
  final List<String> hosts;
  final List<String> capabilities;
  final bool adult;
  final String coverAlign;
  final String authUrl;
  final List<LibraryKind> libraryKinds;
  final ModuleAuth? auth;
  final List<ModuleSetting> settings;
  final List<ModuleDetailAction> detailActions;
  final bool browserFetch;
  final String verifyUrl;
  final String coverAspect;
  // 模組申報自己係直播源（live）同屬公開平台（livePublic）；
  // 語意同 SourceSite.live/livePublic。
  final bool live;
  final bool livePublic;
  final String baseUrl;
  final bool installed;

  /// 實際生效的登入方式（同 SourceSite.effectiveAuth 同一規則）：
  /// 有 auth 申報用申報；冇申報行舊模組 fallback（authUrl→手動
  /// 瀏覽器登入；account 能力＋固定 hosts→自動保存＋橋接；
  /// hosts 含 '*' 嘅自架伺服器型唔行瀏覽器 fallback）。
  ModuleAuth? get effectiveAuth {
    final declared = auth;
    if (declared != null) return declared;
    if (authUrl.isNotEmpty) {
      return ModuleAuth(type: 'browser', url: authUrl);
    }
    if (capabilities.contains('account') &&
        baseUrl.isNotEmpty &&
        !hosts.contains('*')) {
      return ModuleAuth(
        type: 'browser',
        url: baseUrl,
        saveMode: 'auto',
        bridge: true,
      );
    }
    return null;
  }
  final String previous;
  final String token;
  final String error;
}

class ModuleIndexEntry {
  const ModuleIndexEntry({
    required this.id,
    required this.name,
    required this.version,
    this.description = '',
    this.repo = '',
    this.adult = false,
    this.bundled = false,
  });
  factory ModuleIndexEntry.fromJson(Map<String, dynamic> json) =>
      ModuleIndexEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        version: json['version'] as String? ?? '',
        description: json['description'] as String? ?? '',
        repo: json['repo'] as String? ?? '',
        adult: json['adult'] == true,
        bundled: json['bundled'] == true,
      );
  final String id;
  final String name;
  final String version;
  final String description;
  final String repo;
  final bool adult;
  final bool bundled;
}

class ModuleStore {
  const ModuleStore(this.entries, {this.warning = ''});
  final List<ModuleIndexEntry> entries;
  final String warning;
}

bool isNewerModuleVersion(String latest, String installed) {
  List<int>? parse(String version) {
    final parts = version.split('.').map(int.tryParse).toList();
    return parts.length == 3 && !parts.contains(null)
        ? parts.cast<int>()
        : null;
  }

  final next = parse(latest);
  final current = parse(installed);
  if (next == null) return false;
  if (current == null) return latest != installed;
  for (var index = 0; index < 3; index++) {
    if (next[index] != current[index]) return next[index] > current[index];
  }
  return false;
}

const moduleCapabilityNames = {
  'search': '搜索',
  'account': '账号登录',
  'suggestions': '搜索联想',
  'recommendations': '推荐',
  'danmaku': '弹幕',
  'devices': '设备注册',
  'rankings': '榜单',
  'seasons': '分季',
  'cover': '封面',
  'metadata': '补充信息',
  'catalogState': '目录状态',
  'library': '收藏同步',
};

String? missingSourceHint(Map<String, int> counts, String unit) {
  final total = counts.values.fold(0, (sum, count) => sum + count);
  return total == 0 ? null : '有 $total $unit来自未安装的站源，在 我的 › 模块 安装后恢复显示';
}
