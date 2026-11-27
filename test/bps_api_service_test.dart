import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mboistats/services/bps_api_service.dart';

void main() {
  group('BpsDataResult.fromJson validation', () {
    test('Maps composite keys accurately for LPE (varId 434)', () {
      final sampleJson = {
        'var': [
          {
            'val': 434,
            'label':
                'Laju Pertumbuhan Ekonomi di Kota Malang, Jawa Timur, dan Indonesia',
            'unit': 'Persen',
            'decimal': 2,
            'note': 'Sumber: Badan Pusat Statistik (BPS)',
          },
        ],
        'turvar': [
          {'val': '0', 'label': 'Tidak ada'},
        ],
        'vervar': [
          {'val': 1, 'label': 'Kota Malang'},
          {'val': 2, 'label': 'Jawa Timur'},
          {'val': 3, 'label': 'Indonesia'},
        ],
        'tahun': [
          {'val': 123, 'label': '2023'},
          {'val': 124, 'label': '2024'},
          {'val': 125, 'label': '2025'},
        ],
        'turtahun': [
          {'val': 0, 'label': 'Tahun'},
        ],
        'datacontent': {
          '143401230': 6.07,
          '143401240': 5.41,
          '143401250': 5.92,
          '243401230': 4.95,
          '243401240': 4.93,
          '243401250': 5.33,
          '343401230': 5.05,
          '343401240': 5.03,
          '343401250': 5.11,
        },
      };

      final result = BpsDataResult.fromJson(sampleJson, maxYears: 10);
      expect(result.unit, 'Persen');
      expect(result.decimal, 2);
      expect(result.years, ['2023', '2024', '2025']);
      expect(result.series.length, 3);
      expect(result.series[0].label, 'Kota Malang');
      expect(result.series[0].values, [6.07, 5.41, 5.92]);
      expect(result.series[1].values, [4.95, 4.93, 5.33]);
      expect(result.series[2].values, [5.05, 5.03, 5.11]);
    });

    test('Preserves null on missing datacontent entry without shifting series',
        () {
      final sparseJson = {
        'var': [
          {
            'val': 431,
            'label': 'Garis Kemiskinan',
            'unit': 'Rupiah (Rp.)',
            'decimal': 0,
            'note': 'Sumber: BPS',
          },
        ],
        'turvar': [
          {'val': '0', 'label': 'Tidak ada'},
        ],
        'vervar': [
          {'val': 1, 'label': 'Kota Malang'},
          {'val': 2, 'label': 'Jawa Timur'},
        ],
        'tahun': [
          {'val': 123, 'label': '2023'},
          {'val': 124, 'label': '2024'},
        ],
        'turtahun': [
          {'val': 0, 'label': 'Tahun'},
        ],
        'datacontent': {
          // 143101230 sengaja dikosongkan (missing value pada 2023 Kota Malang)
          '143101240': 706341,
          '243101230': 507286,
          '243101240': 536122,
        },
      };

      final result = BpsDataResult.fromJson(sparseJson, maxYears: 10);
      expect(result.decimal, 0);
      expect(result.series[0].values, [null, 706341.0]);
      expect(result.series[1].values, [507286.0, 536122.0]);
    });
  });

  group('BpsApiService live list & fresh URL recovery', () {
    test('Normalizes live infographic items and strips BPS date suffix',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'data': [
              {'page': 1, 'pages': 1},
              [
                {
                  'title':
                      'Tingkat Penghunian Kamar Hotel di Kota Malang(1)2026-10-01',
                  'img': 'https://webapi.bps.go.id/cover.php?f=AQAD_COVER',
                  'dl': 'https://webapi.bps.go.id/download.php?f=AQAD_DL',
                  'date': '2026-10-01',
                },
              ],
            ],
          }),
          200,
        );
      });

      final list = await BpsApiService.fetchLiveContentList(
        model: 'infographic',
        page: 99,
        forceRefresh: true,
        client: mockClient,
      );

      expect(list.length, 1);
      expect(
        list.first['title'],
        'Tingkat Penghunian Kamar Hotel di Kota Malang',
      );
      expect(
        list.first['cover_url'],
        'https://webapi.bps.go.id/cover.php?f=AQAD_COVER',
      );
      expect(
        list.first['content_url'],
        'https://webapi.bps.go.id/download.php?f=AQAD_DL',
      );
    });

    test('Resolves fresh URLs by title when Supabase URL has expired',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/keyword/')) {
          return http.Response(
            jsonEncode({
              'status': 'OK',
              'data': [
                {'page': 1, 'pages': 1},
                [
                  {
                    'title': 'Infografis ST2023 - I Kota Malang',
                    'img': 'https://webapi.bps.go.id/cover.php?f=AQAD_ST_IMG',
                    'dl': 'https://webapi.bps.go.id/download.php?f=AQAD_ST_DL',
                  },
                ],
              ],
            }),
            200,
          );
        }
        return http.Response('{"status":"Error"}', 404);
      });

      final resolved = await BpsApiService.resolveFreshMediaUrls(
        title: 'Infografis ST2023 - I Kota Malang',
        preferredType: 'infografis',
        client: mockClient,
      );

      expect(resolved, isNotNull);
      expect(
        resolved!.coverUrl,
        'https://webapi.bps.go.id/cover.php?f=AQAD_ST_IMG',
      );
      expect(
        resolved.contentUrl,
        'https://webapi.bps.go.id/download.php?f=AQAD_ST_DL',
      );
    });

    test('forceRefresh bypasses cached expired URL and fetches a new token',
        () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'data': [
              {'page': 1, 'pages': 1},
              [
                {
                  'title':
                      'Indeks Pembangunan Manusia (IPM) Kota Malang tahun 2026',
                  'thumbnail':
                      'https://webapi.bps.go.id/cover.php?f=AQAD_C_$callCount',
                  'pdf':
                      'https://webapi.bps.go.id/download.php?f=AQAD_PDF_$callCount',
                },
              ],
            ],
          }),
          200,
        );
      });

      final first = await BpsApiService.resolveFreshMediaUrls(
        title: 'Indeks Pembangunan Manusia (IPM) Kota Malang tahun 2026',
        preferredType: 'brs',
        client: mockClient,
      );
      final refreshed = await BpsApiService.resolveFreshMediaUrls(
        title: 'Indeks Pembangunan Manusia (IPM) Kota Malang tahun 2026',
        preferredType: 'brs',
        forceRefresh: true,
        client: mockClient,
      );

      expect(first, isNotNull);
      expect(refreshed, isNotNull);
      expect(refreshed!.contentUrl, isNot(equals(first!.contentUrl)));
      expect(refreshed.contentUrl, contains('AQAD_PDF_'));
    });

    test('fetchData resolves model/th and chunks <= 3 years with bpsHeaders',
        () async {
      final requestedPaths = <String>[];
      final mockClient = MockClient((request) async {
        requestedPaths.add(request.url.path);
        expect(
          request.headers['User-Agent'],
          BpsApiService.bpsHeaders['User-Agent'],
        );

        if (request.url.path.contains('/model/th/')) {
          return http.Response(
            jsonEncode({
              'status': 'OK',
              'data': [
                {'page': 1, 'pages': 1},
                [
                  {'th_id': 125, 'th': '2025'},
                  {'th_id': 124, 'th': '2024'},
                  {'th_id': 123, 'th': '2023'},
                  {'th_id': 120, 'th': '2020'},
                ],
              ],
            }),
            200,
          );
        }

        if (request.url.path.contains('/th/120/')) {
          return http.Response(
            jsonEncode({
              'status': 'OK',
              'var': [
                {'val': 51, 'label': 'Penduduk', 'unit': 'Jiwa', 'decimal': 0},
              ],
              'turvar': [
                {'val': 26, 'label': 'Laki-Laki'},
              ],
              'vervar': [
                {'val': 1, 'label': '0 - 4'},
              ],
              'tahun': [
                {'val': 120, 'label': '2020'},
              ],
              'turtahun': [
                {'val': 0, 'label': 'Tahun'},
              ],
              'datacontent': {'151261200': 25000},
            }),
            200,
          );
        }

        if (request.url.path.contains('/th/123:125/')) {
          return http.Response(
            jsonEncode({
              'status': 'OK',
              'var': [
                {'val': 51, 'label': 'Penduduk', 'unit': 'Jiwa', 'decimal': 0},
              ],
              'turvar': [
                {'val': 26, 'label': 'Laki-Laki'},
              ],
              'vervar': [
                {'val': 1, 'label': '0 - 4'},
              ],
              'tahun': [
                {'val': 123, 'label': '2023'},
                {'val': 124, 'label': '2024'},
                {'val': 125, 'label': '2025'},
              ],
              'turtahun': [
                {'val': 0, 'label': 'Tahun'},
              ],
              'datacontent': {
                '151261230': 27687,
                '151261240': 26863,
                '151261250': 22525,
              },
            }),
            200,
          );
        }

        return http.Response('{"status":"error"}', 400);
      });

      final result = await BpsApiService.fetchData(
        varId: 51,
        maxYears: 10,
        forceRefresh: true,
        client: mockClient,
      );

      expect(requestedPaths.any((p) => p.contains('/th/1:/')), isFalse);
      expect(requestedPaths.any((p) => p.contains('/th/120/')), isTrue);
      expect(requestedPaths.any((p) => p.contains('/th/123:125/')), isTrue);
      expect(result.years, ['2020', '2023', '2024', '2025']);
      expect(result.series.single.values, [25000.0, 27687.0, 26863.0, 22525.0]);
    });
  });
}
