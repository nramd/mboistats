import 'package:flutter/material.dart';
import 'package:mboistats/services/supabase_auth_service.dart';
import 'package:mboistats/services/supabase_db_service.dart';
import 'package:mboistats/theme.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mboistats/utils/download_helper.dart';

class FavoritPage extends StatefulWidget {
  const FavoritPage({Key? key}) : super(key: key);

  @override
  State<FavoritPage> createState() => _FavoritPageState();
}

class _FavoritPageState extends State<FavoritPage> {
  late final SupabaseDbService _dbService;

  @override
  void initState() {
    super.initState();
    _dbService = SupabaseDbService(SupabaseAuthService());
  }

  @override
  void dispose() {
    _dbService.dispose();
    super.dispose();
  }

  Widget _buildFavoriteItem(BuildContext context, Map<String, dynamic> item) {
    final String itemType = item['item_type'] ?? 'unknown'; 
    final bool isPublikasi = itemType == 'publikasi';
    final bool isInfografis = itemType == 'infografis';
    final bool isBrs = itemType == 'brs';

    final String title = item['title'] ?? 'Tanpa Judul';
    String imageUrl = '';
    String date = '';
    String typeLabel = 'Lainnya';
    Color typeColor = Colors.grey;

    if (isPublikasi) {
      imageUrl = item['cover'] ?? '';
      date = item['rl_date'] ?? 'N/A';
      typeLabel = 'Publikasi';
      typeColor = Colors.blue[700]!;
    } else if (isInfografis) {
      imageUrl = item['img'] ?? '';
      date = item['date'] ?? 'N/A';
      typeLabel = 'Infografis';
      typeColor = Colors.green[700]!;
    } else if (isBrs) {
      imageUrl = item['thumbnail'] ?? '';
      date = item['rl_date'] ?? 'N/A';
      typeLabel = 'BRS';
      typeColor = Colors.orange[700]!;
    } else {
      imageUrl = 'https://placehold.co/70x90/e0e0e0/9e9e9e?text=?';
      date = 'N/A';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: InkWell(
          onTap: () {
            _showItemDialog(context, item);
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.network(
                    imageUrl,
                    width: 70,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                        width: 70,
                        height: 90,
                        color: Colors.grey[200],
                        child: Icon(Icons.broken_image, color: Colors.grey[400])),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: typeColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: semibold14.copyWith(color: dark1),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Rilis: $date",
                        style: regular12_5.copyWith(color: dark3),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Favorit Saya'),
          leading: IconButton(
            icon: Image.asset('assets/icons/left-arrow.png', height: 25),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListenableBuilder(
          listenable: _dbService,
          builder: (context, child) {
            final favoriteItems = _dbService.favoriteItems;
            if (favoriteItems.isEmpty) {
              return Center(
                child: Text(
                  'Anda belum memiliki item favorit.',
                  style: regular14.copyWith(color: dark2),
                ),
              );
            }
            return ListView.builder(
              itemCount: favoriteItems.length,
              itemBuilder: (context, index) {
                return _buildFavoriteItem(context, favoriteItems[index]);
              },
            );
          },
        ),
      ),
    );
  }

  void _showItemDialog(
      BuildContext context,
      Map<String, dynamic> item) {
        
    final String itemType = item['item_type'] ?? 'unknown';
    final String itemTitle = item["title"] ?? "Tanpa Judul";

    final bool isPublikasi = itemType == 'publikasi';
    final bool isInfografis = itemType == 'infografis';
    final bool isBrs = itemType == 'brs';
    final String favoriteKey = _dbService.generateItemId(itemType, itemTitle);
    bool isCurrentlyFavorited = _dbService.favoriteIds.contains(favoriteKey);

    void toggleFavorite() async {
      try {
        bool newStatus = !isCurrentlyFavorited;
        
        if (newStatus) {
          Map<String, dynamic> itemToAdd = Map.from(item);
          itemToAdd.remove('id');
          itemToAdd.remove('user_id');
          itemToAdd.remove('created_at');
          itemToAdd.remove('item_id');
          itemToAdd['type'] = itemType;
          itemToAdd['title'] = itemTitle;
          await _dbService.addFavorite(itemToAdd);
          Fluttertoast.showToast(msg: "Ditambahkan ke favorit.");
        } else {
          await _dbService.removeFavorite(itemType, itemTitle);
          Fluttertoast.showToast(msg: "Dihapus dari favorit.");
        }
      } catch (e) {
        debugPrint("Error toggling favorite: $e");
      }
    }

    if (isPublikasi || isBrs) {
      DownloadHelper.showPublikasiDialog(
        context: context, 
        title: itemTitle, 
        postType: itemType, 
        pdfUrl: item["pdf"] ?? "", 
        abstract: item["abstract"] ?? "", 
        size: item["size"] ?? "N/A", 
        releaseDate: item["rl_date"] ?? item["date"] ?? "N/A", 
        onToggleFavorite: toggleFavorite, 
        isCurrentlyFavorited: isCurrentlyFavorited,
      );
    } else if (isInfografis) {
      DownloadHelper.showInfografisDialog(
        context: context, 
        title: itemTitle, 
        imageUrl: item['img'] ?? '', 
        releaseDate: item['date'] ?? 'N/A', 
        onToggleFavorite: toggleFavorite, 
        isCurrentlyFavorited: isCurrentlyFavorited,
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(itemTitle),
          content: const Text("Detail untuk tipe item ini tidak tersedia."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup"),
            )
          ],
        ),
      );
    }
  }
}