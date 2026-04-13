Tüm içeriği tek bir dosya yapısında birleştiren nihai `README.md` formatı aşağıdadır. Kopyalayarak doğrudan projenize ekleyebilirsiniz.

```markdown
# AntaresStudio IoT

Tam otonom bir dijital ikiz stüdyosu oluşturmak amacıyla geliştirilen, fotogrametri tabanlı 3D tarama sistemi için IoT altyapısı. Sistem, donanım ve yazılım bileşenleri arasında SD kart ihtiyacını ortadan kaldırarak doğrudan Wi-Fi tabanlı iletişim kurar.

## Mimari

```text
┌──────────────┐     Wi-Fi (OTA)      ┌──────────────┐     UART Seri       ┌──────────────┐
│  Flutter App │ ──────────────────► │  ESP32-CAM   │ ──────────────────► │   Arduino    │
│  (Windows)   │     .bin / .hex      │  (Gateway)   │   Tetik & Bridge    │ (Mekanik/Mot)│
└──────┬───────┘                      └──────┬───────┘                     └──────────────┘
       │                                      │
       │  HTTP/REST                           │ HTTP POST (JPEG) 
       │                                      │ (SD Kart kullanılmaz)
       ▼                                      ▼
┌──────────────┐                      ┌──────────────┐
│   GitHub     │                      │   Backend    │
│  Releases    │                      │  (Python)    │
│  (.hex/.bin) │                      │  rembg +     │
└──────────────┘                      │  Meshroom    │
                                      └──────────────┘
```

## Klasör Yapısı

| Klasör              | Açıklama                                          |
|---------------------|---------------------------------------------------|
| `app/`              | Flutter masaüstü uygulaması (Windows kontrol merkezi) |
| `backend/`          | Python backend (rembg + Meshroom fotogrametri)     |
| `firmware_esp/`     | ESP32-CAM firmware (mDNS, OTA, UART Bridge, Doğrudan aktarım) |
| `firmware_arduino/` | Arduino Nano firmware (Mekanik dönüş ve sensör kontrolü) |

## Sistem Akışı ve Güncelleme (OTA + UART Bridge)

1. **Tam Otonom Çalışma:** ESP32-CAM, masaüstü uygulaması üzerinden gelen komutlarla Arduino'yu seri haberleşme üzerinden tetikleyerek platformun mekanik dönüşünü sağlar. Çekilen görüntüler SD kart kullanılmadan doğrudan Wi-Fi üzerinden Windows uygulamasına aktarılır.
2. **Yazılım Güncelleme:** Flutter masaüstü uygulaması GitHub Releases'dan güncel `.bin` (ESP32) ve `.hex` (Arduino) dosyalarını indirir.
3. ESP32-CAM kendi donanım güncellemesini Wi-Fi OTA ile alır.
4. Arduino güncellemesi için ESP32-CAM **Transparent UART Bridge** moduna geçer:
   - ESP32, Arduino'nun RESET pinini LOW'a çekerek bootloader moduna sokar.
   - Wi-Fi üzerinden gelen STK500 protokol verisi UART TX/RX hatlarından Arduino'ya aktarılır.
   - Güncelleme tamamlandığında bridge modu kapatılır ve normal çalışmaya dönülür.

## Donanım Bağlantıları

| ESP32-CAM Pin | Arduino Pin | Açıklama         |
|---------------|-------------|------------------|
| GPIO 14 (TX)  | RX          | UART Data        |
| GPIO 15 (RX)  | TX          | UART Data        |
| GPIO 12       | RESET       | Arduino Reset    |
| GND           | GND         | Ortak ground     |

---

## Değişiklik Günlüğü (Changelog)

Aşağıdaki liste, projenin mobil odaklı altyapıdan tam otonom stüdyo sistemine geçişi sırasındaki temel değişiklikleri içerir:

* **Platform Değişimi:** Hedef platform mobil cihazlardan **Windows masaüstüne** kaydırıldı. Klasör mimarisi ve şema, bu yapının profesyonel bir kontrol merkezi olduğunu yansıtacak şekilde revize edildi.
* **Proje Vizyonu:** Sistem tanımı salt bir IoT altyapısı olmaktan çıkarılarak, "tam otonom bir dijital ikiz stüdyosu" hedefi vurgulandı.
* **Veri Aktarım Akışı (SD Kart İptali):** Görüntülerin fiziksel bir SD karta kaydedilmeden, doğrudan Wi-Fi üzerinden masaüstü uygulamasına ve Python backend'ine aktarıldığı mimariye entegre edildi.
* **Donanım Görev Dağılımı:** Arduino'nun görev tanımı güncellenerek; ESP32 tarafından seri haberleşme ile tetiklenen **mekanik dönüş** sisteminin kontrol birimi olarak belirlendi.
* **Sistem İşleyişi (Otonom Süreç):** Güncelleme akışına "Tam Otonom Çalışma" adımı eklendi; sistemin normal operasyon sırasındaki veri aktarımı ve motor tetikleme süreci dökümante edildi.
```