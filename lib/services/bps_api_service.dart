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
    final directUrl =
        '$_baseUrl/model/data/domain/$_domain/var/$varId/th/1:/key/$_apiKey';
    final response = await httpClient
        .get(Uri.parse(directUrl))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP Error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> &&
        decoded['status'] == 'OK' &&
        decoded['var'] is List) {
      return decoded;
    }

    // Fallback: ambil daftar th_id terbaru melalui endpoint model/th lalu unduh per 3 tahun
    final thUrl = '$_baseUrl/model/th/domain/$_domain/var/$varId/key/$_apiKey';
    final thResp = await httpClient
        .get(Uri.parse(thUrl))
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
        .toList()
      ..sort();

    if (thIds.isEmpty) {
      throw const FormatException('Rentang tahun indikator BPS kosong.');
    }

    final selectedThIds = thIds.length > maxYears
        ? thIds.sublist(thIds.length - maxYears)
        : thIds;

    Map<String, dynamic>? mergedJson;
    final List<Map<String, dynamic>> mergedTahun = [];
    final Map<String, dynamic> mergedDataContent = {};

    for (int i = 0; i < selectedThIds.length; i += 3) {
      final chunk = selectedThIds.sublist(
        i,
        (i + 3 < selectedThIds.length) ? i + 3 : selectedThIds.length,
      );
      final thParam =
          chunk.length == 1 ? '${chunk.first}' : '${chunk.first}:${chunk.last}';
      final chunkUrl =
          '$_baseUrl/model/data/domain/$_domain/var/$varId/th/$thParam/key/$_apiKey';

      final chunkResp = await httpClient
          .get(Uri.parse(chunkUrl))
          .timeout(const Duration(seconds: 10));

      if (chunkResp.statusCode == 200) {
        final chunkMap = jsonDecode(chunkResp.body);
        if (chunkMap is Map<String, dynamic> && chunkMap['status'] == 'OK') {
          mergedJson ??= Map<String, dynamic>.from(chunkMap);
          if (chunkMap['tahun'] is List) {
            for (final t in chunkMap['tahun'] as List) {
              if (t is Map) {
                mergedTahun.add(Map<String, dynamic>.from(t));
              }
            }
          }
          if (chunkMap['datacontent'] is Map) {
            mergedDataContent.addAll(
              Map<String, dynamic>.from(chunkMap['datacontent'] as Map),
            );
          }
        }
      }
    }

    if (mergedJson == null) {
      throw Exception('Gagal mengunduh rentang tahun indikator BPS.');
    }

    mergedJson['tahun'] = mergedTahun;
    mergedJson['datacontent'] = mergedDataContent;
    return mergedJson;
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
