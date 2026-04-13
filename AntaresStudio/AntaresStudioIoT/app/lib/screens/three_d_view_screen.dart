/// AntaresStudio IoT - 3D Model Görüntüleyici Ekranı
///
/// Meshroom pipeline'ından gelen .obj modelini görüntüleme.
/// Backend ile konuşarak tarama başlatma, ilerleme takibi ve
/// sonuç modelini yükleme.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

// ============================================================
// Pipeline Durumu
// ============================================================

class PipelineStatus {
  final String pipelineId;
  final String status;
  final int progress;
  final String currentStep;
  final int photoCount;
  final String? modelPath;
  final String? error;

  PipelineStatus({
    this.pipelineId = '',
    this.status = 'idle',
    this.progress = 0,
    this.currentStep = '',
    this.photoCount = 0,
    this.modelPath,
    this.error,
  });

  factory PipelineStatus.fromJson(Map<String, dynamic> json) {
    return PipelineStatus(
      pipelineId: json['pipeline_id'] ?? '',
      status: json['status'] ?? 'idle',
      progress: json['progress'] ?? 0,
      currentStep: json['current_step'] ?? '',
      photoCount: json['photo_count'] ?? 0,
      modelPath: json['output_model'],
      error: json['error'],
    );
  }

  bool get isRunning => status == 'running' || status == 'queued';
  bool get isCompleted => status == 'completed';
  bool get hasError => status == 'error';
}

// ============================================================
// 3D View Ekranı
// ============================================================

class ThreeDViewScreen extends StatefulWidget {
  const ThreeDViewScreen({super.key});

  @override
  State<ThreeDViewScreen> createState() => _ThreeDViewScreenState();
}

class _ThreeDViewScreenState extends State<ThreeDViewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Backend bağlantı
  final String _backendHost = '192.168.1.100:8000'; // Konfigürasyondan alınacak
  final http.Client _client = http.Client();

  // Pipeline durumu
  PipelineStatus _pipeline = PipelineStatus();
  bool _isStarting = false;
  String _sessionId = '';

  // Pipeline aşamaları
  final List<_PipelineStep> _steps = [
    _PipelineStep('Feature Extraction', Icons.auto_fix_high_rounded),
    _PipelineStep('Feature Matching', Icons.compare_rounded),
    _PipelineStep('Structure from Motion', Icons.view_in_ar_rounded),
    _PipelineStep('Depth Map', Icons.layers_rounded),
    _PipelineStep('Meshing', Icons.grid_3x3_rounded),
    _PipelineStep('Texturing', Icons.texture_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _client.close();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // Backend İletişimi
  // ----------------------------------------------------------------

  /// Taramayı başlat (backend'e pipeline/start isteği gönder)
  Future<void> _startPipeline() async {
    if (_isStarting) return;

    setState(() {
      _isStarting = true;
      _pipeline = PipelineStatus(status: 'starting', currentStep: 'Başlatılıyor...');
    });

    try {
      final url = 'http://$_backendHost/api/v1/pipeline/start/$_sessionId?use_cleaned=true';
      final response = await _client.post(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final pipelineId = json['pipeline_id'] as String;

        setState(() {
          _pipeline = PipelineStatus(
            pipelineId: pipelineId,
            status: 'running',
            currentStep: 'Başlatıldı',
            photoCount: json['photo_count'] ?? 0,
          );
        });

        // İlerlemeyi periyodik olarak sorgula
        _pollPipelineStatus(pipelineId);
      } else {
        setState(() {
          _pipeline = PipelineStatus(
            status: 'error',
            error: 'Pipeline başlatılamadı: ${response.statusCode}',
          );
        });
      }
    } catch (e) {
      setState(() {
        _pipeline = PipelineStatus(
          status: 'error',
          error: 'Backend bağlantı hatası: $e',
        );
      });
    } finally {
      setState(() => _isStarting = false);
    }
  }

  /// Pipeline ilerlemesini sorgula
  Future<void> _pollPipelineStatus(String pipelineId) async {
    while (mounted && _pipeline.isRunning) {
      await Future.delayed(const Duration(seconds: 3));

      try {
        final url = 'http://$_backendHost/api/v1/pipeline/status/$pipelineId';
        final response = await _client.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _pipeline = PipelineStatus.fromJson(json);
            });
          }
        }
      } catch (e) {
        // Polling hatası, tekrar dene
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Başlık
          SliverToBoxAdapter(child: _buildHeaderCard()),

          // 3D Model Görüntüleyici
          SliverToBoxAdapter(child: _buildModelViewer()),

          // Pipeline Kontrolleri
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Container(width: 3, height: 16,
                    decoration: BoxDecoration(
                      color: AntaresColors.secondary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PİPELINE',
                    style: TextStyle(
                      color: AntaresColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Container(height: 1, color: AntaresColors.border)),
                ],
              ),
            ),
          ),

          // Oturum ID girişi ve başlat butonu
          SliverToBoxAdapter(child: _buildPipelineControls()),

          // Pipeline adımları
          SliverToBoxAdapter(child: _buildPipelineSteps()),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // Header
  // ----------------------------------------------------------------
  Widget _buildHeaderCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AntaresColors.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.view_in_ar_rounded,
                  color: AntaresColors.secondary, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3D Fotogrametri',
                    style: TextStyle(
                      color: AntaresColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Meshroom Pipeline → OBJ Model',
                    style: TextStyle(
                      color: AntaresColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // 3D Model Görüntüleyici
  // ----------------------------------------------------------------
  Widget _buildModelViewer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          gradient: AntaresColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AntaresColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Arka plan grid
              CustomPaint(
                painter: _GridPainter(),
              ),

              // Merkez içerik
              Center(
                child: _pipeline.isCompleted
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 56,
                            color: AntaresColors.success.withOpacity(0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Model hazır!',
                            style: TextStyle(
                              color: AntaresColors.success,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'flutter_3d_controller ile görüntülenecek',
                            style: TextStyle(
                              color: AntaresColors.textDisabled,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.view_in_ar_rounded,
                            size: 56,
                            color: AntaresColors.textDisabled.withOpacity(0.12),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '3D Model Önizleme',
                            style: TextStyle(
                              color: AntaresColors.textDisabled,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Pipeline tamamlandığında model\nburada görüntülenecek.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AntaresColors.textDisabled,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
              ),

              // Eksen göstergesi (sol alt)
              Positioned(
                left: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAxisLabel('X', AntaresColors.error),
                    const SizedBox(height: 2),
                    _buildAxisLabel('Y', AntaresColors.success),
                    const SizedBox(height: 2),
                    _buildAxisLabel('Z', AntaresColors.info),
                  ],
                ),
              ),

              // Model bilgisi (sağ alt)
              Positioned(
                right: 16,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _pipeline.isCompleted ? 'OBJ • Textured' : 'Henüz model yok',
                    style: const TextStyle(
                      color: AntaresColors.textDisabled,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAxisLabel(String axis, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 2, color: color),
        const SizedBox(width: 4),
        Text(
          axis,
          style: TextStyle(
            color: color.withOpacity(0.7),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------
  // Pipeline Kontrolleri
  // ----------------------------------------------------------------
  Widget _buildPipelineControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: AntaresColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AntaresColors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session ID girişi
            TextField(
              onChanged: (v) => _sessionId = v,
              style: const TextStyle(
                color: AntaresColors.textPrimary,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'Session ID (fotoğraf oturumu)',
                hintStyle: const TextStyle(
                  color: AntaresColors.textDisabled,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AntaresColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AntaresColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AntaresColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AntaresColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: const Icon(Icons.folder_rounded,
                    color: AntaresColors.textDisabled, size: 20),
              ),
            ),
            const SizedBox(height: 12),

            // Buton satırı
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pipeline.isRunning || _isStarting || _sessionId.isEmpty
                        ? null
                        : _startPipeline,
                    icon: _isStarting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AntaresColors.background,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      _pipeline.isRunning ? 'Çalışıyor...' : 'Taramayı Başlat',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AntaresColors.secondary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                if (_pipeline.isRunning) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () {
                      // Pipeline iptal et
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AntaresColors.error,
                      side: const BorderSide(color: AntaresColors.error),
                    ),
                    child: const Text('İptal'),
                  ),
                ],
              ],
            ),

            // İlerleme göstergesi
            if (_pipeline.isRunning) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    _pipeline.currentStep,
                    style: const TextStyle(
                      color: AntaresColors.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_pipeline.progress}%',
                    style: const TextStyle(
                      color: AntaresColors.secondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _pipeline.progress / 100,
                  minHeight: 6,
                  backgroundColor: AntaresColors.surfaceLight,
                  valueColor: const AlwaysStoppedAnimation<Color>(AntaresColors.secondary),
                ),
              ),
            ],

            // Hata
            if (_pipeline.hasError) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AntaresColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AntaresColors.error.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AntaresColors.error, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pipeline.error ?? 'Bilinmeyen hata',
                        style: const TextStyle(
                          color: AntaresColors.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Pipeline Adımları
  // ----------------------------------------------------------------
  Widget _buildPipelineSteps() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: AntaresColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AntaresColors.border),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: List.generate(_steps.length, (index) {
            final step = _steps[index];
            final stepProgress = _getStepState(index);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  // Durum ikonu
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: stepProgress == _StepState.completed
                          ? AntaresColors.success.withOpacity(0.15)
                          : stepProgress == _StepState.active
                              ? AntaresColors.secondary.withOpacity(0.15)
                              : AntaresColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      stepProgress == _StepState.completed
                          ? Icons.check_rounded
                          : step.icon,
                      size: 14,
                      color: stepProgress == _StepState.completed
                          ? AntaresColors.success
                          : stepProgress == _StepState.active
                              ? AntaresColors.secondary
                              : AntaresColors.textDisabled,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Adım adı
                  Expanded(
                    child: Text(
                      step.name,
                      style: TextStyle(
                        color: stepProgress == _StepState.pending
                            ? AntaresColors.textDisabled
                            : AntaresColors.textPrimary,
                        fontSize: 13,
                        fontWeight: stepProgress == _StepState.active
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),

                  // Aktif animasyon
                  if (stepProgress == _StepState.active)
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AntaresColors.secondary,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  _StepState _getStepState(int index) {
    if (!_pipeline.isRunning && !_pipeline.isCompleted) return _StepState.pending;

    // Basit ilerleme hesabı (her adım eşit ağırlıkta)
    final progressPerStep = 100 / _steps.length;
    final stepStart = index * progressPerStep;

    if (_pipeline.progress >= stepStart + progressPerStep) return _StepState.completed;
    if (_pipeline.progress >= stepStart) return _StepState.active;
    return _StepState.pending;
  }
}

// ============================================================
// Yardımcı Sınıflar
// ============================================================

class _PipelineStep {
  final String name;
  final IconData icon;
  _PipelineStep(this.name, this.icon);
}

enum _StepState { pending, active, completed }

/// 3D viewport arka plan grid çizimi
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AntaresColors.border.withOpacity(0.3)
      ..strokeWidth = 0.5;

    const spacing = 30.0;

    // Yatay çizgiler
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Dikey çizgiler
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Merkez çapraz (perspektif feeling)
    final centerPaint = Paint()
      ..color = AntaresColors.primary.withOpacity(0.06)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
