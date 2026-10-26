import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mboistats/theme.dart';
import 'package:mboistats/services/logger_service.dart';
import 'package:mboistats/utils/download_helper.dart';

/// Native Flutter PDF Viewer (dev-v2-native)
/// Menggunakan SfPdfViewer.memory & Local Disk Caching
/// disertai validasi integritas berkas dan manajemen lifecycle.
class GlobalPDFViewer extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final String? contentType;
  final String? contentId;

  const GlobalPDFViewer({
    Key? key,
    required this.pdfUrl,
    this.title = 'Dokumen Statistik',
    this.contentType,
    this.contentId,
  }) : super(key: key);

  @override
  State<GlobalPDFViewer> createState() => _GlobalPDFViewerState();
}

class _GlobalPDFViewerState extends State<GlobalPDFViewer> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  http.Client? _httpClient;
  bool _isDownloading = false;
  Uint8List? _pdfBytes;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _httpClient?.close();
    _pdfViewerController.dispose();
    super.dispose();
  }

  /// Memeriksa header maqic bytes '%PDF' untuk memastikan berkas bukan HTML/korup
  bool _isValidPdfBytes(Uint8List bytes) {
    return bytes.length > 4 &&
        bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46; // F
  }

  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final hashName = 'pdf_cache_${widget.pdfUrl.hashCode}.pdf';
    return File('${dir.path}/$hashName');
  }

  Future<void> _invalidateCacheFile() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Memeriksa cache lokal atau mengunduh langsung bytes PDF dengan User-Agent BPS
  Future<void> _loadPdf() async {
    try {
      final file = await _getCacheFile();

      if (await file.exists() && (await file.length()) > 0) {
        final bytes = await file.readAsBytes();
        if (_isValidPdfBytes(bytes)) {
          if (mounted) {
            setState(() {
              _pdfBytes = bytes;
              _isLoading = false;
            });
          }
          return;
        } else {
          // Berkas lokal rusak/tidak valid: hapus sebelum mencoba unduh ulang
          await file.delete();
        }
      }

      _httpClient?.close();
      _httpClient = http.Client();

      // Unduh dari server dengan User-Agent resmi agar tidak diblokir oleh WebAPI BPS
      final response = await _httpClient!.get(
        Uri.parse(widget.pdfUrl),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/pdf,*/*',
        },
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200 && _isValidPdfBytes(response.bodyBytes)) {
        await file.writeAsBytes(response.bodyBytes);
        if (mounted) {
          setState(() {
            _pdfBytes = response.bodyBytes;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = response.statusCode == 200
                ? 'Berkas yang diterima bukan dokumen PDF yang valid.'
                : 'Gagal memuat dokumen (HTTP ${response.statusCode})';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal mengunduh berkas: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadPdf() async {
    setState(() {
      _isDownloading = true;
    });

    try {
      await DownloadHelper.downloadDocument(
        context,
        url: widget.pdfUrl,
        fileName: widget.title,
        contentType: widget.contentType,
        contentId: widget.contentId,
        sectorCategory: LoggerService.classifySector(widget.title),
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Terjadi kesalahan: $e",
        toastLength: Toast.LENGTH_SHORT,
        backgroundColor: blueNormal,
        textColor: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          _isDownloading
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'Unduh PDF',
                  onPressed: _downloadPdf,
                ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: blueNormal),
                  SizedBox(height: 16),
                  Text(
                    'Memuat dokumen PDF...',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          : _pdfBytes != null
              ? SfPdfViewer.memory(
                  _pdfBytes!,
                  controller: _pdfViewerController,
                  onDocumentLoadFailed:
                      (PdfDocumentLoadFailedDetails details) async {
                    await _invalidateCacheFile();
                    if (mounted) {
                      setState(() {
                        _pdfBytes = null;
                        _errorMessage = details.description;
                      });
                    }
                  },
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage ?? 'Dokumen tidak dapat dimuat.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: blueNormal,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _errorMessage = null;
                            });
                            _loadPdf();
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
