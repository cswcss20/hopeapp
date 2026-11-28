import 'dart:convert';

import 'zh_script.dart';

const hongguoSourceId = 'hongguo';

bool validSourceId(String id) => RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(id);

/// 模組在 manifest 申報的一個帳號收藏種類（libraryKinds）：
/// id 是 libraryItems 的 kind 參數，name 是追劇頁子頁標籤，
/// style 是渲染方式（'cover' 標準封面卡格／'avatar' 圓形頭像格）。
/// id='favorites' 是協議約定的同步/寫入 kind（拉取存 site list＋
/// 詳情頁收藏掣 write-through 對象），其餘 kind 即時攞、不存檔。
class LibraryKind {
  const LibraryKind({required this.id, required this.name, this.style = 'cover'});

  factory LibraryKind.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final name = (json['name'] as String? ?? '').trim();
    return LibraryKind(
      id: id,
      name: name.isEmpty ? id : name,
      style: (json['style'] as String? ?? '').trim() == 'avatar'
          ? 'avatar'
          : 'cover',
    );
  }

  final String id;
  final String name;
  final String style;

  bool get isFavorites => id == 'favorites';
  bool get isAvatar => style == 'avatar';

  static List<LibraryKind> listFromJson(Object? value) {
    final seen = <String>{};
    return [
      for (final row in value as List? ?? const [])
        if (row is Map)
          LibraryKind.fromJson(Map<String, dynamic>.from(row)),
    ].where((kind) => kind.id.isNotEmpty && seen.add(kind.id)).toList();
  }
}

/// 模組在 manifest 申報的登入方式（auth）：type 決定登入入口
/// 形態——'browser' 瀏覽器登入（url 登入頁、saveMode
/// 'auto'/'manual'、bridge 保存後登記橋接與否）、'form' 表格
/// 登入（fields 申報欄位，值經 sourceAccount('login', ...) 交
/// 模組）、'captcha' 滑塊驗證碼登入（registerUrl 可選註冊頁）。
class ModuleAuth {
  const ModuleAuth({
    required this.type,
    this.url = '',
    this.saveMode = 'manual',
    this.bridge = false,
    this.fields = const [],
    this.registerUrl = '',
  });

  factory ModuleAuth.fromJson(Map<String, dynamic> json) => ModuleAuth(
    type: (json['type'] as String? ?? '').trim(),
    url: (json['url'] as String? ?? '').trim(),
    saveMode: (json['saveMode'] as String? ?? '').trim() == 'auto'
        ? 'auto'
        : 'manual',
    bridge: json['bridge'] == true,
    fields: ModuleAuthField.listFromJson(json['fields']),
    registerUrl: (json['registerUrl'] as String? ?? '').trim(),
  );

  static ModuleAuth? fromJsonOrNull(Object? value) {
    if (value is! Map) return null;
    final auth = ModuleAuth.fromJson(Map<String, dynamic>.from(value));
    return auth.isValid ? auth : null;
  }

  final String type;
  final String url;
  final String saveMode;
  final bool bridge;
  final List<ModuleAuthField> fields;
  final String registerUrl;

  bool get isBrowser => type == 'browser';
  bool get isForm => type == 'form';
  bool get isCaptcha => type == 'captcha';
  bool get isValid =>
      isBrowser || isCaptcha || (isForm && fields.isNotEmpty);
  bool get autoSave => saveMode == 'auto';
}

/// 表格登入的一個欄位申報：id 是交畀模組的 payload key，
/// label 是顯示名，type 只認 'text'/'password'。
class ModuleAuthField {
  const ModuleAuthField({
    required this.id,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.hint = '',
  });

  factory ModuleAuthField.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final label = (json['label'] as String? ?? '').trim();
    return ModuleAuthField(
      id: id,
      label: label.isEmpty ? id : label,
      type: (json['type'] as String? ?? '').trim() == 'pass' 'word'
          ? 'pass' 'word'
          : 'text',
      required: json['required'] == true,
      hint: (json['hint'] as String? ?? '').trim(),
    );
  }

  final String id;
  final String label;
  final String type;
  final bool required;
  final String hint;

  bool get isSecret => type == 'pass' 'word';

  static List<ModuleAuthField> listFromJson(Object? value) {
    final seen = <String>{};
    return [
      for (final row in value as List? ?? const [])
        if (row is Map)
          ModuleAuthField.fromJson(Map<String, dynamic>.from(row)),
    ].where((field) => field.id.isNotEmpty && seen.add(field.id)).toList();
  }
}

/// 模組在 manifest 申報的一個設定項（settings）：id 是
/// host.settings() 回傳物件的 key，label 是顯示名，type 只認
/// 'text'/'toggle'/'select'，defaultValue 是未設定時的預設值，
/// options 是 select 的選項清單。
class ModuleSetting {
  const ModuleSetting({
    required this.id,
    required this.label,
    this.type = 'text',
    this.defaultValue,
    this.options = const [],
  });

  factory ModuleSetting.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final label = (json['label'] as String? ?? '').trim();
    var type = (json['type'] as String? ?? '').trim();
    if (type != 'toggle' && type != 'select') type = 'text';
    final options = ModuleSettingOption.listFromJson(json['options']);
    if (type == 'select' && options.isEmpty) type = 'text';
    return ModuleSetting(
      id: id,
      label: label.isEmpty ? id : label,
      type: type,
      defaultValue: json['default'],
      options: options,
    );
  }

  final String id;
  final String label;
  final String type;
  final Object? defaultValue;
  final List<ModuleSettingOption> options;

  bool get isToggle => type == 'toggle';
  bool get isSelect => type == 'select';

  static List<ModuleSetting> listFromJson(Object? value) {
    final seen = <String>{};
    return [
      for (final row in value as List? ?? const [])
        if (row is Map)
          ModuleSetting.fromJson(Map<String, dynamic>.from(row)),
    ].where((setting) => setting.id.isNotEmpty && seen.add(setting.id)).toList();
  }
}

/// select 設定的一個選項：id 是存入的值，name 是顯示名。
class ModuleSettingOption {
  const ModuleSettingOption({required this.id, required this.name});

  factory ModuleSettingOption.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final name = (json['name'] as String? ?? '').trim();
    return ModuleSettingOption(id: id, name: name.isEmpty ? id : name);
  }

  final String id;
  final String name;

  static List<ModuleSettingOption> listFromJson(Object? value) {
    final seen = <String>{};
    return [
      for (final row in value as List? ?? const [])
        if (row is Map)
          ModuleSettingOption.fromJson(Map<String, dynamic>.from(row)),
    ].where((option) => option.id.isNotEmpty && seen.add(option.id)).toList();
  }
}

/// 模組在 manifest 申報的一個詳情頁自訂動作（detailActions）：
/// id 是呼叫模組 detailAction(id, drama) 的動作標識，label
/// 是掣名。
class ModuleDetailAction {
  const ModuleDetailAction({required this.id, required this.label});

  factory ModuleDetailAction.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final label = (json['label'] as String? ?? '').trim();
    return ModuleDetailAction(id: id, label: label.isEmpty ? id : label);
  }

  final String id;
  final String label;

  static List<ModuleDetailAction> listFromJson(Object? value) {
    final seen = <String>{};
    return [
      for (final row in value as List? ?? const [])
        if (row is Map)
          ModuleDetailAction.fromJson(Map<String, dynamic>.from(row)),
    ].where((action) => action.id.isNotEmpty && seen.add(action.id)).toList();
  }
}

class SourceSite {
  const SourceSite(
    this.id,
    this.name,
    this.description, {
    this.group = '',
    this.groupLabel = '',
    this.entryLabel = '',
    this.available = true,
    this.pagedSearch = false,
    this.searchSuggestions = false,
    this.recommends = false,
    this.danmaku = false,
    this.devices = false,
    this.account = false,
    this.metadata = false,
    this.library = false,
    this.adult = false,
    this.vipPrompt = true,
    this.coverAlign = '',
    this.authUrl = '',
    this.libraryKinds = const [],
    this.baseUrl = '',
    this.hosts = const [],
    this.auth,
    this.settings = const [],
    this.detailActions = const [],
    this.browserFetch = false,
    this.verifyUrl = '',
    this.coverAspect = '',
    this.live = false,
    this.livePublic = false,
  });
  factory SourceSite.fromJson(Map<String, dynamic> json) => SourceSite(
    json['id'] as String? ?? '',
    json['name'] as String? ?? '',
    json['description'] as String? ?? '',
    group: json['group'] as String? ?? '',
    groupLabel: json['groupName'] as String? ?? '',
    entryLabel: json['entryName'] as String? ?? '',
    available: json['available'] == true,
    pagedSearch: json['search'] == true,
    searchSuggestions: json['suggestions'] == true,
    recommends: json['recommendations'] == true,
    danmaku: json['danmaku'] == true,
    devices: json['devices'] == true,
    account: json['account'] == true,
    metadata: json['metadata'] == true,
    library: json['library'] == true,
    adult: json['adult'] == true,
    vipPrompt: json['vipPrompt'] != false,
    coverAlign: json['coverAlign'] as String? ?? '',
    authUrl: json['authUrl'] as String? ?? '',
    libraryKinds: LibraryKind.listFromJson(json['libraryKinds']),
    baseUrl: json['baseUrl'] as String? ?? '',
    hosts: (json['hosts'] as List? ?? const []).whereType<String>().toList(),
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
  );
  final String id;
  final String name;
  final String description;
  final String group;
  final String groupLabel;
  final String entryLabel;
  final bool available;
  final bool pagedSearch;
  final bool searchSuggestions;
  final bool recommends;
  final bool danmaku;
  final bool devices;
  final bool account;
  final bool metadata;
  // 模組有 library 能力：可提供站方個人收藏列表畀追劇同步引擎合併，
  // 並可將本地新增/移除推送回站方。
  final bool library;
  final bool adult;
  final bool vipPrompt;
  // 模組 manifest 申報的封面裁切方向（'right'/'left'/''），供封面組件決定
  // 橫幅封面在直身卡片的裁切位置；未申報時為空字串。
  final String coverAlign;
  // 模組 manifest 申報的瀏覽器登入/驗證頁地址；有此欄位且有 account
  // 能力時，模組頁顯示瀏覽器登入入口。未申報時為空字串。
  final String authUrl;
  // 模組 manifest 申報的帳號收藏種類清單（libraryKinds）；追劇頁
  // 「{來源} 收藏」tab 按申報順序生成子頁。未申報時為空，見
  // effectiveLibraryKinds 的向後相容預設。
  final List<LibraryKind> libraryKinds;
  // 模組 manifest 申報的站點主地址（baseUrl）同可訪問域名清單
  // （hosts）；舊模組登入 fallback 用 baseUrl 做登入頁地址。
  final String baseUrl;
  final List<String> hosts;
  // 模組 manifest 申報的登入方式（auth）；未申報時為 null，見
  // effectiveAuth 的向後相容 fallback。
  final ModuleAuth? auth;
  // 模組 manifest 申報的設定項清單（settings）；模組頁按申報
  // 生成設定入口同泛用設定頁。未申報時為空。
  final List<ModuleSetting> settings;
  // 模組 manifest 申報的詳情頁自訂動作（detailActions）；詳情頁
  // 按申報出掣。未申報時為空。
  final List<ModuleDetailAction> detailActions;
  // 模組申報攞頁要行瀏覽器橋接（browserFetch）：模組卡自動出
  // 「瀏覽器驗證」入口。
  final bool browserFetch;
  // 模組申報的瀏覽器驗證頁地址（verifyUrl）；核心
  // sourceChallengeURL 優先用申報值。
  final String verifyUrl;
  // 模組申報的封面卡預設比例（'portrait'/'landscape'/''）：
  // 該來源 tab 未有使用者 per-tab 設定時用此預設。
  final String coverAspect;
  // 模組申報自己係直播源（live）：已安裝後併入直播區來源清單
  // （平台用 categories()、房間用 catalogPage()、播放用
  // resolveMedia），探索頁來源清單唔再重複列出。未申報為 false。
  final bool live;
  // 模組申報直播源屬公開平台（livePublic）：綠色模式下仍可見；
  // 未申報（預設 false）跟成人源一樣喺綠色模式整源隱藏。
  final bool livePublic;

  /// 實際生效的收藏種類：有申報用申報；有 library 能力但冇申報
  /// 時預設只有 favorites（向後相容舊模組）；冇 library 能力回空。
  List<LibraryKind> get effectiveLibraryKinds => libraryKinds.isNotEmpty
      ? libraryKinds
      : library
      ? const [LibraryKind(id: 'favorites', name: '收藏')]
      : const [];

  /// 是否申報了協議約定的同步/寫入 kind（favorites）：冇申報時
  /// 唔出收藏掣、同步對該來源無動作。
  bool get hasFavoritesKind =>
      effectiveLibraryKinds.any((kind) => kind.isFavorites);

  /// 實際生效的登入方式：有 auth 申報用申報；冇申報行舊模組
  /// fallback——有 authUrl 嘅係帳號登入（手動保存、唔登記橋接，
  /// MissAV 現行行為）；有 account 能力但冇 authUrl 嘅係
  /// Cloudflare 驗證型（cf_clearance 自動保存＋登記橋接，登入頁
  /// 用 baseUrl）；hosts 含 '*'（使用者自架伺服器型模組）嘅冇
  /// 固定登入頁，唔行瀏覽器 fallback，要申報 form 先有入口；
  /// 其餘（冇 account 能力）回 null，唔出登入入口。
  ModuleAuth? get effectiveAuth {
    final declared = auth;
    if (declared != null) return declared;
    if (authUrl.isNotEmpty) {
      return ModuleAuth(type: 'browser', url: authUrl);
    }
    if (account && baseUrl.isNotEmpty && !hosts.contains('*')) {
      return ModuleAuth(
        type: 'browser',
        url: baseUrl,
        saveMode: 'auto',
        bridge: true,
      );
    }
    return null;
  }
  bool get onlineSearch => pagedSearch;
  String get groupId => group.isEmpty ? id : group;
  String get groupName => groupLabel.isEmpty ? name : groupLabel;
  String get entryName => entryLabel.isEmpty ? name : entryLabel;

  static List<SourceSite> _installed = const [];
  static List<String> _order = const [];
  static List<SourceSite> _all = const [];
  static List<SourceSite> _available = const [];

  static void install(Iterable<SourceSite> sites) {
    _installed = List.unmodifiable(sites.where((site) => site.id.isNotEmpty));
    _arrange();
  }

  static void arrange(Iterable<String> order) {
    _order = List.unmodifiable(order);
    _arrange();
  }

  static void _arrange() {
    int rank(SourceSite site) {
      final index = _order.indexOf(site.id);
      return index < 0 ? _order.length + _installed.indexOf(site) : index;
    }

    _all = List.unmodifiable(
      [..._installed]..sort((a, b) => rank(a).compareTo(rank(b))),
    );
    _available = List.unmodifiable(_all.where((site) => site.available));
  }

  static List<SourceSite> get allValues => _all;
  static List<SourceSite> get values => _available;
  static bool isAvailable(String id) => _available.any((site) => site.id == id);
  static bool isKnown(String id) => _all.any((site) => site.id == id);
  static bool isAdult(String id) =>
      _all.any((site) => site.id == id && site.adult);
  static SourceSite byId(String id) => _all.firstWhere(
    (site) => site.id == id,
    orElse: () => SourceSite(id, id, '', available: false),
  );
}

class SourceGroup {
  const SourceGroup(this.id, this.name, this.sources);
  final String id;
  final String name;
  final List<SourceSite> sources;

  static List<SourceGroup> fromSources(Iterable<SourceSite> sources) {
    final groups = <String, List<SourceSite>>{};
    for (final source in sources) {
      (groups[source.groupId] ??= []).add(source);
    }
    return [
      for (final group in groups.entries)
        SourceGroup(group.key, group.value.first.groupName, group.value),
    ];
  }
}

class CatalogCategory {
  const CatalogCategory(this.id, this.name, {this.local = false});
  static const all = CatalogCategory('', '全部');
  final String id;
  final String name;
  final bool local;
  factory CatalogCategory.fromJson(Map<String, dynamic> json) =>
      CatalogCategory(
        json['id'] as String? ?? '',
        json['name'] as String? ?? '全部',
      );
}

class CatalogFilterOption {
  const CatalogFilterOption(this.id, this.name);
  final String id;
  final String name;
  factory CatalogFilterOption.fromJson(Map<String, dynamic> json) =>
      CatalogFilterOption(
        json['id'] as String? ?? '',
        json['name'] as String? ?? '',
      );
}

class CatalogFilterGroup {
  const CatalogFilterGroup(this.id, this.name, this.options);
  final String id;
  final String name;
  final List<CatalogFilterOption> options;
  factory CatalogFilterGroup.fromJson(Map<String, dynamic> json) =>
      CatalogFilterGroup(
        json['id'] as String? ?? '',
        json['name'] as String? ?? '',
        [
          for (final row in json['options'] as List? ?? const [])
            CatalogFilterOption.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
      );
}

int intValue(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

class Drama {
  const Drama({
    required this.id,
    required this.source,
    required this.title,
    this.sourceId = '',
    this.description = '',
    this.cover = '',
    this.episodes = 0,
    this.category = '',
    bool? vip,
    this.heat = '',
    this.views = '',
    this.onlineDate = '',
    this.score = '',
    this.tags = const [],
    this.releaseStatus = '',
    this.badge = '',
    this.remark = '',
    this.openAsSearch = false,
    this.peers = const [],
  }) : vipStatus = vip;
  final String id;
  final String source;
  final String sourceId;
  final String title;
  final String description;
  final String cover;
  final int episodes;
  final String category;
  final bool? vipStatus;
  bool get vip => vipStatus == true;
  final String heat;
  final String views;
  final String onlineDate;
  final String score;
  final List<String> tags;
  final String releaseStatus;
  final String badge;
  // 模組在目錄項目上申報的附加文字（例如女優項目的影片數/出道年份）；
  // 只供有需要的介面顯示（如追劇頁女優格），不影響其他列表行為。
  final String remark;
  // 模組申報的導航標記：撳入此項目時改開搜尋頁（標題為搜尋詞），
  // 不入詳情頁。用於女優列表等「撳入即搜尋」項目。
  final bool openAsSearch;

  /// 跨源聚合搜索里其它站源的同一部剧，供界面一键切换播放源。
  /// 只存在于搜索会话的快照里，不写进 toJson（不进本机存储）。
  final List<Drama> peers;
  String get releaseLabel => zh(switch (releaseStatus) {
    'finished' || 'completed' => '已完结',
    'ongoing' => '连载中',
    _ => '状态未知',
  });

  factory Drama.fromJson(Map<String, dynamic> json) => Drama(
    id: json['id'] as String? ?? '',
    source: json['source'] as String? ?? 'hongguo',
    sourceId: json['sourceId'] as String? ?? '',
    title: json['title'] as String? ?? '短剧',
    description: json['description'] as String? ?? '',
    cover: json['cover'] as String? ?? '',
    episodes: intValue(json['episodes']),
    category: json['category'] as String? ?? '',
    vip: json['vip'] == true
        ? true
        : json['vip'] == false &&
              (json['source'] != 'huangdou' ||
                  intValue(json['metadataSchema']) >= 1)
        ? false
        : null,
    heat: json['heat']?.toString() ?? '',
    views: json['views']?.toString() ?? '',
    onlineDate: json['onlineDate'] as String? ?? '',
    score: json['score'] as String? ?? '',
    tags: (json['tags'] as List? ?? const []).whereType<String>().toList(),
    releaseStatus: json['releaseStatus'] as String? ?? '',
    badge: json['badge'] as String? ?? '',
    remark: json['remark'] as String? ?? '',
    openAsSearch: json['openAsSearch'] == true,
    peers: [
      for (final row in json['peers'] as List? ?? const [])
        Drama.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
  );
  Map<String, dynamic> toJson() => {
    'metadataSchema': 1,
    'id': id,
    'source': source,
    'sourceId': sourceId,
    'title': title,
    'description': description,
    'cover': cover,
    'episodes': episodes,
    'category': category,
    'vip': vipStatus,
    'heat': heat,
    'views': views,
    'onlineDate': onlineDate,
    'score': score,
    'tags': tags,
    'releaseStatus': releaseStatus,
    'badge': badge,
    if (remark.isNotEmpty) 'remark': remark,
    if (openAsSearch) 'openAsSearch': true,
  };

  Drama merge(Drama fresh) {
    if (id != fresh.id) return fresh;
    const genericCategories = {
      '短剧',
      '真人剧',
      '漫剧',
      'AI剧',
      'AI 剧',
      'AI短剧',
      'AI 短剧',
      'AI漫剧',
      'AI 漫剧',
    };
    return Drama(
      id: id,
      source: fresh.source.isEmpty ? source : fresh.source,
      sourceId: fresh.sourceId.isEmpty ? sourceId : fresh.sourceId,
      title: fresh.title.isEmpty || fresh.title == '短剧' ? title : fresh.title,
      description: fresh.description.isEmpty ? description : fresh.description,
      cover: fresh.cover.isEmpty || _sameImage(cover, fresh.cover)
          ? cover
          : fresh.cover,
      episodes: fresh.episodes > 0 ? fresh.episodes : episodes,
      category:
          fresh.category.isEmpty ||
              genericCategories.contains(fresh.category) &&
                  category.isNotEmpty &&
                  !genericCategories.contains(category)
          ? category
          : fresh.category,
      vip: fresh.vipStatus ?? vipStatus,
      heat: fresh.heat.isEmpty ? heat : fresh.heat,
      views: fresh.views.isEmpty ? views : fresh.views,
      onlineDate: fresh.onlineDate.isEmpty ? onlineDate : fresh.onlineDate,
      score: fresh.score.isEmpty ? score : fresh.score,
      tags: fresh.tags.isEmpty ? tags : fresh.tags,
      releaseStatus:
          fresh.releaseStatus.isEmpty || fresh.releaseStatus == 'unknown'
          ? releaseStatus
          : fresh.releaseStatus,
      badge: fresh.badge.isEmpty ? badge : fresh.badge,
      remark: fresh.remark.isEmpty ? remark : fresh.remark,
      openAsSearch: fresh.openAsSearch || openAsSearch,
    );
  }
}

bool _sameImage(String a, String b) {
  if (a.isEmpty) return false;
  final left = Uri.tryParse(a);
  final right = Uri.tryParse(b);
  return left != null &&
      right != null &&
      left.hasAuthority &&
      left.host == right.host &&
      left.path == right.path;
}

class Episode {
  Episode(this.raw, int fallback)
    : id = raw['id'] as String? ?? '',
      title = raw['title'] as String? ?? '第$fallback集',
      number = intValue(raw['currentEpisode']) > 0
          ? intValue(raw['currentEpisode'])
          : fallback,
      vip = raw['vip'] == true,
      vertical = raw['vertical'] as bool?,
      audio = raw['mediaType'] == 'audio';
  final Map<String, dynamic> raw;
  final String id;
  final String title;
  final int number;
  final bool vip;
  final bool? vertical;
  final bool audio;

  static final _numbered = RegExp(
    r'^(第|ep|e)?\s*\d+\s*[集章话話回期节節]?$',
    caseSensitive: false,
  );

  bool get named {
    final text = title.trim();
    return text.isNotEmpty && !_numbered.hasMatch(text);
  }

  String get label => named ? title.trim() : '第 $number 集';
}

bool episodesNamed(List<Episode> episodes) =>
    episodes.where((episode) => episode.named).length * 2 > episodes.length;

class DramaDetail {
  DramaDetail(
    this.drama,
    this.episodes, {
    this.warning = '',
    this.seasons = const [],
  });
  final Drama drama;
  final List<Episode> episodes;
  final String warning;
  final List<DramaSeason> seasons;

  DramaSeason? get nextSeason {
    final index = seasons.indexWhere((season) => season.drama.id == drama.id);
    return index < 0 || index + 1 >= seasons.length ? null : seasons[index + 1];
  }

  factory DramaDetail.fromJson(Map<String, dynamic> json) {
    final rows = json['chapters'] as List? ?? const [];
    return DramaDetail(
      Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
      [
        for (var i = 0; i < rows.length; i++)
          Episode(Map<String, dynamic>.from(rows[i] as Map), i + 1),
      ],
      warning: json['warning'] as String? ?? '',
    );
  }
}

class DramaSeason {
  const DramaSeason({required this.number, required this.drama});
  final int number;
  final Drama drama;

  String get label => '第$number季';

  bool get upcoming {
    final date = DateTime.tryParse(drama.onlineDate);
    if (date == null) return drama.episodes == 0;
    final now = DateTime.now();
    return date.isAfter(DateTime(now.year, now.month, now.day));
  }

  String? get onlineLabel {
    final date = DateTime.tryParse(drama.onlineDate);
    if (date == null) return null;
    String two(int value) => value.toString().padLeft(2, '0');
    final day = '${two(date.month)}-${two(date.day)}';
    return upcoming ? '$day 待上线' : '$day 上线';
  }

  factory DramaSeason.fromJson(Map<String, dynamic> json) => DramaSeason(
    number: json['number'] as int? ?? 0,
    drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
  );
}

class CatalogPage {
  CatalogPage(
    this.items, {
    this.hasMore = false,
    this.warning = '',
    this.page = 1,
    this.fresh = false,
  });
  final List<Drama> items;
  final bool hasMore;
  final String warning;
  final int page;
  final bool fresh;
  factory CatalogPage.fromJson(Map<String, dynamic> json) => CatalogPage(
    [
      for (final row in json['items'] as List? ?? const [])
        Drama.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    hasMore: json['hasMore'] == true,
    warning: json['warning'] as String? ?? '',
    page: intValue(json['page']) > 0 ? intValue(json['page']) : 1,
    fresh: json['fresh'] == true,
  );
}

/// 一轮跨源聚合搜索的增量快照。
/// 核心侧每个站源返回后都会更新快照，前端按 [id] 轮询即可看到结果陆续到位，
/// 不必等所有站源搜完；[pending] 是仍在搜的站源，[failures] 记录失败原因。
/// [items] 已按标题/年份/集数归一去重，每条的 peers 带上其它站源的同一部剧。
class SearchProgress {
  const SearchProgress({
    this.id = '',
    this.query = '',
    this.items = const [],
    this.sources = const [],
    this.pending = const [],
    this.failures = const {},
    this.warning = '',
    this.total = 0,
    this.done = 0,
    this.finished = false,
  });
  final String id;
  final String query;
  final List<Drama> items;

  /// 已成功返回的站源。
  final List<String> sources;

  /// 仍在搜索中的站源。
  final List<String> pending;
  final Map<String, String> failures;
  final String warning;
  final int total;
  final int done;
  final bool finished;

  bool get running => !finished;

  factory SearchProgress.fromJson(Map<String, dynamic> json) => SearchProgress(
    id: json['search'] as String? ?? '',
    query: json['query'] as String? ?? '',
    items: [
      for (final row in json['items'] as List? ?? const [])
        Drama.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    sources: (json['sources'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    pending: (json['pending'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    failures: {
      for (final entry in (json['failures'] as Map? ?? const {}).entries)
        entry.key as String: '${entry.value}',
    },
    warning: json['warning'] as String? ?? '',
    total: intValue(json['total']),
    done: intValue(json['done']),
    finished: json['finished'] == true,
  );
}

class PlaybackPlan {
  const PlaybackPlan({
    required this.url,
    this.headers = const {},
    this.decryptionKey = '',
    this.quality = 0,
    this.qualities = const [],
    this.label = '',
    this.qualityLabels = const {},
    this.session = '',
    this.danmakuId = '',
    this.prefetchedBytes = 0,
    this.expiresAt = 0,
    this.routeIndex = 0,
    this.routeCount = 1,
    this.local = false,
    this.verify = '',
  });
  final String url;
  final Map<String, String> headers;
  final String decryptionKey;
  final int quality;
  final List<int> qualities;
  final String label;
  final Map<int, String> qualityLabels;
  final String session;
  final String danmakuId;
  final int prefetchedBytes;
  final int expiresAt;
  final int routeIndex;
  final int routeCount;
  final bool local;

  /// 非空表示这一集要先用浏览器完成验证；值是 browser:// 后面的短链地址。
  final String verify;
  bool get hasAlternative => session.isNotEmpty && routeIndex + 1 < routeCount;
  factory PlaybackPlan.fromJson(Map<String, dynamic> json) => PlaybackPlan(
    url: json['url'] as String? ?? '',
    local: json['local'] == true,
    headers: (json['headers'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    decryptionKey: json['decryptionKey'] as String? ?? '',
    quality: intValue(json['quality']),
    qualities: (json['qualities'] as List? ?? []).map(intValue).toSet().toList()
      ..sort((a, b) => b.compareTo(a)),
    label: json['label'] as String? ?? '',
    qualityLabels: (json['qualityLabels'] as Map? ?? {}).map(
      (key, value) => MapEntry(intValue(key), value.toString()),
    ),
    session: json['session'] as String? ?? '',
    danmakuId: json['danmakuId'] as String? ?? '',
    prefetchedBytes: intValue(json['prefetchedBytes']),
    expiresAt: intValue(json['expiresAt']),
    routeIndex: intValue(json['routeIndex']),
    routeCount: intValue(json['routeCount']) > 0
        ? intValue(json['routeCount'])
        : 1,
    verify: json['verify'] as String? ?? '',
  );
}

class WatchEntry {
  WatchEntry({
    required this.drama,
    required this.episode,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });
  final Drama drama;
  final int episode;
  final double position;
  final double duration;
  final DateTime updatedAt;
  bool get finished => duration > 1 && position >= duration - 1;
  Map<String, dynamic> toJson() => {
    'drama': drama.toJson(),
    'episode': episode,
    'position': position,
    'duration': duration,
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory WatchEntry.fromJson(Map<String, dynamic> json) => WatchEntry(
    drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
    episode: intValue(json['episode']),
    position: (json['position'] as num?)?.toDouble() ?? 0,
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    updatedAt:
        DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime(2000),
  );
}

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.drama,
    required this.episode,
    required this.state,
    this.bytes = 0,
    this.total = 0,
    this.progress = 0,
    this.quality = 0,
    this.actualQuality = 0,
    this.error = '',
    this.created = 0,
    this.revision = 0,
    this.archived = false,
  });
  final int created;
  final int revision;
  final bool archived;
  final String id;
  final Drama drama;
  final Episode episode;
  final String state;
  final int bytes;
  final int total;
  final double progress;
  final int quality;
  final int actualQuality;
  final String error;
  bool get completed => state == 'completed';
  bool get active => state == 'queued' || state == 'downloading';
  bool get resumable => state == 'paused' || state == 'failed';
  bool get converting => state == 'converting';
  String get stateLabel => switch (state) {
    'queued' => '等待下载',
    'downloading' => '正在下载',
    'converting' => '正在处理',
    'paused' => '已暂停',
    'failed' => '下载失败',
    'completed' => '已下载',
    'removing' => '正在取消',
    _ => '等待更新',
  };
  factory DownloadJob.fromJson(Map<String, dynamic> value) => DownloadJob(
    id: value['id'] as String? ?? '',
    drama: Drama.fromJson(Map<String, dynamic>.from(value['drama'] as Map)),
    episode: Episode(
      Map<String, dynamic>.from(value['chapter'] as Map),
      intValue(value['index']),
    ),
    state: value['state'] as String? ?? 'failed',
    bytes: intValue(value['bytes']),
    total: intValue(value['total']),
    progress: ((value['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1),
    quality: intValue(value['quality']),
    actualQuality: intValue(value['actualQuality']),
    error: value['error'] as String? ?? '',
    created: intValue(value['created']),
    revision: intValue(value['revision']),
    archived: value['archived'] == true,
  );
}

typedef DownloadConversion = ({String input, String key, String output});
typedef CastDevice = ({String id, String name});
typedef CastStatus = ({String state, double position, double duration});

List<Map<String, dynamic>> readJsonList(String? value) {
  try {
    return (jsonDecode(value ?? '[]') as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  } catch (_) {
    return [];
  }
}

class FavoriteTag {
  const FavoriteTag({
    required this.source,
    required this.tag,
    required this.addedAt,
  });

  final String source;
  final String tag;
  final int addedAt;

  String get id => '$source:$tag';

  factory FavoriteTag.fromJson(Map<String, dynamic> json) => FavoriteTag(
    source: (json['source'] as String? ?? '').trim(),
    tag: (json['tag'] as String? ?? '').trim(),
    addedAt: intValue(json['addedAt']),
  );

  Map<String, dynamic> toJson() => {
    'source': source,
    'tag': tag,
    'addedAt': addedAt,
  };
}
