// SPDX-License-Identifier: Apache-2.0

/// Antares Studio - Media Gallery & Sync Screen
/// Photo grid, session management, and backend upload interface

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../providers/scan_provider.dart';
import '../services/backend_service.dart';
import '../theme/antares_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/action_button.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late TabController _tabController;
  final List<Uint8List> _capturedPhotos = [];
  bool _isUploading = false;
  double _uploadProgress = 0;
  String _uploadStatus = '';
  String? _sessionId;

  final _backend = BackendService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _backend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer2<DeviceProvider, ScanProvider>(
      builder: (context, device, scan, _) {
        // Get photos from scan provider
        if (scan.capturedPhotos.isNotEmpty) {
          _capturedPhotos.clear();
          _capturedPhotos.addAll(scan.capturedPhotos);
        }

        return Column(
          children: [
            // Tab bar
            Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              decoration: BoxDecoration(
                color: AntaresColors.surface.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AntaresColors.border.withOpacity(0.5)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AntaresColors.cyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AntaresColors.cyan.withOpacity(0.3)),
                ),
                labelColor: AntaresColors.cyan,
                unselectedLabelColor: AntaresColors.textDisabled,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'CURRENT SCAN', icon: Icon(Icons.camera_rounded, size: 18)),
                  Tab(text: 'SD CARD', icon: Icon(Icons.sd_storage_rounded, size: 18)),
                ],
              ),
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCurrentScanTab(scan),
                  _buildSDCardTab(device),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCurrentScanTab(ScanProvider scan) {
    final hasPhotos = _capturedPhotos.isNotEmpty;
    final isCompleted = scan.state == ScanState.completed;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // Photo count header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AntaresColors.cyan.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_library_rounded,
                      color: AntaresColors.cyan,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_capturedPhotos.length} Photos Captured',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AntaresColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isCompleted
                              ? 'Scan completed. Ready for upload.'
                              : scan.isActive
                                  ? 'Scan in progress...'
                                  : 'Start a scan to capture photos.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AntaresColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Upload section
        if (hasPhotos)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildUploadSection(scan),
            ),
          ),

        if (hasPhotos)
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Photo grid
        if (hasPhotos)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _capturedPhotos.length,
              itemBuilder: (context, index) {
                return _buildPhotoThumbnail(
                  index: index,
                  photo: _capturedPhotos[index],
                  onTap: () => _showPhotoViewer(index),
                );
              },
            ),
          )
        else
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 64,
                    color: AntaresColors.textDisabled.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Photos Yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AntaresColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Complete a 360° scan to see photos here.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AntaresColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildUploadSection(ScanProvider scan) {
    final canUpload = _capturedPhotos.isNotEmpty && !_isUploading;
    final hasSession = _sessionId != null;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: _isUploading
          ? AntaresColors.cyan.withOpacity(0.4)
          : hasSession
              ? AntaresColors.emerald.withOpacity(0.3)
              : AntaresColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isUploading
                    ? Icons.cloud_upload_rounded
                    : hasSession
                        ? Icons.check_circle_rounded
                        : Icons.cloud_queue_rounded,
                color: _isUploading
                    ? AntaresColors.cyan
                    : hasSession
                        ? AntaresColors.emerald
                        : AntaresColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isUploading
                          ? 'Uploading to Backend...'
                          : hasSession
                              ? 'Upload Complete'
                              : 'Ready to Upload',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _isUploading
                            ? AntaresColors.cyan
                            : hasSession
                                ? AntaresColors.emerald
                                : AntaresColors.textPrimary,
                      ),
                    ),
                    if (_uploadStatus.isNotEmpty)
                      Text(
                        _uploadStatus,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AntaresColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_isUploading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: AntaresColors.border.withOpacity(0.3),
                color: AntaresColors.cyan,
                minHeight: 6,
              ),
            ),
          ],
          if (canUpload) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    label: 'UPLOAD TO BACKEND',
                    icon: Icons.cloud_upload_rounded,
                    onPressed: () => _uploadPhotos(scan),
                    accentColor: AntaresColors.cyan,
                  ),
                ),
              ],
            ),
          ],
          if (hasSession) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AntaresColors.emerald.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AntaresColors.emerald.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 18,
                    color: AntaresColors.emerald.withOpacity(0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      'Session: $_sessionId',
                      style: TextStyle(
                        fontSize: 12,
                        color: AntaresColors.emerald.withOpacity(0.8),
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    label: 'START BACKGROUND CLEANING',
                    icon: Icons.auto_fix_high_rounded,
                    onPressed: () => _startCleaning(scan),
                    accentColor: AntaresColors.violet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    label: 'START MESHROOM PIPELINE',
                    icon: Icons.view_in_ar_rounded,
                    onPressed: () => _startPipeline(scan),
                    accentColor: AntaresColors.amber,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSDCardTab(DeviceProvider device) {
    final sdActive = device.espStatus?.sdActive == true;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // SD Status
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: sdActive
                          ? AntaresColors.emerald.withOpacity(0.15)
                          : AntaresColors.rose.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      sdActive
                          ? Icons.sd_storage_rounded
                          : Icons.sd_storage_outlined,
                      color: sdActive
                          ? AntaresColors.emerald
                          : AntaresColors.rose,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sdActive ? 'SD Card Active' : 'SD Card Not Detected',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: sdActive
                                ? AntaresColors.emerald
                                : AntaresColors.rose,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sdActive
                              ? 'Photos are stored on SD when PC is unavailable.'
                              : 'Direct transfer mode only. No SD backup.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AntaresColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Session sync placeholder
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.sync_rounded,
                    size: 48,
                    color: AntaresColors.textDisabled.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'SD Card Sessions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AntaresColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Access saved sessions from SD card and sync to backend.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AntaresColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ActionButton(
                    label: sdActive ? 'REFRESH SESSIONS' : 'SD NOT AVAILABLE',
                    icon: Icons.refresh_rounded,
                    onPressed: sdActive ? () {} : null,
                    accentColor: AntaresColors.cyan,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildPhotoThumbnail({
    required int index,
    required Uint8List photo,
    required VoidCallback onTap,
  }) {
    return Hero(
      tag: 'photo_$index',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AntaresColors.border.withOpacity(0.3),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              photo,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  void _showPhotoViewer(int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black.withOpacity(0.9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo page view
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: _capturedPhotos.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: Hero(
                      tag: 'photo_$index',
                      child: Image.memory(
                        _capturedPhotos[index],
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                );
              },
            ),
            // Close button
            Positioned(
              top: 16,
              right: 16,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: AntaresColors.surface.withOpacity(0.8),
                  foregroundColor: AntaresColors.textPrimary,
                ),
              ),
            ),
            // Photo counter
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AntaresColors.surface.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${initialIndex + 1} / ${_capturedPhotos.length}',
                    style: const TextStyle(
                      color: AntaresColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadPhotos(ScanProvider scan) async {
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _uploadStatus = 'Preparing upload...';
    });

    try {
      final sid = await scan.uploadToBackend(_capturedPhotos);
      if (sid != null) {
        setState(() {
          _sessionId = sid;
          _uploadStatus = 'Upload complete!';
        });
      } else {
        setState(() {
          _uploadStatus = 'Upload failed';
        });
      }
    } catch (e) {
      setState(() {
        _uploadStatus = 'Error: $e';
      });
    } finally {
      setState(() {
        _isUploading = false;
        _uploadProgress = 1;
      });
    }
  }

  void _startCleaning(ScanProvider scan) {
    scan.startBackgroundCleaning();
  }

  void _startPipeline(ScanProvider scan) {
    scan.startPipelineAndMonitor();
  }
}
