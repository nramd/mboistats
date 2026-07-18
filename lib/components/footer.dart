import 'package:flutter/material.dart';

class Footer extends StatefulWidget {
  const Footer({Key? key}) : super(key: key);

  @override
  _FooterState createState() => _FooterState();
}

class _FooterState extends State<Footer> {
  int _selectedIndex = 0; // Indeks awal (Beranda)

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Ambil nama rute halaman yang sedang aktif
    final currentRoute = ModalRoute.of(context)!.settings.name;

    // Tentukan _selectedIndex berdasarkan nama rute halaman yang sedang aktif
    if (currentRoute == '/berita') {
      _selectedIndex = 1;
    } else if (currentRoute == '/contact') {
      _selectedIndex = 2;
    } else {
      _selectedIndex = 0; // Default ke Beranda jika tidak ada rute yang cocok
    }
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) {
      return; // Jangan lakukan apa-apa jika menekan tab yang saat ini aktif
    }

    switch (index) {
      case 0:
        // Kembali ke Beranda dan bersihkan semua tumpukan halaman sebelumnya
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
        break;
      case 1:
        // Ganti rute aktif jika kita berpindah di antara halaman tab non-beranda
        if (_selectedIndex != 0) {
          Navigator.of(context).pushReplacementNamed('/berita');
        } else {
          Navigator.of(context).pushNamed('/berita');
        }
        break;
      case 2:
        if (_selectedIndex != 0) {
          Navigator.of(context).pushReplacementNamed('/contact');
        } else {
          Navigator.of(context).pushNamed('/contact');
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex != 0) {
          // Jika ditekan tombol kembali di luar Beranda, kembali ke Beranda dan bersihkan stack
          Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
          return false;
        }
        return true; // Keluar dari aplikasi jika sudah berada di Beranda
      },
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: [
          BottomNavigationBarItem(
            icon: Icon(
              Icons.home,
              color: _selectedIndex == 0 ? Colors.blue : null, // Home
            ),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.newspaper_outlined,
              color: _selectedIndex == 1 ? Colors.blue : null, // News
            ),
            label: 'BRS',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.contacts,
              color: _selectedIndex == 2 ? Colors.blue : null, // Contact
            ),
            label: 'Kontak',
          ),
        ],
      ),
    );
  }
  }

