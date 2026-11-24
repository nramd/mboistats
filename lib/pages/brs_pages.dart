import 'package:flutter/material.dart';
import 'package:mboistats/components/bps_cover_image.dart';
import 'package:mboistats/components/footer.dart';
import 'package:mboistats/components/global_pdf_viewer.dart';
import 'package:mboistats/services/bps_api_service.dart';
import 'package:mboistats/theme.dart';
import 'package:saf/saf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:html/parser.dart' show parse;
import 'package:mboistats/services/logger_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mboistats/utils/download_helper.dart';

class BeritaPages extends StatefulWidget {
  const BeritaPages({Key? key}) : super(key: key);

  @override
  _BeritaPageState createState() => _BeritaPageState();
}

class _BeritaPageState extends State<BeritaPages> {
  late Saf saf;
  List<Map<String, dynamic>> dataBRS = [];
  int currentPage = 1;
  bool isLoading = false;
  bool hasMore = true;
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
    fetchDataBRS();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !isLoading && hasMore) {
        fetchDataBRS();
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
    final dateA = (a['rl_date'] ?? a['created_at'] ?? '').toString();
    final dateB = (b['rl_date'] ?? b['created_at'] ?? '').toString();
    final comp = dateB.compareTo(dateA);
    if (comp != 0) return comp;

    final yearA = _extractYear((a['title'] ?? '').toString());
    final yearB = _extractYear((b['title'] ?? '').toString());
    return yearB.compareTo(yearA);
  }

  Future<void> fetchDataBRS() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
    });

    // 1. Jika tanpa filter sektor, utamakan BPS WebAPI live agar cover & PDF selalu HTTP 200
    if (_selectedSector == 'semua') {
      try {
        final brs = await BpsApiService.fetchLiveContentList(
          model: 'pressrelease',
          page: currentPage,
        );
        if (mounted) {
          setState(() {
            if (brs.isNotEmpty) {
              dataBRS.addAll(brs.map((item) => {
                'id': item['id']?.toString(),
                'title': item['title'] ?? '',
                'thumbnail': item['cover_url'] ?? item['thumbnail'] ?? '',
                'pdf': item['content_url'] ?? item['pdf'] ?? '',
                'rl_date': item['rl_date'],
                'abstract': item['abstract'],
                'size': item['size'],
                'created_at': item['created_at'],
              }));
              dataBRS.sort(_compareByNewest);
              currentPage++;
              if (brs.length < 10) {
                hasMore = false;
              }
            } else {
              hasMore = false;
            }
            isLoading = false;
          });
        }
        return;
      } catch (e) {
        debugPrint("Error fetching BRS from BPS API: $e");
      }
    }

    // 2. Fallback / filter sektor menggunakan Supabase contents
    try {
      final from = (currentPage - 1) * 20;
      final to = from + 19;

      var query = Supabase.instance.client
          .from('contents')
          .select(_selectedSector != 'semua' ? '*, contents_has_categories!inner(categories_id_category)' : '*')
          .or('content_type.eq.brs,action_type.eq.view_brs_pdf');

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
            dataBRS.addAll(list.map((item) => {
              'id': item['id']?.toString(),
              'title': item['title'] ?? item['item_name'],
              'thumbnail': item['cover_url'],
              'pdf': item['content_url'],
              'created_at': item['created_at'],
            }));
            currentPage++;
          }
          if (list.length < 20) {
            hasMore = false;
          }
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching BRS from Supabase: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  String truncateText(String text, int maxLength) {
    if (text.length > maxLength) {
      return '${text.substring(0, maxLength)}...';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayList = dataBRS;

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
                    'Berita Resmi Statistik',
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
                            dataBRS.clear();
                            currentPage = 1;
                            hasMore = true;
                          });
                          fetchDataBRS();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Grid content
            Expanded(
              child: displayList.isEmpty && isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : displayList.isEmpty
                      ? Center(
                          child: Text(
                            'Tidak ada BRS di sektor ini.',
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
                          itemCount: displayList.length + (hasMore && _selectedSector == 'semua' ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == displayList.length) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final item = displayList[index];
                            final title = (item["title"] ?? '').toString();
                            final thumbnail = (item['thumbnail'] ?? '').toString();
                            final pdfUrl = (item["pdf"] ?? '').toString();

                            return InkWell(
                              onTap: () => showDownloadDialog(context, pdfUrl, index),
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
                                        imageUrl: thumbnail,
                                        title: title,
                                        contentType: 'brs',
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        fallback: Center(
                                          child: Icon(
                                            Icons.newspaper,
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

  void showDownloadDialog(BuildContext context, String pdfUrl, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            dataBRS[index]["title"],
            textAlign: TextAlign.center,
            style: bold16.copyWith(color: dark1),
          ),
          content: SingleChildScrollView(
            child: Row(
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dataBRS[index]["abstract"] != null && (dataBRS[index]["abstract"] as String).isNotEmpty
                            ? (parse(HtmlUnescape().convert(dataBRS[index]["abstract"])).body?.text ?? '')
                            : (dataBRS[index]["title"] ?? ''),
                        style: TextStyle(fontSize: 13, color: dark1),
                        textAlign: TextAlign.justify,
                      ),
                      const SizedBox(height: 8),
                      if (dataBRS[index]["size"] != null)
                        Text(
                          "Ukuran Berkas: ${(dataBRS[index]["size"] as String).replaceAll('.', ',')}",
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey
                          ),
                        ),
                      if (dataBRS[index]["rl_date"] != null || dataBRS[index]["created_at"] != null)
                        Text(
                          "Tanggal Rilis: ${dataBRS[index]["rl_date"] ?? dataBRS[index]["created_at"]?.toString().split('T')[0] ?? ''}",
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Tutup"),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    String fileName = dataBRS[index]["title"];
                    final contentId = dataBRS[index]["id"] as String?;
                    final coverUrl = dataBRS[index]["thumbnail"] as String?;
                    await downloadAndShowConfirmation(
                      context,
                      pdfUrl,
                      fileName,
                      contentId: contentId,
                      coverUrl: coverUrl,
                    );
                  },
                  child: const Text("Unduh"),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    String fileName = dataBRS[index]["title"];
                    final contentId = dataBRS[index]["id"] as String?;
                    LoggerService.logActivity(
                      actionType: 'view_brs_pdf',
                      contentType: 'brs',
                      contentId: contentId,
                      sectorCategory: LoggerService.classifySector(fileName),
                      itemName: fileName,
                      coverUrl: dataBRS[index]["thumbnail"],
                      contentUrl: pdfUrl,
                    );
                    openPdfDirectly(context, pdfUrl, fileName, contentId: contentId);
                  },
                  child: const Text("Buka PDF"),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> downloadAndShowConfirmation(
    BuildContext context,
    String pdfUrl,
    String fileName, {
    String? contentId,
    String? coverUrl,
  }) async {
    final item = dataBRS.firstWhere((x) => x['pdf'] == pdfUrl, orElse: () => {});
    final resolvedCover = coverUrl ?? item['thumbnail'] as String?;
    final resolvedId = contentId ?? item['id'] as String?;

    await DownloadHelper.downloadDocument(
      context,
      url: pdfUrl,
      fileName: fileName,
      contentType: 'brs',
      contentId: resolvedId,
      coverUrl: resolvedCover,
      sectorCategory: LoggerService.classifySector(fileName),
    );
  }

  void openPdfDirectly(BuildContext context, String pdfUrl, String title, {String? contentId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GlobalPDFViewer(
          pdfUrl: pdfUrl,
          title: title,
          contentType: 'brs',
          contentId: contentId,
        ),
      ),
    );
  }
}

class PDFViewer extends StatelessWidget {
  final String pdfUrl;

  const PDFViewer({Key? key, required this.pdfUrl}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Viewer'),
      ),
      body: SfPdfViewer.network(pdfUrl),
    );
  }
}