import 'package:flutter/material.dart';
import 'package:mboistats/theme.dart';
import 'package:mboistats/utils/download_helper.dart';

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
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  Future<void> _downloadImage() async {
    setState(() {
      _isDownloading = true;
    });
    try {
      await DownloadHelper.downloadInfografis(
        context,
        url: widget.imageUrl,
        fileName: widget.title,
        coverUrl: widget.imageUrl,
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
        title: Text(widget.title, style: pjsBold16.copyWith(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isDownloading)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: _downloadImage,
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text('Gagal memuat gambar', style: pjsMedium12.copyWith(color: Colors.white)),
              );
            },
          ),
        ),
      ),
    );
  }
}
