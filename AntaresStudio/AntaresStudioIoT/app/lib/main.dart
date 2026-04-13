/// AntaresStudio IoT - Ana Uygulama Giriş Noktası
///
/// Antares Kapsül kontrol merkezi (Windows masaüstü).
/// Tema: Dark Mode, Modern, Industrial.
///
/// Navigasyon:
///   - Dashboard:  Canlı veriler + kamera akışı
///   - 3D Tarama:  Meshroom pipeline yönetimi
///   - Güncelleme: OTA firmware güncelleme
///
/// Provider yapısı:
///   - DeviceProvider: ESP32-CAM bağlantı ve sensör verileri
///   - ScanProvider:   Tarama orkestrasyon ve SD aktarım

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'providers/device_provider.dart';
import 'providers/scan_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/update_screen.dart';
import 'screens/three_d_view_screen.dart';

// ============================================================
// main()
// ============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Sistem UI - Windows masaüstü
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AntaresColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const AntaresStudioApp());
}

// ============================================================
// Ana Uygulama
// ============================================================

class AntaresStudioApp extends StatelessWidget {
  const AntaresStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ChangeNotifierProvider(create: (_) => ScanProvider()),
      ],
      child: MaterialApp(
        title: 'AntaresStudio IoT',
        debugShowCheckedModeBanner: false,
        theme: AntaresTheme.darkTheme,
        home: const AppShell(),
      ),
    );
  }
}

// ============================================================
// Uygulama Kabuğu (Bottom Nav + Sayfa Yönetimi)
// ============================================================

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with TickerProviderStateMixin {
  int _currentIndex = 0;

  // Animasyon
  late AnimationController _logoGlowController;
  late Animation<double> _logoGlowAnimation;

  // Sayfalar
  final List<Widget> _pages = const [
    DashboardScreen(),
    ThreeDViewScreen(),
    UpdateScreen(),
  ];

  @override
  void initState() {
    super.initState();

    // Logo glow animasyonu
    _logoGlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _logoGlowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoGlowController, curve: Curves.easeInOut),
    );
    _logoGlowController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _logoGlowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _pages[_currentIndex],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ----------------------------------------------------------------
  // Özel AppBar
  // ----------------------------------------------------------------
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Logo animasyonu
          AnimatedBuilder(
            animation: _logoGlowAnimation,
            builder: (context, child) {
              return Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AntaresColors.primary.withOpacity(_logoGlowAnimation.value),
                      AntaresColors.primary.withOpacity(_logoGlowAnimation.value * 0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AntaresColors.primary
                          .withOpacity(_logoGlowAnimation.value * 0.25),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'A',
                    style: TextStyle(
                      color: AntaresColors.background,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(width: 12),

          // Başlık
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ANTARES STUDIO',
                style: TextStyle(
                  color: AntaresColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                _getPageSubtitle(),
                style: const TextStyle(
                  color: AntaresColors.textDisabled,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Bağlantı durum göstergesi
          Consumer<DeviceProvider>(
            builder: (context, device, _) {
              return _buildAppBarStatus(device);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarStatus(DeviceProvider device) {
    final isConnected = device.isConnected;
    final color = isConnected ? AntaresColors.success : AntaresColors.textDisabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: isConnected
                  ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            device.statusMessage,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Alt Navigasyon
  // ----------------------------------------------------------------
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AntaresColors.surface,
        border: Border(
          top: BorderSide(color: AntaresColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _buildNavItem(0, Icons.dashboard_rounded, 'Dashboard'),
              _buildNavItem(1, Icons.view_in_ar_rounded, '3D Tarama'),
              _buildNavItem(2, Icons.system_update_rounded, 'Güncelleme'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AntaresColors.primary : AntaresColors.textDisabled;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AntaresColors.primary.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPageSubtitle() {
    switch (_currentIndex) {
      case 0:
        return 'KONTROL MERKEZİ';
      case 1:
        return 'FOTOGRAMETRİ';
      case 2:
        return 'FİRMWARE YÖNETİMİ';
      default:
        return '';
    }
  }
}
