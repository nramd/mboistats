import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Service untuk mengambil, menyimpan cache lokal, dan mem-parsing data dari BPS Web API
/// URL Pattern: https://webapi.bps.go.id/v1/api/list/model/data/domain/{domain}/var/{varId}/th/{thRange}/key/{apiKey}
class BpsApiService {
  static const String _baseUrl = 'https://webapi.bps.go.id/v1/api/list';
  static const String _apiKey = '9db89e91c3c142df678e65a78c4e547f';
  static const String _domain = '3573'; // Kota Malang
  static const Map<String, String> bpsHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  // Token `?f=` pada WebAPI BPS kedaluwarsa dalam ~1-2 jam; batasi cache in-memory 15 menit
  static const Duration _cacheTtl = Duration(minutes: 15);
  static final Map<String, List<Map<String, dynamic>>> _liveListCache = {};
  static final Map<String, DateTime> _liveListCacheTimes = {};
  static final Map<String, BpsMediaUrls> _resolvedMediaCache = {};
  static final Map<String, DateTime> _resolvedMediaCacheTimes = {};
  static final Map<String, Future<BpsMediaUrls?>> _inFlightMediaLookups = {};

  static bool _isCacheFresh(DateTime? timestamp) {
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheTtl;
  }

  static Future<File> _getCacheFile(int varId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/bps_var_$varId.json');
  }

  /// Mengambil data statistik dari cache lokal persisten atau BPS Web API
  /// [varId] = ID variabel statistik (misal: 434 = Laju Pertumbuhan Ekonomi)
  /// [maxYears] = Jumlah tahun terakhir yang ditampilkan (default: 10)
  /// [client] = Opsional http.Client untuk manajemen lifecycle (pembatalan saat dispose)
  /// [forceRefresh] = Jika true, lewati pembacaan awal cache lokal dan perbarui dari jaringan
  static Future<BpsDataResult> fetchData({
    required int varId,
    int maxYears = 10,
    http.Client? client,
    bool forceRefresh = false,
  }) async {
    File? cacheFile;
    try {
      cacheFile = await _getCacheFile(varId);
    } catch (_) {
      cacheFile = null;
    }

    // 1. Cache-First: baca dari berkas lokal apabila tersedia dan valid
    if (!forceRefresh && cacheFile != null) {
      try {
        if (await cacheFile.exists() && (await cacheFile.length()) > 0) {
          final rawJson = await cacheFile.readAsString();
          final decoded = jsonDecode(rawJson);
          if (decoded is Map<String, dynamic>) {
            final result = BpsDataResult.fromJson(decoded, maxYears: maxYears);
            if (result.years.isNotEmpty && result.series.isNotEmpty) {
              return result;
            }
          }
          // Invalidasi berkas cache lokal yang rusak atau tidak lengkap
          await cacheFile.delete();
        }
      } catch (_) {
        try {
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        } catch (_) {}
      }
    }

    // 2. Network Fetch dengan fallback otomatis apabila endpoint /th/1: dibatasi 3 tahun per panggilan
    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    try {
      final jsonMap = await _fetchJsonFromNetwork(
        httpClient: httpClient,
        varId: varId,
        maxYears: maxYears,
      );

      final result = BpsDataResult.fromJson(jsonMap, maxYears: maxYears);
      if (result.years.isEmpty || result.series.isEmpty) {
        throw const FormatException(
            'Payload data indikator BPS kosong atau tidak valid.');
      }

      if (cacheFile != null) {
        try {
          await cacheFile.writeAsString(jsonEncode(jsonMap));
        } catch (_) {}
      }

      return result;
    } catch (e) {
      // Fallback ke cache lokal jika forceRefresh gagal karena perangkat sedang offline
      if (forceRefresh && cacheFile != null) {
        try {
          if (await cacheFile.exists() && (await cacheFile.length()) > 0) {
            final rawJson = await cacheFile.readAsString();
            final decoded = jsonDecode(rawJson);
            if (decoded is Map<String, dynamic>) {
              final result =
                  BpsDataResult.fromJson(decoded, maxYears: maxYears);
              if (result.years.isNotEmpty && result.series.isNotEmpty) {
                return result;
              }
            }
          }
        } catch (_) {}
      }
      throw Exception('Gagal mengambil data BPS: $e');
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  static Future<Map<String, dynamic>> _fetchJsonFromNetwork({
    required http.Client httpClient,
    required int varId,
    required int maxYears,
  }) async {
    // BPS WebAPI membatasi parameter /th/ maksimal 3 tahun per panggilan (HTTP 400 jika /th/1:/)
    // sehingga daftar th_id diambil lebih dulu lewat endpoint model/th lalu diunduh per chunk <= 3 tahun.
    final thUrl = '$_baseUrl/model/th/domain/$_domain/var/$varId/key/$_apiKey';
    final thResp = await httpClient
        .get(Uri.parse(thUrl), headers: bpsHeaders)
        .timeout(const Duration(seconds: 10));

    if (thResp.statusCode != 200) {
      throw Exception('HTTP Error (model/th): ${thResp.statusCode}');
    }

    final thDecoded = jsonDecode(thResp.body);
    if (thDecoded is! Map<String, dynamic> ||
        thDecoded['data'] is! List ||
        (thDecoded['data'] as List).length < 2) {
      throw const FormatException('Daftar tahun indikator BPS tidak tersedia.');
    }

    final List<dynamic> thItems = thDecoded['data'][1] as List<dynamic>;
    final List<int> thIds = thItems
        .map((item) => int.tryParse(item['th_id'].toString()))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();

    if (thIds.isEmpty) {
      throw const FormatException('Rentang tahun indikator BPS kosong.');
    }

    final selectedThIds = thIds.length > maxYears
        ? thIds.sublist(thIds.length - maxYears)
        : thIds;

    // Kelompokkan th_id agar selisih first..last tiap chunk selalu < 3 (maksimal 3 tahun)
    final List<List<int>> chunks = [];
    for (final id in selectedThIds) {
      if (chunks.isEmpty || (id - chunks.last.first) >= 3) {
        chunks.add([id]);
      } else {
        chunks.last.add(id);
      }
    }

    Map<String, dynamic>? mergedJson;
    final Map<String, Map<String, dynamic>> mergedTahunByVal = {};
    final Map<String, dynamic> mergedDataContent = {};
    int? lastErrorStatus;

    for (final chunk in chunks) {
      final thParam =
          chunk.length == 1 ? '${chunk.first}' : '${chunk.first}:${chunk.last}';
      final chunkUrl =
          '$_baseUrl/model/data/domain/$_domain/var/$varId/th/$thParam/key/$_apiKey';

      final chunkResp = await httpClient
          .get(Uri.parse(chunkUrl), headers: bpsHeaders)
          .timeout(const Duration(seconds: 10));

      if (chunkResp.statusCode == 200) {
        final chunkMap = jsonDecode(chunkResp.body);
        if (chunkMap is Map<String, dynamic> && chunkMap['status'] == 'OK') {
          mergedJson ??= Map<String, dynamic>.from(chunkMap);
          if (chunkMap['tahun'] is List) {
            for (final t in chunkMap['tahun'] as List) {
              if (t is Map) {
                final tMap = Map<String, dynamic>.from(t);
                final key = (tMap['val'] ?? tMap['label'] ?? '').toString();
                if (key.isNotEmpty) {
                  mergedTahunByVal[key] = tMap;
                }
              }
            }
          }
          if (chunkMap['datacontent'] is Map) {
            mergedDataContent.addAll(
              Map<String, dynamic>.from(chunkMap['datacontent'] as Map),
            );
          }
        }
      } else {
        lastErrorStatus = chunkResp.statusCode;
      }
    }

    if (mergedJson == null) {
      if (lastErrorStatus != null) {
        throw Exception('HTTP Error: $lastErrorStatus');
      }
      throw Exception('Gagal mengunduh rentang tahun indikator BPS.');
    }

    final mergedTahun = mergedTahunByVal.values.toList()
      ..sort((a, b) {
        final av = int.tryParse((a['val'] ?? '').toString()) ?? 0;
        final bv = int.tryParse((b['val'] ?? '').toString()) ?? 0;
        return av.compareTo(bv);
      });

    mergedJson['tahun'] = mergedTahun;
    mergedJson['datacontent'] = mergedDataContent;
    return mergedJson;
  }

  /// Mengambil daftar BRS, Infografis, atau Publikasi langsung dari WebAPI BPS
  /// untuk memastikan tautan gambar/PDF memakai token `?f=` terbaru (HTTP 200).
  static Future<List<Map<String, dynamic>>> fetchLiveContentList({
    required String model,
    int page = 1,
    bool forceRefresh = false,
    http.Client? client,
  }) async {
    final cacheKey = '${model}_$page';
    if (!forceRefresh &&
        _liveListCache.containsKey(cacheKey) &&
        _isCacheFresh(_liveListCacheTimes[cacheKey])) {
      return _liveListCache[cacheKey]!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final url =
        '$_baseUrl/domain/$_domain/model/$model/lang/ind/page/$page/key/$_apiKey';
    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    try {
      final response = await httpClient
          .get(Uri.parse(url), headers: bpsHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('HTTP Error: ${response.statusCode}');
      }

      final parsed = jsonDecode(response.body);
      if (parsed is! Map<String, dynamic> ||
          parsed['data'] is! List ||
          (parsed['data'] as List).length < 2 ||
          parsed['data'][1] is! List) {
        return [];
      }

      final rawList = List<Map<String, dynamic>>.from(
        (parsed['data'][1] as List).map((e) => Map<String, dynamic>.from(e)),
      );
      final normalized =
          rawList.map((item) => _normalizeLiveItem(item, model)).toList();
      _liveListCache[cacheKey] = normalized;
      _liveListCacheTimes[cacheKey] = DateTime.now();
      return normalized.map((e) => Map<String, dynamic>.from(e)).toList();
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  static Map<String, dynamic> _normalizeLiveItem(
    Map<String, dynamic> raw,
    String model,
  ) {
    final item = Map<String, dynamic>.from(raw);
    final rawTitle = (item['title'] ?? item['judul'] ?? '').toString().trim();
    // BPS infographic API sering menempelkan "(1)YYYY-MM-DD" di akhir judul
    final cleanTitle =
        rawTitle.replaceAll(RegExp(r'\(\d+\)\d{4}-\d{2}-\d{2}$'), '').trim();
    final cover =
        (item['cover'] ?? item['img'] ?? item['thumbnail'] ?? '').toString();
    final content = (item['pdf'] ?? item['dl'] ?? item['img'] ?? '').toString();
    final dateStr =
        (item['rl_date'] ?? item['sch_date'] ?? item['date'] ?? '').toString();

    item['title'] = cleanTitle.isNotEmpty ? cleanTitle : rawTitle;
    item['cover_url'] = cover;
    item['content_url'] = content;
    item['content_type'] = model == 'pressrelease'
        ? 'brs'
        : (model == 'infographic' ? 'infografis' : 'publikasi');
    if (dateStr.isNotEmpty) {
      item['created_at'] = dateStr;
    }
    return item;
  }

  /// Mencari ulang tautan media BPS yang segar (mengatasi token `?f=` kedaluwarsa / HTTP 400).
  /// Jika [forceRefresh] = true, lewati cache in-memory agar langsung meminta token baru ke WebAPI BPS.
  static Future<BpsMediaUrls?> resolveFreshMediaUrls({
    required String title,
    String? preferredType,
    bool forceRefresh = false,
    http.Client? client,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return null;

    final cacheKey = '${preferredType ?? ''}|${cleanTitle.toLowerCase()}';
    if (!forceRefresh &&
        _resolvedMediaCache.containsKey(cacheKey) &&
        _isCacheFresh(_resolvedMediaCacheTimes[cacheKey])) {
      return _resolvedMediaCache[cacheKey];
    }

    if (!forceRefresh) {
      final existingLookup = _inFlightMediaLookups[cacheKey];
      if (existingLookup != null) {
        return await existingLookup;
      }
    }

    final future = _lookupFreshMediaUrls(
      title: cleanTitle,
      preferredType: preferredType,
      forceRefresh: forceRefresh,
      client: client,
    );
    if (!forceRefresh) {
      _inFlightMediaLookups[cacheKey] = future;
    }

    try {
      final result = await future;
      if (result != null) {
        _resolvedMediaCache[cacheKey] = result;
        _resolvedMediaCacheTimes[cacheKey] = DateTime.now();
      }
      return result;
    } finally {
      if (!forceRefresh) {
        _inFlightMediaLookups.remove(cacheKey);
      }
    }
  }

  static Future<BpsMediaUrls?> _lookupFreshMediaUrls({
    required String title,
    String? preferredType,
    bool forceRefresh = false,
    http.Client? client,
  }) async {
    final models = _candidateModelsForType(preferredType);
    final keywords = _buildSearchKeywords(title);
    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    Map<String, dynamic>? bestMatch;
    double bestScore = 0.0;

    void evaluateCandidates(List<Map<String, dynamic>> candidates) {
      for (final item in candidates) {
        final candTitle = (item['title'] ?? '').toString();
        final score = _scoreTitleMatch(title, candTitle);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = item;
        }
      }
    }

    try {
      // 1. Cek cache daftar live hanya jika tidak forceRefresh dan cache masih segar
      if (!forceRefresh) {
        for (final model in models) {
          final cacheKey = '${model}_1';
          final cached = _liveListCache[cacheKey];
          if (cached != null && _isCacheFresh(_liveListCacheTimes[cacheKey])) {
            evaluateCandidates(cached);
          }
        }
        if (bestScore >= 0.85 && bestMatch != null) {
          return BpsMediaUrls(
            coverUrl: bestMatch!['cover_url'] as String?,
            contentUrl: bestMatch!['content_url'] as String?,
          );
        }
      }

      // 2. Cari via parameter keyword WebAPI BPS
      for (final model in models) {
        for (final kw in keywords) {
          final encodedKw = Uri.encodeComponent(kw);
          final url =
              '$_baseUrl/domain/$_domain/model/$model/lang/ind/keyword/$encodedKw/key/$_apiKey/';
          try {
            final resp = await httpClient
                .get(Uri.parse(url), headers: bpsHeaders)
                .timeout(const Duration(seconds: 7));
            if (resp.statusCode == 200) {
              final parsed = jsonDecode(resp.body);
              if (parsed is Map<String, dynamic> &&
                  parsed['data'] is List &&
                  (parsed['data'] as List).length > 1 &&
                  parsed['data'][1] is List) {
                final items = (parsed['data'][1] as List)
                    .map((e) =>
                        _normalizeLiveItem(Map<String, dynamic>.from(e), model))
                    .toList();
                evaluateCandidates(items);
                if (bestScore >= 0.85) break;
              }
            }
          } catch (_) {}
        }
        if (bestScore >= 0.85) break;
      }

      // 3. Fallback: ambil ulang halaman 1 live (atau halaman 2 jika belum cukup cocok)
      if (bestScore < 0.85) {
        for (final model in models) {
          if (forceRefresh ||
              !_liveListCache.containsKey('${model}_1') ||
              !_isCacheFresh(_liveListCacheTimes['${model}_1'])) {
            try {
              final page1 = await fetchLiveContentList(
                model: model,
                page: 1,
                forceRefresh: forceRefresh,
                client: httpClient,
              );
              evaluateCandidates(page1);
            } catch (_) {}
          }
        }
      }

      if (bestScore < 0.45) {
        for (final model in models) {
          try {
            final page2 = await fetchLiveContentList(
              model: model,
              page: 2,
              forceRefresh: forceRefresh,
              client: httpClient,
            );
            evaluateCandidates(page2);
            if (bestScore >= 0.85) break;
          } catch (_) {}
        }
      }

      if (bestMatch != null && bestScore >= 0.40) {
        return BpsMediaUrls(
          coverUrl: bestMatch!['cover_url'] as String?,
          contentUrl: bestMatch!['content_url'] as String?,
        );
      }
      return null;
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  static List<String> _candidateModelsForType(String? preferredType) {
    final t = (preferredType ?? '').toLowerCase();
    if (t == 'infografis' || t == 'infographic') return ['infographic'];
    if (t == 'brs' || t == 'pressrelease') {
      return ['pressrelease', 'infographic'];
    }
    if (t == 'publikasi' || t == 'publication') return ['publication'];
    return ['infographic', 'pressrelease', 'publication'];
  }

  static List<String> _buildSearchKeywords(String title) {
    const stopWords = {
      'kota',
      'malang',
      'pada',
      'bulan',
      'tahun',
      'yang',
      'dan',
      'di',
      'ke',
      'dari',
      'untuk',
      'sebesar',
      'mencapai',
      'mengalami',
      'persen',
      'poin',
      'dibandingkan',
      'sebelumnya',
      'pad',
      'tahun-on-tahun',
      'year',
      'on',
      'januari',
      'februari',
      'maret',
      'april',
      'mei',
      'juni',
      'juli',
      'agustus',
      'september',
      'oktober',
      'november',
      'desember',
    };
    final cleaned = title
        .replaceAll(RegExp(r'\(\d+\)\d{4}-\d{2}-\d{2}$'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .toLowerCase();
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toList();

    final queries = <String>[];
    if (tokens.length >= 3) {
      queries.add(tokens.take(3).join(' '));
    }
    if (tokens.length >= 2) {
      queries.add(tokens.take(2).join(' '));
    }
    if (tokens.isNotEmpty) {
      queries.add(tokens.first);
    }
    if (queries.isEmpty && title.trim().isNotEmpty) {
      queries.add(title.trim().split(RegExp(r'\s+')).take(2).join(' '));
    }
    return queries.toSet().toList();
  }

  static Set<String> _normalizeTokens(String text) {
    return text
        .replaceAll(RegExp(r'\(\d+\)\d{4}-\d{2}-\d{2}$'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .toSet();
  }

  static double _scoreTitleMatch(String a, String b) {
    final normA = a
        .replaceAll(RegExp(r'\(\d+\)\d{4}-\d{2}-\d{2}$'), '')
        .trim()
        .toLowerCase();
    final normB = b
        .replaceAll(RegExp(r'\(\d+\)\d{4}-\d{2}-\d{2}$'), '')
        .trim()
        .toLowerCase();
    if (normA.isEmpty || normB.isEmpty) return 0.0;
    if (normA == normB) return 1.0;

    final setA = _normalizeTokens(a);
    final setB = _normalizeTokens(b);
    if (setA.isEmpty || setB.isEmpty) return 0.0;

    final intersection = setA.intersection(setB);
    if (intersection.isEmpty) return 0.0;

    final coverageA = intersection.length / setA.length;
    final coverageB = intersection.length / setB.length;
    double score = (coverageA + coverageB) / 2.0;

    // Bonus/penalti jika ada angka tahun atau kode unik (misal 2026, ST2023)
    final numTokensA = setA.where((w) => RegExp(r'\d').hasMatch(w)).toSet();
    final numTokensB = setB.where((w) => RegExp(r'\d').hasMatch(w)).toSet();
    if (numTokensA.isNotEmpty && numTokensB.isNotEmpty) {
      final numOverlap = numTokensA.intersection(numTokensB).length;
      if (numOverlap > 0) {
        score += 0.15;
      } else {
        score -= 0.15;
      }
    }
    return score.clamp(0.0, 1.0);
  }
}

/// Model hasil parsing data BPS Web API
class BpsDataResult {
  final String title; // Nama variabel (misal: "Laju Pertumbuhan Ekonomi")
  final String unit; // Satuan (misal: "Persen")
  final String source; // Sumber data (misal: "BPS Kota Malang")
  final int decimal; // Jumlah digit desimal bawaan metadata variabel BPS
  final List<String> years; // Label tahun ["2016", "2017", ...]
  final List<BpsSeriesData> series; // Data per kategori/vervar

  BpsDataResult({
    required this.title,
    required this.unit,
    required this.source,
    this.decimal = 2,
    required this.years,
    required this.series,
  });

  factory BpsDataResult.fromJson(
    Map<String, dynamic> json, {
    int maxYears = 10,
  }) {
    if (json['var'] is! List ||
        json['vervar'] is! List ||
        json['tahun'] is! List) {
      throw const FormatException('Struktur JSON indikator BPS tidak lengkap.');
    }

    // 1. Parse metadata variabel
    final varList = json['var'] as List<dynamic>;
    final title =
        varList.isNotEmpty ? (varList[0]['label'] ?? '').toString() : '';
    final unit =
        varList.isNotEmpty ? (varList[0]['unit'] ?? '').toString() : '';
    final source =
        varList.isNotEmpty ? (varList[0]['note'] ?? '').toString() : '';
    final int decimal = (varList.isNotEmpty && varList[0]['decimal'] is num)
        ? (varList[0]['decimal'] as num).toInt()
        : 2;

    // 2. Parse kategori/vervar (kolom data)
    final vervarList = json['vervar'] as List<dynamic>;
    final vervarLabels =
        vervarList.map((v) => (v['label'] ?? '').toString()).toList();
    final vervarVals =
        vervarList.map((v) => (v['val'] ?? '').toString()).toList();

    // 3. Parse turvar dan turtahun untuk penyusunan kunci komposit BPS
    final turvarList = (json['turvar'] is List)
        ? (json['turvar'] as List<dynamic>)
        : const <dynamic>[];
    final turvarVals = turvarList.isNotEmpty
        ? turvarList.map((t) => (t['val'] ?? '0').toString()).toList()
        : <String>['0'];

    final turtahunList = (json['turtahun'] is List)
        ? (json['turtahun'] as List<dynamic>)
        : const <dynamic>[];
    final turtahunVals = turtahunList.isNotEmpty
        ? turtahunList.map((t) => (t['val'] ?? '0').toString()).toList()
        : <String>['0'];

    // 4. Parse tahun
    final tahunList = json['tahun'] as List<dynamic>;
    final allYears =
        tahunList.map((t) => (t['label'] ?? '').toString()).toList();
    final allYearVals =
        tahunList.map((t) => (t['val'] ?? '').toString()).toList();

    // Ambil N tahun terakhir saja
    final startIdx =
        allYears.length > maxYears ? allYears.length - maxYears : 0;
    final years = allYears.sublist(startIdx);
    final yearVals = allYearVals.sublist(startIdx);

    // 5. Parse datacontent
    final datacontentRaw = json['datacontent'];
    final Map<String, dynamic> datacontent = (datacontentRaw is Map)
        ? Map<String, dynamic>.from(datacontentRaw)
        : {};
    final List<dynamic> dcValuesList = datacontent.values.toList();

    // 6. Buat series data per vervar
    final varId = varList.isNotEmpty ? varList[0]['val'].toString() : '';
    final totalYearsCount = allYears.length;
    final bool canUsePositionalFallback =
        dcValuesList.length == (vervarVals.length * totalYearsCount);
    final List<BpsSeriesData> series = [];

    for (int v = 0; v < vervarVals.length; v++) {
      final List<double?> values = [];
      final vervarVal = vervarVals[v];

      for (int y = 0; y < yearVals.length; y++) {
        final yearVal = yearVals[y];
        final fullYearIndex = startIdx + y;

        double? value;

        // Metrik 1: Kunci komposit resmi BPS Web API
        // Skema utama: {vervarVal}{varId}{turvarVal}{tahunVal}{turtahunVal}
        final List<String> possibleKeys = [];
        for (final tv in turvarVals) {
          for (final tt in turtahunVals.reversed) {
            possibleKeys.add('$vervarVal$varId$tv$yearVal$tt');
          }
        }
        possibleKeys.addAll([
          '$vervarVal${varId}0${yearVal}0',
          '$vervarVal$varId$yearVal',
          '$varId$vervarVal$yearVal',
          '$vervarVal${varId}0$yearVal',
          '$varId${vervarVal}0$yearVal',
          '$varId${vervarVal}000015$yearVal',
        ]);

        for (final k in possibleKeys) {
          if (datacontent.containsKey(k)) {
            final raw = datacontent[k];
            if (raw != null) {
              value = (raw is num)
                  ? raw.toDouble()
                  : double.tryParse(raw.toString());
              if (value != null) break;
            }
          }
        }

        // Metrik 2: Fallback urutan posisi HANYA jika matriks datacontent lengkap
        // (mencegah pergeseran tahun/seri ketika terdapat tahun dengan nilai kosong)
        if (value == null && canUsePositionalFallback) {
          final posIndex = (v * totalYearsCount) + fullYearIndex;
          if (posIndex >= 0 && posIndex < dcValuesList.length) {
            final raw = dcValuesList[posIndex];
            if (raw != null) {
              value = (raw is num)
                  ? raw.toDouble()
                  : double.tryParse(raw.toString());
            }
          }
        }

        values.add(value);
      }
      series.add(BpsSeriesData(label: vervarLabels[v], values: values));
    }

    return BpsDataResult(
      title: title,
      unit: unit,
      source: source,
      decimal: decimal,
      years: years,
      series: series,
    );
  }
}

/// Data satu seri/kolom (misal: "Kota Malang", "Jawa Timur", "Indonesia")
class BpsSeriesData {
  final String label;
  final List<double?> values;

  BpsSeriesData({required this.label, required this.values});
}

/// Pasangan URL cover dan konten segar hasil resolusi BPS Web API
class BpsMediaUrls {
  final String? coverUrl;
  final String? contentUrl;

  const BpsMediaUrls({this.coverUrl, this.contentUrl});
}
