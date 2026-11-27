import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:mboistats/theme.dart';
import 'package:mboistats/services/bps_api_service.dart';
import 'package:mboistats/utils/download_helper.dart';

/// Native Flutter Infographic Viewer (dev-v2-native)
/// Menggunakan InteractiveViewer & Local Disk Caching (img_cache_{hash}.img)
/// disertai validasi integritas citra dan manajemen lifecycle.
class GlobalImageViewer extends StatefulWidget {
  final String imageUrl;
  final String title;

  const GlobalImageViewer({
    Key? key,
    required this.imageUrl,
    this.title = 'Infografis',
  }) : super(key: key);

  @override
  State<GlobalImageViewer> createState() => _GlobalImageViewerState();
}

class _GlobalImageViewerState extends State<GlobalImageViewer> {
  final TransformationController _transformationController =
      TransformationController();
  http.Client? _httpClient;
  late String _activeUrl;
  Uint8List? _imageBytes;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.imageUrl;
    _loadImage();
  }

  @override
  void dispose() {
    _httpClient?.close();
    _transformationController.dispose();
    super.dispose();
  }

  /// Memeriksa header magic bytes citra (JPEG, PNG, WebP, GIF)
  bool _isValidImageBytes(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    final isPng = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final isRiff = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46;
    final isGif = bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    return isJpeg || isPng || isRiff || isGif;
  }

  Future<File> _getCacheFile([String? url]) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = url ?? _activeUrl;
    final hashName = 'img_cache_${target.hashCode}.img';
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

  Future<http.Response> _fetchImageResponse(String url) {
    return _httpClient!.get(
      Uri.parse(url),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'image/*,*/*',
      },
    ).timeout(const Duration(seconds: 25));
  }

  Future<void> _loadImage() async {
    try {
      final file = await _getCacheFile(_activeUrl);

      if (await file.exists() && (await file.length()) > 0) {
        final bytes = await file.readAsBytes();
        if (_isValidImageBytes(bytes)) {
          if (mounted) {
            setState(() {
              _imageBytes = bytes;
              _isLoading = false;
            });
          }
          return;
        } else {
          await file.delete();
        }
      }

      _httpClient?.close();
      _httpClient = http.Client();

      http.Response? response;
      if (_activeUrl.isNotEmpty) {
        response = await _fetchImageResponse(_activeUrl);
      }

      // Jika URL lama dari Supabase atau cache sementara kedaluwarsa (HTTP 400), resolve ulang langsung dari WebAPI BPS
      if (response == null ||
          response.statusCode != 200 ||
          !_isValidImageBytes(response.bodyBytes)) {
        final fresh = await BpsApiService.resolveFreshMediaUrls(
          title: widget.title,
          preferredType: 'infografis',
          forceRefresh: true,
          client: _httpClient,
        );
        final candidates = <String>[
          if (fresh?.contentUrl != null && fresh!.contentUrl!.isNotEmpty)
            fresh.contentUrl!,
          if (fresh?.coverUrl != null && fresh!.coverUrl!.isNotEmpty)
            fresh.coverUrl!,
        ];
        for (final candidate in candidates) {
          final retryResp = await _fetchImageResponse(candidate);
          if (retryResp.statusCode == 200 &&
              _isValidImageBytes(retryResp.bodyBytes)) {
            _activeUrl = candidate;
            response = retryResp;
            break;
          }
        }
      }

      if (response != null &&
          response.statusCode == 200 &&
          _isValidImageBytes(response.bodyBytes)) {
        final validBytes = response.bodyBytes;
        final targetFile = await _getCacheFile(_activeUrl);
        await targetFile.writeAsBytes(validBytes);
        if (mounted) {
          setState(() {
            _imageBytes = validBytes;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          final status = response?.statusCode ?? 0;
          setState(() {
            _errorMessage = status == 200
                ? 'Berkas yang diterima bukan citra yang valid.'
                : 'Gagal memuat infografis (HTTP $status)';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal mengunduh citra: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadImage() async {
    setState(() {
      _isDownloading = true;
    });
    try {
      await DownloadHelper.downloadInfografis(
        context,
        url: _activeUrl,
        fileName: widget.title,
        coverUrl: _activeUrl,
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: pjsBold16.copyWith(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isDownloading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              tooltip: 'Unduh Infografis',
              onPressed: _downloadImage,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Memuat infografis...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            )
          : _imageBytes != null
              ? Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    panEnabled: true,
                    boundaryMargin: const EdgeInsets.all(20),
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      _imageBytes!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                          await _invalidateCacheFile();
                          if (mounted && _imageBytes != null) {
                            setState(() {
                              _imageBytes = null;
                              _errorMessage =
                                  'Berkas citra rusak atau gagal didekode.';
                            });
                          }
                        });
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage ?? 'Infografis tidak dapat dimuat.',
                          textAlign: TextAlign.center,
                          style: pjsMedium12.copyWith(
                              color: Colors.white, fontSize: 14),
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
                            _loadImage();
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
