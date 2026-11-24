import 'package:flutter/material.dart';
import 'package:mboistats/components/bps_cover_image.dart';
import 'package:mboistats/components/footer.dart';
import 'package:mboistats/services/bps_api_service.dart';
import 'package:mboistats/services/logger_service.dart';
import 'package:mboistats/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InfografisFullPage extends StatefulWidget {
  const InfografisFullPage({Key? key}) : super(key: key);

  @override
  State<InfografisFullPage> createState() => _InfografisFullPageState();
}

class _InfografisFullPageState extends State<InfografisFullPage> {
  List<Map<String, dynamic>> _dataInfografis = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  String _selectedSector = 'semua';

  final List<Map<String, String>> _sectorFilters = const [
    {'key': 'semua', 'label': 'Semua Sektor'},
    {'key': 'pertanian', 'label': 'Pertanian'},
    {'key': 'perekonomian', 'label': 'Perekonomian'},
    {'key': 'tenaga_kerja', 'label': 'Tenaga Kerja'},
    {'key': 'ipm', 'label': 'IPM'},
    {'key': 'kemiskinan', 'label': 'Kemiskinan'},
    {'key': 'kependudukan', 'label': 'Kependudukan'},
    {'key': 'kesejahteraan', 'label': 'Kesejahteraan'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchDataInfografis();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore) {
        _fetchDataInfografis();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _extractYear(String title) {
    final matches = RegExp(r'\b(20\d{2}|19\d{2})\b').allMatches(title);
    if (matches.isNotEmpty) {
      return int.tryParse(matches.last.group(0) ?? '') ?? 0;
    }
    return 0;
  }

  int _compareByNewest(Map<String, dynamic> a, Map<String, dynamic> b) {
    final dateA = (a['date'] ?? a['created_at'] ?? '').toString();
    final dateB = (b['date'] ?? b['created_at'] ?? '').toString();
    final comp = dateB.compareTo(dateA);
    if (comp != 0) return comp;

    final yearA = _extractYear((a['title'] ?? '').toString());
    final yearB = _extractYear((b['title'] ?? '').toString());
    return yearB.compareTo(yearA);
  }

  List<Map<String, dynamic>> get _filteredInfografis {
    if (_selectedSector == 'semua') return _dataInfografis;
    return _dataInfografis.where((item) {
      final title = (item['title'] ?? '').toString().toLowerCase();
      final sector = LoggerService.classifySector(title).toLowerCase();
      return sector == _selectedSector.toLowerCase() ||
          title.contains(_selectedSector.toLowerCase());
    }).toList();
  }

  Future<void> _fetchDataInfografis() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    // 1. Jika tanpa filter sektor, utamakan BPS WebAPI live agar gambar selalu HTTP 200
    if (_selectedSector == 'semua') {
      try {
        final infografis = await BpsApiService.fetchLiveContentList(
          model: 'infographic',
          page: _currentPage,
        );
        if (mounted) {
          setState(() {
            if (infografis.isNotEmpty) {
              _dataInfografis.addAll(infografis.map((item) => {
                'id': item['id']?.toString(),
                'title': item['title'] ?? '',
                'img': item['cover_url'] ?? item['img'] ?? '',
                'dl': item['content_url'] ?? item['dl'] ?? item['img'] ?? '',
                'created_at': item['created_at'],
              }));
              _dataInfografis.sort(_compareByNewest);
              _currentPage++;
              if (infografis.length < 10) {
                _hasMore = false;
              }
            } else {
              _hasMore = false;
            }
            _isLoading = false;
          });
        }
        return;
      } catch (e) {
        debugPrint("Error fetching Infografis from BPS API: $e");
      }
    }

    // 2. Fallback / filter sektor menggunakan Supabase contents
    try {
      final from = (_currentPage - 1) * 20;
      final to = from + 19;

      var query = Supabase.instance.client
          .from('contents')
          .select(_selectedSector != 'semua' ? '*, contents_has_categories!inner(categories_id_category)' : '*')
          .or('content_type.eq.infografis,action_type.eq.download_file');

      const sectorToCategoryId = {
        'perekonomian': 1, 'tenaga_kerja': 2, 'ipm': 3,
        'kemiskinan': 4, 'kependudukan': 5, 'pertanian': 6, 'kesejahteraan': 7,
      };

      if (_selectedSector != 'semua' && sectorToCategoryId.containsKey(_selectedSector)) {
        query = query.eq('contents_has_categories.categories_id_category', sectorToCategoryId[_selectedSector]!);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(from, to);

      final list = List<Map<String, dynamic>>.from(response);

      if (mounted) {
        setState(() {
          if (list.isNotEmpty) {
            _dataInfografis.addAll(list.map((item) => {
              'id': item['id']?.toString(),
              'title': item['title'] ?? item['item_name'],
              'img': item['cover_url'],
              'dl': item['content_url'],
              'created_at': item['created_at'],
            }));
            _currentPage++;
          }
          if (list.length < 20) {
            _hasMore = false;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching Infografis from Supabase: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayList = _dataInfografis;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Custom header matching mockup: back arrow + title text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    icon: Image.asset(
                      'assets_v2/icons/back_arrow.png',
                      width: 24,
                      height: 24,
                      color: isDark ? blueLighter : blueHover,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Infografis',
                    style: pjsBold20.copyWith(
                      color: isDark ? blueLighter : blueHover,
                    ),
                  ),
                ],
              ),
            ),

            // Horizontal Sector Filter Chips
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: _sectorFilters.map((sector) {
                    final isSelected = _selectedSector == sector['key'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          sector['label']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white70 : dark1),
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: blueNormal,
                        backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? blueNormal : dark4,
                            width: 1,
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            _selectedSector = sector['key']!;
                            _dataInfografis.clear();
                            _currentPage = 1;
                            _hasMore = true;
                          });
                          _fetchDataInfografis();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Grid content
            Expanded(
              child: displayList.isEmpty && _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : displayList.isEmpty
                      ? Center(
                          child: Text(
                            'Tidak ada Infografis di sektor ini.',
                            style: pjsRegular14.copyWith(color: dark3),
                          ),
                        )
                      : GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 20,
                            childAspectRatio: 0.58,
                          ),
                          itemCount: displayList.length + (_hasMore && _selectedSector == 'semua' ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == displayList.length) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final item = displayList[index];
                            final title = (item['title'] ?? '').toString();
                            final imgUrl = (item['img'] ?? '').toString();

                            return InkWell(
                              onTap: () {
                                LoggerService.logActivity(
                                  actionType: 'download_file',
                                  contentType: 'infografis',
                                  contentId: item['id']?.toString(),
                                  sectorCategory: LoggerService.classifySector(title),
                                  itemName: title,
                                  coverUrl: imgUrl,
                                  contentUrl: imgUrl,
                                );
                                Navigator.pushNamed(context, '/image_viewer', arguments: {'imageUrl': imgUrl, 'title': title});
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      clipBehavior: Clip.hardEdge,
                                      child: BpsCoverImage(
                                        imageUrl: imgUrl,
                                        title: title,
                                        contentType: 'infografis',
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        fallback: Center(
                                          child: Icon(
                                            Icons.image,
                                            color: dark3,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    title,
                                    style: pjsRegular14.copyWith(
                                      color: isDark ? Colors.white : dark1,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const Footer(),
    );
  }
}
