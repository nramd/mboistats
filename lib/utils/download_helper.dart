import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_file_downloader/flutter_file_downloader.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:mboistats/services/logger_service.dart';
import 'package:mboistats/theme.dart';

/// Helper terpusat untuk menangani proses pengunduhan berkas dokumen (.pdf) dan infografis (.jpeg)
/// Mendukung penuh Android & iOS, meminta izin sistem OS asli, auto-rename format anti-.php,
/// dan otomatis mencatat aktivitas unduh ke Supabase / Dashboard Monitoring.
class DownloadHelper {
  /// Memeriksa dan meminta izin penyimpanan/notifikasi sistem OS asli
  static Future<bool> checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        if (androidInfo.version.sdkInt >= 33) {
          // Android 13+ memerlukan izin notifikasi
          final notifStatus = await Permission.notification.status;
          if (notifStatus.isDenied) {
            await Permission.notification.request();
          }
          return true;
        } else {
          // Android 12 ke bawah memerlukan izin WRITE/READ external storage
          var storageStatus = await Permission.storage.status;
          if (storageStatus.isDenied) {
            storageStatus = await Permission.storage.request();
          }
          return storageStatus.isGranted;
        }
      } catch (e) {
        print('Error checking permissions: $e');
        return true;
      }
    }
    return true;
  }

  /// Membersihkan nama berkas dari karakter ilegal dan memaksakan ekstensi target
  static String sanitizeFileName(String originalName, String targetExtension) {
    // 1. Ganti karakter yang dilarang pada sistem berkas (misal / \ : * ? " < > |)
    String clean = originalName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    // 2. Hapus ekstensi lama yang menempel jika ada (misal .php, .tmp, .pdf, .jpg, .jpeg, .png)
    clean = clean.replaceAll(RegExp(r'\.(php|tmp|pdf|jpg|jpeg|png)$', caseSensitive: false), '');

    // 3. Trim spasi berlebih
    clean = clean.trim();
    if (clean.isEmpty) {
      clean = 'berkas_mboistats';
    }

    // 4. Pastikan ekstensi target diawali titik
    final ext = targetExtension.startsWith('.') ? targetExtension : '.$targetExtension';
    return '$clean$ext';
  }

  /// Melakukan auto-rename pada berkas di storage lokal jika terunduh dengan akhiran .php
  static void _autoRenameIfPhp(String path, String targetExtension) {
    try {
      final decodedPath = Uri.decodeFull(path);
      final ext = targetExtension.startsWith('.') ? targetExtension : '.$targetExtension';

      if (decodedPath.toLowerCase().endsWith('.php') || !decodedPath.toLowerCase().endsWith(ext.toLowerCase())) {
        final file = File(decodedPath);
        final newPath = decodedPath.replaceAll(RegExp(r'\.php$', caseSensitive: false), ext);
        if (file.existsSync()) {
          file.renameSync(newPath);
          print('Auto-rename sukses: $decodedPath -> $newPath');
          return;
        }

        // Coba gunakan path mentah jika path ter-encode karakter khusus
        final rawFile = File(path);
        final rawNewPath = path.replaceAll(RegExp(r'\.php$', caseSensitive: false), ext);
        if (rawFile.existsSync()) {
          rawFile.renameSync(rawNewPath);
          print('Auto-rename sukses (raw): $path -> $rawNewPath');
        }
      }
    } catch (e) {
      print('Auto-rename file error: $e');
    }
  }

  /// Mengunduh dokumen publikasi atau BRS secara pasti berformat .pdf (lintas platform iOS & Android)
  static Future<void> downloadDocument(
    BuildContext context, {
    required String url,
    required String fileName,
    String? contentId,
    String? coverUrl,
    String? sectorCategory,
    String? contentType,
    bool showConfirmation = false,
  }) async {
    final lower = fileName.toLowerCase();
    final isBrsTitle = lower.contains('berita resmi') ||
        lower.contains('brs') ||
        lower.contains('inflasi') ||
        lower.contains('perkembangan') ||
        lower.contains('luas panen') ||
        lower.contains('pariwisata') ||
        lower.contains('ekspor') ||
        lower.contains('impor');

    final resolvedContentType = contentType ?? (isBrsTitle ? 'brs' : 'publikasi');

    await _executeDownload(
      context: context,
      url: url,
      fileName: fileName,
      targetExtension: '.pdf',
      fileTypeDesc: 'dokumen PDF',
      contentType: resolvedContentType,
      contentId: contentId,
      coverUrl: coverUrl,
      sectorCategory: sectorCategory,
    );
  }

  /// Mengunduh infografis secara pasti berformat .jpeg (lintas platform iOS & Android)
  static Future<void> downloadInfografis(
    BuildContext context, {
    required String url,
    required String fileName,
    String? contentId,
    String? coverUrl,
    bool showConfirmation = false,
  }) async {
    await _executeDownload(
      context: context,
      url: url,
      fileName: fileName,
      targetExtension: '.jpeg',
      fileTypeDesc: 'gambar Infografis (JPEG)',
      contentType: 'infografis',
      contentId: contentId,
      coverUrl: coverUrl ?? url,
      sectorCategory: 'infografis',
    );
  }

  /// Mesin pengunduh terpadu lintas platform (iOS & Android)
  static Future<void> _executeDownload({
    required BuildContext context,
    required String url,
    required String fileName,
    required String targetExtension,
    required String fileTypeDesc,
    required String contentType,
    String? contentId,
    String? coverUrl,
    String? sectorCategory,
  }) async {
    if (url.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Tautan berkas tidak tersedia.',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) {
      Fluttertoast.showToast(
        msg: 'Izin penyimpanan ditolak. Tidak dapat mengunduh berkas.',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    final safeName = sanitizeFileName(fileName, targetExtension);

    // 1. Catat log aktivitas unduhan ke Supabase secara instan agar langsung termonitor di Dashboard
    final downloadAction = (contentType == 'brs')
        ? 'download_brs'
        : (contentType == 'publikasi'
            ? 'download_publikasi'
            : (contentType == 'infografis'
                ? 'download_infografis'
                : 'download_file'));

    LoggerService.logActivity(
      actionType: downloadAction,
      sectorCategory: sectorCategory ?? LoggerService.classifySector(fileName),
      itemName: fileName,
      contentType: contentType,
      contentId: contentId,
      coverUrl: coverUrl,
      contentUrl: url,
    );

    Fluttertoast.showToast(
      msg: 'Memulai pengunduhan $fileTypeDesc...',
      backgroundColor: blueNormal,
      textColor: Colors.white,
    );

    if (Platform.isIOS) {
      await _downloadOnIos(
        url: url,
        safeName: safeName,
        fileName: fileName,
      );
    } else {
      await _downloadOnAndroid(
        url: url,
        safeName: safeName,
        fileName: fileName,
        targetExtension: targetExtension,
      );
    }
  }

  /// Logika download khusus iOS: simpan ke Dokumen Aplikasi (tersedia di app Files) & buka via Quick Look
  static Future<void> _downloadOnIos({
    required String url,
    required String safeName,
    required String fileName,
  }) async {
    HttpClient? client;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$safeName';
      final file = File(filePath);

      // 1. Periksa apakah berkas sudah pernah di-cache oleh viewer (GlobalPDFViewer)
      final cachedFile = File('${dir.path}/pdf_cache_${url.hashCode}.pdf');
      if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
        await cachedFile.copy(filePath);
      } else {
        // 2. Unduh menggunakan HttpClient dengan streaming langsung ke berkas (tanpa buffer RAM & tanpa timeout paksa)
        client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 30);

        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        );
        request.headers.set(HttpHeaders.acceptHeader, '*/*');

        final response = await request.close();
        if (response.statusCode == 200) {
          final sink = file.openWrite();
          await response.pipe(sink);
          await sink.flush();
          await sink.close();
        } else {
          throw Exception('Server BPS mengembalikan HTTP ${response.statusCode}');
        }
      }

      if (await file.exists() && (await file.length()) > 0) {
        Fluttertoast.showToast(
          msg: 'Berkas "$safeName" berhasil diunduh.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: blueNormal,
          textColor: Colors.white,
        );

        // Buka dokumen via native iOS preview (Quick Look dengan tombol Simpan ke File / Bagikan)
        await OpenFile.open(filePath);
      } else {
        throw Exception('Ukuran berkas 0 byte.');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Gagal mengunduh berkas di iOS: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      client?.close();
    }
  }

  /// Logika download Android: gunakan FileDownloader dengan fallback HTTP streaming
  static Future<void> _downloadOnAndroid({
    required String url,
    required String safeName,
    required String fileName,
    required String targetExtension,
  }) async {
    try {
      await FileDownloader.downloadFile(
        url: url,
        name: safeName,
        downloadDestination: DownloadDestinations.publicDownloads,
        onDownloadCompleted: (String path) {
          _autoRenameIfPhp(path, targetExtension);

          Fluttertoast.showToast(
            msg: 'Berkas "$safeName" berhasil disimpan di folder Download.',
            toastLength: Toast.LENGTH_LONG,
            backgroundColor: blueNormal,
            textColor: Colors.white,
          );
        },
        onDownloadError: (String error) async {
          // Fallback jika DownloadManager terhambat
          await _fallbackHttpDownloadAndroid(
            url: url,
            safeName: safeName,
            fileName: fileName,
            targetExtension: targetExtension,
          );
        },
      );
    } catch (e) {
      await _fallbackHttpDownloadAndroid(
        url: url,
        safeName: safeName,
        fileName: fileName,
        targetExtension: targetExtension,
      );
    }
  }

  /// Fallback HTTP streaming download untuk Android jika plugin FileDownloader terhambat
  static Future<void> _fallbackHttpDownloadAndroid({
    required String url,
    required String safeName,
    required String fileName,
    required String targetExtension,
  }) async {
    HttpClient? client;
    try {
      Directory? downloadDir;
      final publicDownload = Directory('/storage/emulated/0/Download');
      if (await publicDownload.exists()) {
        downloadDir = publicDownload;
      } else {
        downloadDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final filePath = '${downloadDir.path}/$safeName';
      final file = File(filePath);

      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      request.headers.set(HttpHeaders.acceptHeader, '*/*');

      final response = await request.close();
      if (response.statusCode == 200) {
        final sink = file.openWrite();
        await response.pipe(sink);
        await sink.flush();
        await sink.close();
        _autoRenameIfPhp(filePath, targetExtension);

        Fluttertoast.showToast(
          msg: 'Berkas "$safeName" berhasil disimpan.',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: blueNormal,
          textColor: Colors.white,
        );
      } else {
        throw Exception('Server BPS mengembalikan HTTP ${response.statusCode}');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Gagal mengunduh berkas: $e',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      client?.close();
    }
  }
}
