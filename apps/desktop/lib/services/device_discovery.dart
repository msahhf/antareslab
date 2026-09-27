// SPDX-License-Identifier: Apache-2.0

/// AntaresStudio IoT - Device Discovery Service
///
/// mDNS ile ağdaki ESP32-CAM cihazlarını keşfetme.
/// ESP32-CAM, "_antares._tcp" servisi olarak yayın yapar.

import 'dart:async';

/// Keşfedilen cihaz bilgisi
class DiscoveredDevice {
  final String name;
  final String host;
  final int port;
  final String? firmwareVersion;
  final String? deviceType;

  DiscoveredDevice({
    required this.name,
    required this.host,
    required this.port,
    this.firmwareVersion,
    this.deviceType,
  });

  String get baseUrl => 'http://$host:$port';

  @override
  String toString() => '$name ($host:$port) - v$firmwareVersion';
}

/// mDNS cihaz keşif servisi
class DeviceDiscoveryService {
  static const String serviceType = '_antares._tcp';
  static const Duration scanTimeout = Duration(seconds: 5);

  final List<DiscoveredDevice> _devices = [];
  final StreamController<List<DiscoveredDevice>> _devicesController =
      StreamController.broadcast();

  /// Keşfedilen cihazlar stream'i
  Stream<List<DiscoveredDevice>> get devicesStream => _devicesController.stream;

  /// Mevcut keşfedilen cihazlar
  List<DiscoveredDevice> get devices => List.unmodifiable(_devices);

  /// Ağda cihaz tara
  ///
  /// TODO: multicast_dns veya nsd_platform_interface paketi ile
  /// gerçek mDNS tarama implementasyonu yapılacak.
  ///
  /// Şimdilik bilinen hostname ile doğrudan bağlantı dener.
  Future<List<DiscoveredDevice>> scanForDevices() async {
    _devices.clear();

    // Şimdilik bilinen hostname'i dene
    // Gerçek implementasyonda mDNS discovery kullanılacak
    try {
      // TODO: multicast_dns paketi ile mDNS tarama
      // final MDnsClient client = MDnsClient();
      // await client.start();
      // await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
      //     ResourceRecordQuery.serverPointer(serviceType))) {
      //   // Servis kaydını bul
      // }
      // client.stop();

      // Geçici: Bilinen host'a doğrudan bağlan
      final device = DiscoveredDevice(
        name: 'AntaresScanner',
        host: 'antares-scanner.local',
        port: 80,
        firmwareVersion: 'unknown',
        deviceType: 'esp32cam',
      );

      _devices.add(device);
      _devicesController.add(_devices);
    } catch (e) {
      print('mDNS tarama hatası: $e');
    }

    return _devices;
  }

  void dispose() {
    _devicesController.close();
  }
}
