
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:saf/saf.dart';
import 'package:mboistats/utils/download_helper.dart';
import '../theme.dart';

class CarouselInfografis extends StatefulWidget {
  const CarouselInfografis({Key? key}) : super(key: key);

  @override
  _CarouselInfografisState createState() => _CarouselInfografisState();
}

class _CarouselInfografisState extends State<CarouselInfografis> {
  late Saf saf;
  List<Map<String, dynamic>> dataInfografis = [];

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    try {
      final response = await http.get(Uri.parse(
          'https://webapi.bps.go.id/v1/api/list/domain/3573/model/infographic/lang/ind/domain/3573/key/9db89e91c3c142df678e65a78c4e547f'),);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final infographic =
        (data['data'][1] as List).cast<Map<String, dynamic>>();
        setState(() {
          dataInfografis = infographic;
        });
      } else {
        throw Exception('Gagal mendapatkan data.');
      }
    } catch (error) {

    }
  }

  @override
  Widget build(BuildContext context) {
    return dataInfografis.isEmpty
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
            'INFOGRAFIS',
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
          items: dataInfografis.map((item) {
            return GestureDetector(
              onTap: () {
                openDownloadConfirmation(
                  context,
                  item['img'] ?? '',
                  item['title'] ?? '',
                  item['date'] ?? '',
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
                    item['img'],
                    width: MediaQuery
                        .of(context)
                        .size
                        .width,
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

  void openDownloadConfirmation(BuildContext context, String tautan,
      String judul, String tglrilis) {
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
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.network(
                        tautan,
                        fit: BoxFit.fill,
                        errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.image_not_supported),
                      ),
                      Text(
                        "Tanggal Rilis: $tglrilis",
                        textAlign: TextAlign.center,
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
              ],
            ),
          ],

        );
      },
    );
  }

  Future<void> downloadAndShowConfirmation(BuildContext context, String imgUrl,
      String fileName) async {
    await DownloadHelper.downloadInfografis(
      context,
      url: imgUrl,
      fileName: fileName,
      coverUrl: imgUrl,
    );
  }
}
