
import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:saf/saf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mboistats/services/logger_service.dart';
import 'package:mboistats/components/global_pdf_viewer.dart';
import 'package:mboistats/utils/download_helper.dart';
import '../theme.dart';

class CarouselPublikasi extends StatefulWidget {
  const CarouselPublikasi({Key? key}) : super(key: key);

  @override
  _CarouselPublikasiState createState() => _CarouselPublikasiState();
}

class _CarouselPublikasiState extends State<CarouselPublikasi> {
  late Saf saf;
  List<Map<String, dynamic>> dataPublikasi = [];

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    try {
      final response = await Supabase.instance.client
          .from('contents')
          .select()
          .or('content_type.eq.publikasi,action_type.eq.view_publikasi_pdf')
          .order('created_at', ascending: false)
          .limit(10);
      final list = List<Map<String, dynamic>>.from(response);
      if (list.isNotEmpty) {
        if (mounted) {
          setState(() {
            dataPublikasi = list.map((item) => {
              'id': item['id']?.toString(),
              'title': item['title'] ?? item['item_name'],
              'cover': item['cover_url'],
              'pdf': item['content_url'],
              'rl_date': item['created_at']?.toString().split('T')[0],
            }).toList();
          });
        }
        return;
      }
    } catch (_) {}

    // Fallback BPS API
    try {
      final response = await http.get(Uri.parse('http://webapi.bps.go.id/v1/api/list/domain/3573/model/publication/lang/ind/page/1/key/9db89e91c3c142df678e65a78c4e547f'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final publications = (data['data'][1] as List).cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() {
            dataPublikasi = publications;
          });
        }
      }
    } catch (error) {}
  }

  @override
  Widget build(BuildContext context) {
    return dataPublikasi.isEmpty
        ? const Center(
      child: CircularProgressIndicator(),
    )
        : Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(
            top: 24.0,
            bottom: 16.0,
          ),
          child: Text(
            'PUBLIKASI',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        CarouselSlider(
          options: CarouselOptions(
            height: 450,
            enlargeCenterPage: true,
            autoPlay: true,
            aspectRatio: 3 / 4,
          ),
          items: dataPublikasi.map((item) {
            return GestureDetector(
              onTap: () {
                openDownloadConfirmation(
                  context,
                  item['pdf'] ?? '',
                  item['title'] ?? '',
                  item['abstract'] ?? '',
                  item['rl_date'] ?? '',
                  item['size'] ?? '',
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      spreadRadius: 2,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(
                    item['cover'],
                    width: MediaQuery.of(context).size.width,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void openDownloadConfirmation(BuildContext context, String tautan, String judul, String deskripsi, String tglrilis, String ukuran) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            judul,
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
                        parse(HtmlUnescape().convert(deskripsi)).body?.text ?? '',
                        style: TextStyle(fontSize: 13, color: dark1),
                        textAlign: TextAlign.justify,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Ukuran Berkas: ${ukuran.replaceAll('.', ',')}",
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey
                        ),
                      ),
                      Text(
                        "Tanggal Rilis: $tglrilis",
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                  child: const Text("Tutup"),
                ),
                const SizedBox(width: 16), // space between buttons
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await downloadAndShowConfirmation(context, tautan, judul);
                  },
                  child: const Text("Unduh"),
                ),
                const SizedBox(width: 16), // space between buttons
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    final item = dataPublikasi.firstWhere((x) => x['pdf'] == tautan, orElse: () => {});
                    final coverUrl = item['cover'] as String?;
                    final contentId = item['id']?.toString();
                    LoggerService.logActivity(
                      actionType: 'view_publikasi_pdf',
                      contentType: 'publikasi',
                      contentId: contentId,
                      sectorCategory: LoggerService.classifySector(judul),
                      itemName: judul,
                      coverUrl: coverUrl,
                      contentUrl: tautan,
                    );
                    openPdfDirectly(context, tautan, judul);
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

  Future<void> downloadAndShowConfirmation(BuildContext context, String pdfUrl, String fileName) async {
    final item = dataPublikasi.firstWhere((x) => x['pdf'] == pdfUrl, orElse: () => {});
    final coverUrl = item['cover'] as String?;
    final contentId = item['id']?.toString();

    await DownloadHelper.downloadDocument(
      context,
      url: pdfUrl,
      fileName: fileName,
      contentId: contentId,
      coverUrl: coverUrl,
      sectorCategory: LoggerService.classifySector(fileName),
    );
  }
  void openPdfDirectly(BuildContext context, String pdfUrl, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GlobalPDFViewer(pdfUrl: pdfUrl, title: title),
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
      body: SfPdfViewer.network(
        pdfUrl,
      ),
    );
  }
}
