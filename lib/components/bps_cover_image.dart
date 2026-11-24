import 'package:flutter/material.dart';
import 'package:mboistats/services/bps_api_service.dart';

/// Menampilkan gambar sampul BPS dengan pemulihan otomatis apabila
/// URL lama dari Supabase mengembalikan error (misal HTTP 400 token kedaluwarsa).
class BpsCoverImage extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String? contentType;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget fallback;

  const BpsCoverImage({
    Key? key,
    required this.imageUrl,
    required this.title,
    this.contentType,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    required this.fallback,
  }) : super(key: key);

  @override
  State<BpsCoverImage> createState() => _BpsCoverImageState();
}

class _BpsCoverImageState extends State<BpsCoverImage> {
  late String _effectiveUrl;
  bool _hasAttemptedRecovery = false;
  bool _failedFinal = false;

  @override
  void initState() {
    super.initState();
    _effectiveUrl = widget.imageUrl;
    if (_effectiveUrl.isEmpty) {
      _tryRecoverUrl();
    }
  }

  @override
  void didUpdateWidget(covariant BpsCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.title != widget.title) {
      _effectiveUrl = widget.imageUrl;
      _hasAttemptedRecovery = false;
      _failedFinal = false;
      if (_effectiveUrl.isEmpty) {
        _tryRecoverUrl();
      }
    }
  }

  Future<void> _tryRecoverUrl() async {
    if (_hasAttemptedRecovery) {
      if (mounted && !_failedFinal) {
        setState(() => _failedFinal = true);
      }
      return;
    }
    _hasAttemptedRecovery = true;

    final resolved = await BpsApiService.resolveFreshMediaUrls(
      title: widget.title,
      preferredType: widget.contentType,
    );
    final freshUrl = resolved?.coverUrl ?? resolved?.contentUrl ?? '';
    if (!mounted) return;

    if (freshUrl.isNotEmpty && freshUrl != _effectiveUrl) {
      setState(() {
        _effectiveUrl = freshUrl;
        _failedFinal = false;
      });
    } else {
      setState(() {
        _failedFinal = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_effectiveUrl.isEmpty || _failedFinal) {
      return widget.fallback;
    }

    return Image.network(
      _effectiveUrl,
      headers: BpsApiService.bpsHeaders,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (context, error, stackTrace) {
        if (!_hasAttemptedRecovery) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryRecoverUrl();
          });
        } else if (!_failedFinal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _failedFinal = true);
            }
          });
        }
        return widget.fallback;
      },
    );
  }
}
