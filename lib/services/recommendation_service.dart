import 'dart:async';
import 'package:mboistats/services/logger_service.dart';

class RecommendedItem {
  final String title;
  final String route;
  final String icon;
  final String description;

  RecommendedItem({
    required this.title,
    required this.route,
    required this.icon,
    required this.description,
  });
}

class RecommendationService {
  /// Mendapatkan daftar rekomendasi sektoral secara dinamis.
  /// Saat SSO siap di Checkpoint 3, rekan tim Anda dapat mengirimkan [userId]
  /// untuk mengambil data rekomendasi dari API Machine Learning atau tabel Supabase `user_recommendations`.
  static Future<List<RecommendedItem>> getSectorRecommendations({String? userId}) async {
    // 1. Dapatkan Device ID secara otomatis untuk keperluan mapping
    final deviceId = await LoggerService.getDeviceId();
    
    print('Recommendation Requested -> Device: $deviceId | User ID: ${userId ?? "Anonymous"}');
    
    // Simulasikan latency network API (500 ms)
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. Data Placeholder / Mock Recommendations (Bisa disesuaikan oleh rekan tim Anda nantinya)
    // Di sini kita merekomendasikan dua halaman terpopuler berdasarkan profil demografi Kota Malang
    return [
      RecommendedItem(
        title: 'Penduduk Menurut Kecamatan',
        route: '/PendudukKec',
        icon: 'kependudukan_2.png',
        description: 'Informasi jumlah penduduk di tiap kecamatan Kota Malang terbaru.',
      ),
      RecommendedItem(
        title: 'Tingkat Kemiskinan',
        route: '/TingkatKemiskinan',
        icon: 'kemiskinan.png', // Fallback icon jika ada
        description: 'Persentase dan perkembangan tingkat kemiskinan dari tahun ke tahun.',
      ),
    ];
  }
}
