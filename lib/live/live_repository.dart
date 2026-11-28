import 'dart:async';
import 'dart:convert';

import '../core_bridge.dart';
import '../models.dart';
import '../zh_script.dart';
import 'live_http.dart';
import 'live_models.dart';
import 'live_parser.dart';
import 'live_rooms.dart';
import 'live_sources.dart';

class LiveRepository {
  LiveRepository({LiveHttp? http, this.appRepository})
    : _http = http ?? LiveHttp();

  /// 模組直播源的數據通道（categories/catalog/detail/resolve）。
  /// 由 openLive 在開啟直播頁時注入；未注入時模組源會報錯，
  /// 內置源不受影響。
  AppRepository? appRepository;

  /// 已失效的分类：源站仍返回，但频道统一跳转到版权拦截页。
  static const retiredCategories = ['weishizhibo'];

  static final _cctv = RegExp(r'^(cctv|央视|中央电视台)', caseSensitive: false);

  final LiveHttp _http;
  final Map<String, List<LivePlatform>> _platforms = {};
  final Map<String, List<LiveChannel>> _channels = {};
  final Map<String, List<int>> _routeOrders = {};

  /// 模組房間的 Drama 原件（key 為 LiveChannel.key）：播放時要
  /// 交返核心行 detail＋resolve。收藏/最近觀看重啟後冇呢份，
  /// 會用 channel 記錄的 sourceId 重組。
  final Map<String, Drama> _moduleDramas = {};
  int _generation = 0;

  void cancel() {
    _generation++;
  }

  void dispose() {
    _generation++;
    _http.close();
  }

  void clear() {
    _platforms.clear();
    _channels.clear();
    _routeOrders.clear();
    _moduleDramas.clear();
  }

  Future<List<LivePlatform>> platforms(
    LiveSource source, {
    bool force = false,
  }) async {
    if (!force) {
      final cached = _platforms[source.id];
      if (cached != null) return cached;
    }
    final token = _generation;
    final result = switch (source.protocol) {
      LiveProtocol.pingtai => await _pingtaiPlatforms(source),
      LiveProtocol.list => const [LivePlatform(id: 'all', name: '全部频道')],
      LiveProtocol.room => await LiveRoomClient(_http).platforms(source),
      LiveProtocol.module => await _modulePlatforms(source, force: force),
    };
    if (result.isEmpty) throw AppFailure(zh('该直播源没有可用分类'));
    if (token == _generation) _platforms[source.id] = result;
    return result;
  }

  Future<List<LiveChannel>> channels(
    LiveSource source,
    LivePlatform platform, {
    int page = 1,
    bool force = false,
  }) async {
    final cacheKey = '${source.id}\u0000${platform.id}\u0000$page';
    if (!force) {
      final cached = _channels[cacheKey];
      if (cached != null) return cached;
    }
    final result = switch (source.protocol) {
      LiveProtocol.pingtai => await _pingtaiChannels(source, platform),
      LiveProtocol.list => await _listChannels(source),
      LiveProtocol.room => await LiveRoomClient(
        _http,
      ).channels(source, platform, page: page),
      LiveProtocol.module => await _moduleChannels(
        source,
        platform,
        page: page,
        force: force,
      ),
    };
    if (result.isEmpty) {
      if (page > 1 &&
          (source.protocol == LiveProtocol.room ||
              source.protocol == LiveProtocol.module)) {
        _channels[cacheKey] = const [];
        return const [];
      }
      throw AppFailure(zh('该分类暂时没有频道'));
    }
    _channels[cacheKey] = result;
    return result;
  }

  Future<LivePlayback> playback(LiveSource source, LiveChannel channel) async {
    // 收藏 / 最近观看里的频道可能来自另一个源，取流要按频道自己记录的源路由。
    final resolved = LiveSource.byId(channel.source) ?? source;
    if (resolved.protocol == LiveProtocol.room) {
      return LiveRoomClient(_http).playback(resolved, channel);
    }
    if (resolved.protocol == LiveProtocol.module) {
      return _modulePlayback(resolved, channel);
    }
    if (channel.urls.isEmpty) throw AppFailure(zh('该频道没有可用线路'));
    return LivePlayback(url: channel.urls.first, headers: channel.headers);
  }

  AppRepository get _modules {
    final repository = appRepository;
    if (repository == null) throw AppFailure(zh('直播模組未就緒，請重開直播頁'));
    return repository;
  }

  /// 模組直播源的平台清單：直接用模組 categories() 申報的分類。
  Future<List<LivePlatform>> _modulePlatforms(
    LiveSource source, {
    bool force = false,
  }) async {
    final categories = await _modules.categories(
      source.moduleId,
      force: force,
    );
    return [
      for (final category in categories)
        if (category.id.isNotEmpty)
          LivePlatform(id: category.id, name: category.name),
    ];
  }

  /// 模組直播源的房間清單：catalogPage(platform) 的 Drama 項目
  /// 映射成直播頻道卡（串流地址播放時先經 resolveMedia 攞，
  /// 所以 urls 留空、sourceId 存入 token 供重組 Drama）。
  Future<List<LiveChannel>> _moduleChannels(
    LiveSource source,
    LivePlatform platform, {
    int page = 1,
    bool force = false,
  }) async {
    final result = await _modules.catalog(
      source.moduleId,
      category: platform.id,
      page: page,
      force: force,
    );
    return [
      for (final drama in result.items) _moduleChannel(source, platform, drama),
    ];
  }

  LiveChannel _moduleChannel(
    LiveSource source,
    LivePlatform platform,
    Drama drama,
  ) {
    _moduleDramas[drama.id] = drama;
    return LiveChannel(
      key: drama.id,
      name: drama.title,
      urls: const [],
      logo: drama.cover,
      group: platform.name,
      source: source.id,
      token: drama.sourceId,
      subtitle: drama.remark.isNotEmpty ? drama.remark : drama.heat,
    );
  }

  /// 模組房間播放：行返一般模組路徑 detail＋resolve 攞串流
  /// 地址同 headers，再交直播播放器播（FLV/HLS 都係 mpv 直播
  /// 流，直播播放器接得到）。
  Future<LivePlayback> _modulePlayback(
    LiveSource source,
    LiveChannel channel,
  ) async {
    final drama =
        _moduleDramas[channel.key] ??
        Drama(
          id: channel.key,
          source: channel.source,
          sourceId: channel.token,
          title: channel.name,
        );
    final detail = await _modules.detail(drama);
    if (detail.episodes.isEmpty) {
      throw AppFailure(zh('该直播间暂时无法播放'));
    }
    final plan = await _modules.resolve(detail.drama, detail.episodes.first);
    if (plan.url.isEmpty) throw AppFailure(zh('该直播间暂时无法播放'));
    return LivePlayback(url: plan.url, headers: plan.headers);
  }

  /// 合并同一面板的所有镜像：各镜像共享内容但分类子集不同，取并集后去重，
  /// 并让每个分类记住提供它的镜像。
  Future<List<LivePlatform>> _pingtaiPlatforms(LiveSource source) async {
    final byId = <String, LivePlatform>{};
    final failures = <String>[];
    for (final endpoint in source.endpoints) {
      final List<dynamic> rows;
      try {
        final text = await _http.get('$endpoint/json.txt');
        final dynamic decoded = jsonDecode(text);
        final raw = decoded is Map ? decoded['pingtai'] : decoded;
        if (raw is! List) continue;
        rows = raw;
      } catch (error) {
        failures.add('$error');
        continue;
      }
      for (final row in rows.whereType<Map>()) {
        final id = '${row['address'] ?? ''}'.trim();
        final name = '${row['title'] ?? ''}'.trim();
        if (id.isEmpty || name.isEmpty) continue;
        if (retiredCategories.any(id.contains)) continue;
        final count = int.tryParse('${row['Number'] ?? ''}') ?? 0;
        final item = LivePlatform(
          id: id,
          name: name,
          logo: '${row['xinimg'] ?? ''}'.trim(),
          count: count,
          endpoint: endpoint,
        );
        // 各镜像的分类计数并不同步（实测同一分类一边记 0、另一边记 77），
        // 只要任一镜像报告有内容就保留，并跟随该镜像取频道。
        final previous = byId[id];
        if (previous == null || count > previous.count) byId[id] = item;
      }
    }
    if (byId.isEmpty) {
      throw AppFailure(
        failures.isEmpty ? zh('该直播源没有可用分类') : zh('该直播源暂时不可用：${failures.first}'),
      );
    }
    final all = byId.values.toList();
    final result = [
      for (final item in all)
        if (item.count > 0) item,
    ];
    // 上游整体不带频道数字段时不做过滤，避免把整个源误判成没有分类。
    return result.isEmpty ? all : result;
  }

  Future<List<LiveChannel>> _pingtaiChannels(
    LiveSource source,
    LivePlatform platform,
  ) async {
    // 优先用提供该分类的镜像，全部失败再依次试其他镜像。
    final candidates = <String>{
      if (platform.endpoint.isNotEmpty) platform.endpoint,
      ...source.endpoints,
    };
    String? text;
    Object? lastError;
    for (final endpoint in candidates) {
      try {
        text = await _http.get('$endpoint/${platform.id}');
        break;
      } catch (error) {
        lastError = error;
      }
    }
    if (text == null) throw AppFailure('$lastError');
    final dynamic decoded = jsonDecode(text);
    final rows = decoded is Map
        ? decoded['zhubo'] ?? decoded['list'] ?? decoded['data']
        : decoded;
    if (rows is! List) throw AppFailure(zh('该分类暂时没有频道'));
    final reliable = <LiveChannel>[];
    final fallback = <LiveChannel>[];
    final seen = <String>{};
    var number = 0;
    for (final row in rows.whereType<Map>()) {
      final name = '${row['title'] ?? ''}'.trim();
      final url = '${row['address'] ?? ''}'.trim();
      if (name.isEmpty || !isPlayableLiveUrl(url) || !seen.add(name)) continue;
      if (_cctv.hasMatch(name)) continue;
      number++;
      final channel = LiveChannel(
        key: LiveChannel.makeKey(source.id, platform.name, name),
        name: name,
        urls: [url],
        number: number.toString().padLeft(3, '0'),
        headers: source.headers,
        logo: '${row['img'] ?? ''}'.trim(),
        group: platform.name,
        source: source.id,
      );
      (url.startsWith('rtmp') ? fallback : reliable).add(channel);
    }
    return [...reliable, ...fallback];
  }

  Future<List<LiveChannel>> _listChannels(LiveSource source) async {
    final text = await _http.get(source.endpoint, headers: source.headers);
    final parsed = LiveParser.parse(
      text,
      source: source.id,
      defaultGroup: source.group.isEmpty ? liveUnsortedGroup : source.group,
    );
    final channels = [for (final group in parsed.groups) ...group.channels];
    if (source.proxies.isEmpty) return channels;
    final expanded = [
      for (final channel in channels)
        channel.withUrls([
          for (final proxy in source.proxies)
            if (channel.url.isNotEmpty) '$proxy${channel.url}',
          ...channel.urls,
        ]),
    ];
    final order = await _routeOrder(
      source,
      channels.first.url,
      channels.first.headers,
    );
    if (order == null) return expanded;
    return [
      for (final channel in expanded)
        channel.withUrls([
          for (final index in order)
            if (index < channel.urls.length) channel.urls[index],
        ]),
    ];
  }

  /// 线路可用性取决于用户所处网络，写死的顺序对一部分用户必然是最差顺序：
  /// 列表型源的首条代理实测要 11 秒才响应，而同一条直连在另一些网络直接 403。
  /// 因此按「能取到清单 + 响应快」实测排序，取不到清单的线路沉到最后兜底。
  Future<List<int>?> _routeOrder(
    LiveSource source,
    String sample,
    Map<String, String> headers,
  ) async {
    if (source.proxies.isEmpty || sample.isEmpty) return null;
    final cached = _routeOrders[source.id];
    if (cached != null) return cached;
    final total = source.proxies.length + 1;
    final probes = await Future.wait<Duration?>([
      for (var index = 0; index < total; index++)
        _probeRoute(
          index == total - 1 ? sample : '${source.proxies[index]}$sample',
          headers,
        ),
    ]);
    final order = List<int>.generate(total, (index) => index)
      ..sort((left, right) {
        final a = probes[left];
        final b = probes[right];
        if (a == null || b == null) {
          if (a == null && b == null) return left.compareTo(right);
          return a == null ? 1 : -1;
        }
        final compared = a.compareTo(b);
        return compared == 0 ? left.compareTo(right) : compared;
      });
    _routeOrders[source.id] = order;
    return order;
  }

  /// 返回该线路取回播放清单的耗时，取不到返回 null。
  Future<Duration?> _probeRoute(String url, Map<String, String> headers) async {
    final watch = Stopwatch()..start();
    try {
      await _http.get(url, headers: headers).timeout(liveRouteProbeTimeout);
      return watch.elapsed;
    } catch (_) {
      // 预检失败只影响排序，不应该让整个分类加载失败。
      return null;
    }
  }
}
