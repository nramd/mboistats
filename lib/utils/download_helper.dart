import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_file_downloader/flutter_file_downloader.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:html/parser.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:mboistats/components/bps_cover_image.dart';
import 'package:mboistats/components/global_pdf_viewer.dart';
import 'package:mboistats/services/bps_api_service.dart';
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
        debugPrint('Error checking permissions: $e');
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
    clean = clean.replaceAll(
        RegExp(r'\.(php|tmp|pdf|jpg|jpeg|png)$', caseSensitive: false), '');

    // 3. Trim spasi berlebih
    clean = clean.trim();
    if (clean.isEmpty) {
      clean = 'berkas_mboistats';
    }

    // 4. Pastikan ekstensi target diawali titik
    final ext =
        targetExtension.startsWith('.') ? targetExtension : '.$targetExtension';
    return '$clean$ext';
  }

  /// Melakukan auto-rename pada berkas di storage lokal jika terunduh dengan akhiran .php
  static void _autoRenameIfPhp(String path, String targetExtension) {
    try {
      final decodedPath = Uri.decodeFull(path);
      final ext = targetExtension.startsWith('.')
          ? targetExtension
          : '.$targetExtension';

      if (decodedPath.toLowerCase().endsWith('.php') ||
          !decodedPath.toLowerCase().endsWith(ext.toLowerCase())) {
        final file = File(decodedPath);
        final newPath = decodedPath.replaceAll(
            RegExp(r'\.php$', caseSensitive: false), ext);
        if (file.existsSync()) {
          file.renameSync(newPath);
          debugPrint('Auto-rename sukses: $decodedPath -> $newPath');
          return;
        }

        // Coba gunakan path mentah jika path ter-encode karakter khusus
        final rawFile = File(path);
        final rawNewPath =
            path.replaceAll(RegExp(r'\.php$', caseSensitive: false), ext);
        if (rawFile.existsSync()) {
          rawFile.renameSync(rawNewPath);
          debugPrint('Auto-rename sukses (raw): $path -> $rawNewPath');
        }
      }
    } catch (e) {
      debugPrint('Auto-rename file error: $e');
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

    final resolvedContentType =
        contentType ?? (isBrsTitle ? 'brs' : 'publikasi');

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

  /// Wrapper kompatibilitas untuk kode lama yang memanggil downloadFile
  static Future<void> downloadFile({
    required BuildContext context,
    required String fileUrl,
    required String fileName,
    required String fileTypeForToast,
    required bool isPublikasi,
  }) async {
    if (isPublikasi) {
      await downloadDocument(context, url: fileUrl, fileName: fileName);
    } else {
      await downloadInfografis(context, url: fileUrl, fileName: fileName);
    }
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
        contentType: contentType,
      );
    } else {
      await _downloadOnAndroid(
        url: url,
        safeName: safeName,
        fileName: fileName,
        targetExtension: targetExtension,
        contentType: contentType,
      );
    }
  }

  static Future<HttpClientResponse> _openStreamWithRetry(
    HttpClient client, {
    required String url,
    required String fileName,
    required String contentType,
  }) async {
    Future<HttpClientResponse> sendReq(String targetUrl) async {
      final request = await client.getUrl(Uri.parse(targetUrl));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      return await request.close();
    }

    var response = await sendReq(url);
    if (response.statusCode != 200) {
      await response.drain<void>();
      final fresh = await BpsApiService.resolveFreshMediaUrls(
        title: fileName,
        preferredType: contentType,
        forceRefresh: true,
      );
      final freshUrl = fresh?.contentUrl ?? fresh?.coverUrl;
      if (freshUrl != null && freshUrl.isNotEmpty) {
        response = await sendReq(freshUrl);
      }
    }
    return response;
  }

  /// Logika download khusus iOS: simpan ke Dokumen Aplikasi (tersedia di app Files) & buka via Quick Look
  static Future<void> _downloadOnIos({
    required String url,
    required String safeName,
    required String fileName,
    required String contentType,
  }) async {
    HttpClient? client;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$safeName';
      final file = File(filePath);

      // 1. Periksa apakah berkas sudah pernah di-cache oleh viewer
      final cachedPdf = File('${dir.path}/pdf_cache_${url.hashCode}.pdf');
      final cachedImg = File('${dir.path}/img_cache_${url.hashCode}.img');
      if (await cachedPdf.exists() && (await cachedPdf.length()) > 0) {
        await cachedPdf.copy(filePath);
      } else if (await cachedImg.exists() && (await cachedImg.length()) > 0) {
        await cachedImg.copy(filePath);
      } else {
        // 2. Unduh menggunakan HttpClient dengan streaming langsung ke berkas
        client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 30);

        final response = await _openStreamWithRetry(
          client,
          url: url,
          fileName: fileName,
          contentType: contentType,
        );
        if (response.statusCode == 200) {
          final sink = file.openWrite();
          await response.pipe(sink);
          await sink.flush();
          await sink.close();
        } else {
          throw Exception(
              'Server BPS mengembalikan HTTP ${response.statusCode}');
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
    required String contentType,
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
            contentType: contentType,
          );
        },
      );
    } catch (e) {
      await _fallbackHttpDownloadAndroid(
        url: url,
        safeName: safeName,
        fileName: fileName,
        targetExtension: targetExtension,
        contentType: contentType,
      );
    }
  }

  /// Fallback HTTP streaming download untuk Android jika plugin FileDownloader terhambat
  static Future<void> _fallbackHttpDownloadAndroid({
    required String url,
    required String safeName,
    required String fileName,
    required String targetExtension,
    required String contentType,
  }) async {
    HttpClient? client;
    try {
      Directory? downloadDir;
      final publicDownload = Directory('/storage/emulated/0/Download');
      if (await publicDownload.exists()) {
        downloadDir = publicDownload;
      } else {
        downloadDir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      }

      final filePath = '${downloadDir.path}/$safeName';
      final file = File(filePath);

      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final response = await _openStreamWithRetry(
        client,
        url: url,
        fileName: fileName,
        contentType: contentType,
      );
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

  /// Membuka PDF di viewer utama terpadu (GlobalPDFViewer)
  static void openPdfDirectly(
    BuildContext context,
    String pdfUrl, {
    String title = 'Dokumen Statistik',
    String? contentType,
    String? contentId,
  }) {
    if (pdfUrl.isEmpty) {
      Fluttertoast.showToast(msg: "URL PDF tidak valid.");
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GlobalPDFViewer(
          pdfUrl: pdfUrl,
          title: title,
          contentType: contentType,
          contentId: contentId,
        ),
      ),
    );
  }

  /// Menampilkan dialog terpusat untuk item BRS & Publikasi (digunakan di Favorit & item list)
  static void showPublikasiDialog({
    required BuildContext context,
    required String title,
    required String postType, // 'brs' atau 'publikasi'
    required String pdfUrl,
    required String abstract,
    required String size,
    required String releaseDate,
    required Function onToggleFavorite,
    required bool isCurrentlyFavorited,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContextInner) {
        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            return AlertDialog(
              title: Text(
                title,
                textAlign: TextAlign.center,
                style: bold16.copyWith(color: dark1),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      parse(HtmlUnescape().convert(abstract)).body?.text ?? '',
                      style: TextStyle(fontSize: 13, color: dark1),
                      textAlign: TextAlign.justify,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Ukuran Berkas: ${size.replaceAll('.', ',')}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      "Tanggal Rilis: $releaseDate",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actionsPadding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContextInner),
                          child: const Text("Tutup"),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(dialogContextInner);
                            await downloadDocument(
                              context,
                              url: pdfUrl,
                              fileName: title,
                              contentType: postType,
                            );
                          },
                          child: const Text("Unduh"),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dialogContextInner);
                            openPdfDirectly(
                              context,
                              pdfUrl,
                              title: title,
                              contentType: postType,
                            );
                          },
                          child: const Text("Buka PDF"),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            onToggleFavorite();
                            setDialogState(() {
                              isCurrentlyFavorited = !isCurrentlyFavorited;
                            });
                          },
                          icon: Icon(
                            isCurrentlyFavorited
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: isCurrentlyFavorited
                                ? Colors.red
                                : Colors.grey[600],
                            size: 20,
                          ),
                          label: Text(
                            isCurrentlyFavorited ? 'Favorit' : 'Favoritkan',
                            style: TextStyle(
                              color: isCurrentlyFavorited
                                  ? Colors.red
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                )
              ],
            );
          },
        );
      },
    );
  }

  /// Menampilkan dialog terpusat untuk item Infografis (digunakan di Favorit & item list)
  static void showInfografisDialog({
    required BuildContext context,
    required String title,
    required String imageUrl,
    required String releaseDate,
    required Function onToggleFavorite,
    required bool isCurrentlyFavorited,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContextInner) {
        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            return AlertDialog(
              title: Text(
                title,
                textAlign: TextAlign.center,
                style: bold16.copyWith(color: dark1),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(dialogContextInner);
                        Navigator.pushNamed(
                          context,
                          '/image_viewer',
                          arguments: {
                            'imageUrl': imageUrl,
                            'title': title,
                          },
                        );
                      },
                      child: BpsCoverImage(
                        imageUrl: imageUrl,
                        title: title,
                        contentType: 'infografis',
                        fit: BoxFit.contain,
                        fallback: const Icon(Icons.broken_image,
                            size: 100, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Tanggal Rilis: $releaseDate",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actionsPadding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContextInner),
                          child: const Text("Tutup"),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(dialogContextInner);
                            await downloadInfografis(
                              context,
                              url: imageUrl,
                              fileName: title,
                            );
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.download, size: 18),
                              SizedBox(width: 4),
                              Text("Unduh"),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dialogContextInner);
                            Navigator.pushNamed(
                              context,
                              '/image_viewer',
                              arguments: {
                                'imageUrl': imageUrl,
                                'title': title,
                              },
                            );
                          },
                          child: const Text("Lihat"),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            onToggleFavorite();
                            setDialogState(() {
                              isCurrentlyFavorited = !isCurrentlyFavorited;
                            });
                          },
                          icon: Icon(
                            isCurrentlyFavorited
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: isCurrentlyFavorited
                                ? Colors.red
                                : Colors.grey[600],
                            size: 20,
                          ),
                          label: Text(
                            isCurrentlyFavorited ? 'Favorit' : 'Favoritkan',
                            style: TextStyle(
                              color: isCurrentlyFavorited
                                  ? Colors.red
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                )
              ],
            );
          },
        );
      },
    );
  }
}
