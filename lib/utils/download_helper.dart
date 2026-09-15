import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_file_downloader/flutter_file_downloader.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:mboistats/services/logger_service.dart';
import 'package:mboistats/theme.dart';

/// Helper terpusat untuk menangani proses pengunduhan berkas dokumen (.pdf) dan infografis (.jpeg)
/// Dilengkapi dialog edukasi izin penyimpanan, pembersihan nama berkas, dan auto-rename jika server BPS mengembalikan berkas .php.
class DownloadHelper {
  /// Memeriksa dan meminta izin penyimpanan/notifikasi yang diperlukan sesuai versi OS
  static Future<bool> checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        if (androidInfo.version.sdkInt >= 33) {
          // Android 13+ memerlukan izin notifikasi agar status download bar muncul
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

  /// Menampilkan dialog edukasi izin penyimpanan kepada pengguna sebelum pengunduhan
  static Future<void> showDownloadConfirmationDialog(
    BuildContext context, {
    required String fileName,
    required String fileTypeDesc,
    required VoidCallback onConfirm,
  }) async {
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.file_download_outlined, color: blueNormal, size: 26),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Izin Penyimpanan Unduhan',
                style: pjsBold16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aplikasi MBOIStats memerlukan izin untuk menyimpan berkas $fileTypeDesc ini ke folder Download perangkat Anda.',
              style: pjsRegular14.copyWith(color: dark2),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 20, color: blueNormal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: pjsSemiBold12.copyWith(color: dark1),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Apakah Anda ingin melanjutkan pengunduhan?',
              style: pjsMedium14.copyWith(color: dark1),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Batal',
              style: pjsMedium14.copyWith(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: blueNormal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              onConfirm();
            },
            child: const Text(
              'Izinkan & Unduh',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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

  /// Mengunduh dokumen publikasi atau BRS secara pasti berformat .pdf
  static Future<void> downloadDocument(
    BuildContext context, {
    required String url,
    required String fileName,
    String? coverUrl,
    String? sectorCategory,
    bool showConfirmation = true,
  }) async {
    if (url.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Tautan dokumen tidak tersedia.',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    void executeDownload() async {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        Fluttertoast.showToast(
          msg: 'Izin penyimpanan ditolak. Tidak dapat mengunduh berkas.',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }

      final safeName = sanitizeFileName(fileName, '.pdf');

      Fluttertoast.showToast(
        msg: 'Memulai pengunduhan dokumen PDF...',
        backgroundColor: blueNormal,
        textColor: Colors.white,
      );

      try {
        await FileDownloader.downloadFile(
          url: url,
          name: safeName,
          downloadDestination: DownloadDestinations.publicDownloads,
          onDownloadCompleted: (String path) {
            _autoRenameIfPhp(path, '.pdf');

            // Catat log aktivitas ke Supabase
            LoggerService.logActivity(
              actionType: 'download_file',
              sectorCategory: sectorCategory ?? LoggerService.classifySector(fileName),
              itemName: fileName,
              coverUrl: coverUrl,
              contentUrl: url,
            );

            Fluttertoast.showToast(
              msg: 'Dokumen PDF "$safeName" berhasil disimpan di folder Download.',
              toastLength: Toast.LENGTH_LONG,
              backgroundColor: blueNormal,
              textColor: Colors.white,
            );
          },
          onDownloadError: (String error) {
            Fluttertoast.showToast(
              msg: 'Gagal mengunduh dokumen: $error',
              backgroundColor: Colors.red,
              textColor: Colors.white,
            );
          },
        );
      } catch (e) {
        Fluttertoast.showToast(
          msg: 'Terjadi kesalahan saat mengunduh: $e',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }

    if (showConfirmation) {
      await showDownloadConfirmationDialog(
        context,
        fileName: fileName,
        fileTypeDesc: 'dokumen PDF',
        onConfirm: executeDownload,
      );
    } else {
      executeDownload();
    }
  }

  /// Mengunduh infografis secara pasti berformat .jpeg
  static Future<void> downloadInfografis(
    BuildContext context, {
    required String url,
    required String fileName,
    String? coverUrl,
    bool showConfirmation = true,
  }) async {
    if (url.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Tautan gambar infografis tidak tersedia.',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    void executeDownload() async {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        Fluttertoast.showToast(
          msg: 'Izin penyimpanan ditolak. Tidak dapat mengunduh infografis.',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }

      final safeName = sanitizeFileName(fileName, '.jpeg');

      Fluttertoast.showToast(
        msg: 'Memulai pengunduhan infografis JPEG...',
        backgroundColor: blueNormal,
        textColor: Colors.white,
      );

      try {
        await FileDownloader.downloadFile(
          url: url,
          name: safeName,
          downloadDestination: DownloadDestinations.publicDownloads,
          onDownloadCompleted: (String path) {
            _autoRenameIfPhp(path, '.jpeg');

            // Catat log aktivitas ke Supabase
            LoggerService.logActivity(
              actionType: 'download_file',
              sectorCategory: 'infografis',
              itemName: fileName,
              coverUrl: coverUrl ?? url,
              contentUrl: url,
            );

            Fluttertoast.showToast(
              msg: 'Infografis "$safeName" berhasil disimpan di folder Download.',
              toastLength: Toast.LENGTH_LONG,
              backgroundColor: blueNormal,
              textColor: Colors.white,
            );
          },
          onDownloadError: (String error) {
            Fluttertoast.showToast(
              msg: 'Gagal mengunduh infografis: $error',
              backgroundColor: Colors.red,
              textColor: Colors.white,
            );
          },
        );
      } catch (e) {
        Fluttertoast.showToast(
          msg: 'Terjadi kesalahan saat mengunduh: $e',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }

    if (showConfirmation) {
      await showDownloadConfirmationDialog(
        context,
        fileName: fileName,
        fileTypeDesc: 'gambar Infografis (JPEG)',
        onConfirm: executeDownload,
      );
    } else {
      executeDownload();
    }
  }
}
