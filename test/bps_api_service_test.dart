import 'package:flutter_test/flutter_test.dart';
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
}
