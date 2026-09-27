// ===================== ANTARES KAPSÜL V8 (ULTIMATE + GALERİ) =====================
// ✅ Sensör Verileri & Loglama
// ✅ 360° Tarama Sistemi
// ✅ Canlı Görüntü
// ✅ GALERİ: 192.168.4.1/galeri adresinde çalışan modern galeri
// ✅ Otomatik sayfa yenileme (F5) eklendi
// ==================================================================================

#include "esp_camera.h"
#include <WiFi.h>
#include "esp_http_server.h"
#include "FS.h"
#include "SD_MMC.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// ---------------- AP Bilgileri ----------------
const char *ap_ssid = "ANTARES_KAPSUL_LAB";
const char *ap_password = "CHANGE_THIS_PASSWORD";

// --------------- Pin Tanımları (AI-Thinker) ---------------
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27
#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22
#define LED_GPIO_NUM 4

#define SESSION_LIST_FILE "/360_sessions.txt"

httpd_handle_t server = NULL;
int photoCount = 0;

// ---------------- GLOBAL DEĞİŞKENLER ----------------
String t_temp = "--";
String t_hum = "--";
String t_soil = "--";
String t_heater = "--";
String t_fanDz = "0";
String t_mode = "BEKLEMEDE";

// 360 Tarama değişkenleri
bool is360Scanning = false;
int scan360Count = 0;
unsigned long scan360SessionID = 0;

// ===================== GEÇMİŞ LOG SİSTEMİ =====================
struct LogData {
  unsigned long time;
  String temp;
  String hum;
  String mode;
};

LogData history[20];
int historyIndex = 0;
int historyCount = 0;

void addLog(const String &t, const String &h, const String &m) {
  history[historyIndex].time = millis();
  history[historyIndex].temp = t;
  history[historyIndex].hum = h;
  history[historyIndex].mode = m;
  historyIndex = (historyIndex + 1) % 20;
  if (historyCount < 20) historyCount++;
}

// ===================== URL DECODE =====================
static char fromHex(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return 0;
}

static String urlDecode(const char *src) {
  String out;
  for (size_t i = 0; src[i]; i++) {
    if (src[i] == '%' && src[i + 1] && src[i + 2]) {
      char h = fromHex(src[i + 1]);
      char l = fromHex(src[i + 2]);
      out += char((h << 4) | l);
      i += 2;
    } else if (src[i] == '+') {
      out += ' ';
    } else {
      out += src[i];
    }
  }
  return out;
}

unsigned char h2int(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return 0;
}

// ===================== FOTO ÇEKİM FONKSİYONU =====================
bool takePhoto() {
  camera_fb_t *fb = NULL;

  // İlk 3 frame'i at (bazen bozuk olabiliyor)
  for (int i = 0; i < 3; i++) {
    fb = esp_camera_fb_get();
    if (fb) {
      esp_camera_fb_return(fb);
    }
  }

  // Gerçek fotoğrafı çek
  delay(500);
  fb = esp_camera_fb_get();

  if (!fb) {
    Serial.println("Kamera hatası!");
    return false;
  }

  String filename;
  if (is360Scanning) {
    // 360 tarama modunda
    filename = "/360_" + String(scan360SessionID) + "_" + String(scan360Count) + ".jpg";
    scan360Count++;
  } else {
    // Normal mod
    photoCount++;
    filename = "/IMG_" + String(photoCount) + "_" + String(millis()) + ".jpg";
  }

  File file = SD_MMC.open(filename.c_str(), FILE_WRITE);
  if (!file) {
    Serial.println("Dosya açma hatası!");
    esp_camera_fb_return(fb);
    return false;
  }

  // Fotoğrafı kaydet
  size_t written = file.write(fb->buf, fb->len);
  file.close();
  esp_camera_fb_return(fb);

  if (written == fb->len) {
    Serial.println("Fotoğraf kaydedildi: " + filename);
    return true;
  } else {
    Serial.println("Yazma hatası!");
    return false;
  }
}

// YARDIMCI FONKSİYON: Session'u listeye kaydet
void saveScanSession(unsigned long sessionID, int photoCount) {
  File file = SD_MMC.open(SESSION_LIST_FILE, FILE_APPEND);
  if (file) {
    file.println(String(sessionID) + "," + String(photoCount));
    file.close();
    Serial.println("Session kaydedildi: " + String(sessionID));
  }
}

// ===================== ANA ARAYÜZ (DASHBOARD - HTML) =====================
const char INDEX_HTML[] PROGMEM = R"=====(
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>ANTARES KAPSÜL V8</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.5.28/jspdf.plugin.autotable.min.js"></script>
<style>
  :root { --bg: #0b0c15; --card: #15192b; --text: #e0e6ed; --accent: #00d2ff; --warn: #ff4757; --success: #2ed573; }
  body { font-family: 'Segoe UI', Roboto, sans-serif; background: var(--bg); color: var(--text); margin: 0; padding: 0; }
  .header { background: linear-gradient(90deg, #0f2027, #203a43, #2c5364); padding: 15px; border-bottom: 2px solid var(--accent); display: flex; justify-content: space-between; align-items: center; }
  .status-badge { background: rgba(0, 210, 255, 0.2); padding: 5px 10px; border-radius: 4px; font-size: 0.8rem; border: 1px solid var(--accent); }
  .container { max-width: 900px; margin: 20px auto; padding: 0 10px; display: grid; gap: 15px; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); }
  .card { background: var(--card); border-radius: 12px; padding: 15px; box-shadow: 0 4px 15px rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.05); }
  .card-title { font-size: 0.9rem; color: #8892b0; margin-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 5px; }
  .telemetry-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
  .data-box { background: rgba(0,0,0,0.2); padding: 10px; border-radius: 8px; text-align: center; }
  .data-val { font-size: 1.5rem; font-weight: bold; color: var(--accent); }
  .data-label { font-size: 0.7rem; color: #aaa; }
  .status-row { display: flex; justify-content: space-between; margin-top: 10px; background: rgba(0,0,0,0.25); padding: 10px; border-radius: 8px; }
  .status-item { font-size: 0.8rem; display: flex; align-items: center; gap: 6px; }
  .dot { width: 10px; height: 10px; border-radius: 50%; background: #444; }
  .dot.active { background: var(--success); box-shadow: 0 0 8px var(--success); }
  .btn { width: auto; padding: 10px 20px; font-size: 14px; border: none; border-radius: 6px; font-weight: bold; cursor: pointer; margin-top: 6px; color: white; transition: 0.2s; }
  .btn-cap { background: var(--success); }
  .btn-pdf { background: #0ea5e9; }
  .btn-print { background: #2563eb; }
  .btn-stream { background: #ff4757; margin-top: 10px; }
  .btn-gallery { background: #8e44ad; color: white; text-decoration: none; display: inline-block; text-align: center; padding: 10px 20px; font-size: 14px; border-radius: 6px; margin-top: 10px; font-weight: bold; }
  .stream-container { display: none; background: rgba(0,0,0,0.3); border-radius: 8px; padding: 10px; margin-top: 10px; }
  .stream-view { width: 100%; border-radius: 4px; border: 2px solid var(--accent); }
  table { width: 100%; border-collapse: collapse; }
  th, td { border-bottom: 1px solid rgba(255,255,255,0.08); padding: 6px 4px; font-size: 0.8rem; text-align: left; }
  th { color: #9aa5c1; font-weight: 600; }
  @media print {
    body { background: white; color: black; }
    .no-print, .header { display: none !important; }
    .container { display: block; max-width: 100%; margin: 0; padding: 0; }
    .card { background: white; border: 1px solid #000; box-shadow: none; margin-bottom: 16px; }
    .card-title, th { color: black; }
    .data-val { color: black; }
    #print-header { display: block !important; }
  }
  #print-header { display:none; text-align:center; margin: 0 0 16px 0; }
  #print-header h1 { margin: 0; }
</style>
</head>
<body>

<div id="print-header">
  <h1>ANTARES KAPSÜL RAPORU</h1>
  <p>Mustafa Saffet Fen Lisesi - Sistem Durum Özeti</p>
  <p><small>Oluşturulma: <span id="print-date"></span></small></p>
  <hr>
</div>

<div class="header no-print">
  <div>ANTARES V8</div>
  <div id="modeDisplay" class="status-badge">BAĞLANIYOR...</div>
</div>

<div class="container">

  <div class="card">
    <div class="card-title">CANLI VERİLER</div>
    <div class="telemetry-grid">
      <div class="data-box"><div class="data-val" id="val-temp">--</div><div class="data-label">SICAKLIK (°C)</div></div>
      <div class="data-box"><div class="data-val" id="val-hum">--</div><div class="data-label">NEM (%)</div></div>
      <div class="data-box"><div class="data-val" id="val-soil">--</div><div class="data-label">TOPRAK (ADC)</div></div>
      <div class="data-box"><div class="data-val" id="val-heat">--</div><div class="data-label">ISITICI</div></div>
    </div>
    <div class="status-row">
      <div class="status-item"><div id="dot-sly" class="dot"></div> SLY FAN</div>
      <div class="status-item"><div id="dot-dz" class="dot"></div> DZ FAN</div>
      <div class="status-item"><div id="dot-cam" class="dot active"></div> SISTEM</div>
    </div>
  </div>

  <div class="card no-print">
    <div class="card-title">KAMERA & GÖRÜNTÜ</div>
    <button id="btn-toggle-stream" class="btn btn-stream" onclick="toggleStream()">🔴 CANLI İZLE (BAŞLAT)</button>
    <div id="stream-container" class="stream-container">
      <img id="stream-view" class="stream-view" src="" alt="Canlı Görüntü">
      <p style="font-size:0.8rem; color:#aaa; margin-top:8px; text-align:center;">Saniyede bir otomatik yenilenir</p>
    </div>

    <div style="margin-top:15px;"></div>
    <button class="btn btn-cap" onclick="capture()">📸 FOTOĞRAF ÇEK</button>
    
    <a href="/galeri" class="btn btn-gallery" target="_blank">📂 GALERİYİ AÇ</a>
    
    <div class="card-title" style="margin-top:15px;">RAPORLAMA</div>
    <button class="btn btn-pdf" onclick="exportPDF()">📄 PDF RAPORU İNDİR</button>
    <button class="btn btn-print" onclick="window.print()">🖨️ YAZDIR / PDF KAYDET</button>
  </div>

  <div class="card">
    <div class="card-title">SON 20 KAYIT (GEÇMİŞ)</div>
    <table>
      <thead><tr><th>Zaman</th><th>Sıcaklık</th><th>Nem</th><th>Mod</th></tr></thead>
      <tbody id="history-body"><tr><td colspan="4">Veri bekleniyor...</td></tr></tbody>
    </table>
  </div>

</div>

<script>
document.getElementById('print-date').innerText = new Date().toLocaleString();
const bustCache = (url) => url + (url.indexOf('?') >= 0 ? '&' : '?') + 't=' + new Date().getTime();
const formatTimestamp = (timeAgo) => {
  const now = new Date(); 
  const pastTime = new Date(now.getTime() - (timeAgo * 1000));
  return pastTime.getHours() + ':' + String(pastTime.getMinutes()).padStart(2, '0') + ':' + String(pastTime.getSeconds()).padStart(2, '0');
};

let streamActive = false; 
let streamInterval = null;
const updateLiveView = () => { document.getElementById('stream-view').src = bustCache('/capture_live'); };
const toggleStream = () => {
  const btn = document.getElementById('btn-toggle-stream');
  const container = document.getElementById('stream-container');
  const img = document.getElementById('stream-view');
  if (!streamActive) {
    updateLiveView(); container.style.display = 'block'; btn.textContent = '⏹ CANLI İZLE (DURDUR)'; streamActive = true;
    streamInterval = setInterval(updateLiveView, 1000); 
  } else {
    clearInterval(streamInterval); streamInterval = null; img.src = ''; container.style.display = 'none';
    btn.textContent = '🔴 CANLI İZLE (BAŞLAT)'; streamActive = false; 
  }
};

const updateStatus = () => {
  fetch('/status').then(r => r.json()).then(data => {
    document.getElementById('val-temp').innerText = data.temp;
    document.getElementById('val-hum').innerText = data.hum;
    document.getElementById('val-soil').innerText = data.soil;
    document.getElementById('val-heat').innerText = data.heater;
    document.getElementById('modeDisplay').innerText = '● ' + data.mode;
    document.getElementById('dot-sly').className = data.fanSly === '1' ? 'dot active' : 'dot';
    document.getElementById('dot-dz').className = data.fanDz === '1' ? 'dot active' : 'dot';
  });
};

const updateHistory = () => {
  fetch('/history').then(r => r.json()).then(arr => {
    const tbody = document.getElementById('history-body');
    tbody.innerHTML = '';
    arr.forEach(item => {
      const row = tbody.insertRow();
      row.insertCell(0).innerText = formatTimestamp(item.time / 1000);
      row.insertCell(1).innerText = item.temp + '°C';
      row.insertCell(2).innerText = item.hum + '%';
      row.insertCell(3).innerText = item.mode;
    });
  });
};

const capture = () => { fetch('/capture').then(() => alert('Fotoğraf Çekildi')); };

const exportPDF = () => {
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF();
  doc.text("ANTARES KAPSÜL RAPORU", 105, 15, { align: "center" });
  doc.setFontSize(10);
  doc.text('Tarih: ' + new Date().toLocaleString(), 14, 25);
  doc.autoTable({ html: 'table', startY: 30 });
  doc.save("antares_rapor.pdf");
};

setInterval(updateStatus, 2000);
setInterval(updateHistory, 5000);
updateStatus();
updateHistory();
</script>
</body>
</html>
)=====";

// ===================== GALERİ ARAYÜZÜ (MODERN + OTOMATIK YENİLEME) =====================
const char GALLERY_HTML[] PROGMEM = R"=====(
<!DOCTYPE html>
<html>
<head>
  <meta charset='UTF-8'>
  <meta name='viewport' content='width=device-width,initial-scale=1'>
  <title>ANTARES GALERİ</title>
  <style>
    * {box-sizing: border-box;}
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      text-align: center;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      margin: 0;
      padding: 20px;
      min-height: 100vh;
    }
    .container {
      max-width: 1000px;
      margin: auto;
      background: white;
      padding: 30px;
      border-radius: 20px;
      box-shadow: 0 10px 40px rgba(0,0,0,0.3);
    }
    h2 {
      color: #333;
      margin-bottom: 10px;
      font-size: 28px;
    }
    .status {
      color: #666;
      font-size: 14px;
      margin-bottom: 20px;
    }
    .controls {
      display: flex;
      gap: 10px;
      margin-bottom: 25px;
      flex-wrap: wrap;
      justify-content: center;
    }
    .btn {
      padding: 14px 28px;
      font-size: 16px;
      border: none;
      border-radius: 10px;
      cursor: pointer;
      transition: all 0.3s;
      font-weight: bold;
      box-shadow: 0 4px 15px rgba(0,0,0,0.2);
      flex: 1;
      min-width: 180px;
    }
    .btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(0,0,0,0.3);
    }
    .btn:active {
      transform: translateY(0);
    }
    .btn-home {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
    }
    .btn-cap {
      background: linear-gradient(135deg, #2ed573 0%, #26de81 100%);
      color: white;
    }
    .btn-refresh {
      background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
      color: white;
    }
    .btn-clear {
      background: linear-gradient(135deg, #fa709a 0%, #fee140 100%);
      color: white;
    }
    .btn-del {
      background: #ff4757;
      color: white;
      width: 100%;
      padding: 8px;
      font-size: 13px;
      margin-top: 8px;
      border-radius: 6px;
    }
    .btn-del:hover {
      background: #ff3838;
    }
    .gallery {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
      gap: 20px;
      margin-top: 25px;
    }
    .photo-card {
      background: #f8f9fa;
      padding: 10px;
      border-radius: 12px;
      box-shadow: 0 3px 10px rgba(0,0,0,0.1);
      transition: all 0.3s;
      position: relative;
    }
    .photo-card:hover {
      transform: translateY(-5px);
      box-shadow: 0 8px 25px rgba(0,0,0,0.15);
    }
    .photo-card img {
      width: 100%;
      height: 140px;
      object-fit: cover;
      border-radius: 8px;
      cursor: pointer;
      transition: all 0.3s;
    }
    .photo-card img:hover {
      opacity: 0.9;
    }
    .photo-name {
      font-size: 11px;
      color: #666;
      margin-top: 5px;
      word-break: break-all;
    }
    .loader {
      display: none;
      margin: 20px auto;
      border: 5px solid #f3f3f3;
      border-top: 5px solid #667eea;
      border-radius: 50%;
      width: 50px;
      height: 50px;
      animation: spin 1s linear infinite;
    }
    @keyframes spin {
      0% {transform: rotate(0deg);}
      100% {transform: rotate(360deg);}
    }
    .empty-state {
      padding: 60px 20px;
      color: #999;
      font-size: 18px;
    }
    .empty-state::before {
      content: '📷';
      display: block;
      font-size: 60px;
      margin-bottom: 20px;
    }
  </style>
</head>
<body>
  <div class='container'>
    <h2>📸 ANTARES Fotoğraf Galerisi</h2>
    <div class='status' id='status'>Bağlantı kuruluyor...</div>
    
    <div class='controls'>
      <button class='btn btn-home' onclick="window.location.href='/'">🏠 ANA SAYFA</button>
      <button class='btn btn-cap' onclick='capture()'>📷 YENİ FOTOĞRAF</button>
      <button class='btn btn-refresh' onclick='refreshPage()'>🔄 YENİLE</button>
      <button class='btn btn-clear' onclick='clearGallery()'>🗑️ HEPSİNİ SİL</button>
    </div>
    
    <div id='loader' class='loader'></div>
    <div id='gallery' class='gallery'></div>
  </div>

  <script>
    let loading = false;

    function showLoader() {
      document.getElementById('loader').style.display = 'block';
      loading = true;
    }

    function hideLoader() {
      document.getElementById('loader').style.display = 'none';
      loading = false;
    }

    function updateStatus(msg) {
      document.getElementById('status').textContent = msg;
    }

    function refreshPage() {
      location.reload();
    }

    function loadGallery() {
      if (loading) return;
      showLoader();
      updateStatus('Galeri yükleniyor...');
      
      fetch('/gallery_list')
        .then(response => {
          if (!response.ok) throw new Error('Sunucu yanıt vermedi');
          return response.text();
        })
        .then(html => {
          const gallery = document.getElementById('gallery');
          if (html.trim() === '' || html.includes('Henüz fotoğraf yok')) {
            gallery.innerHTML = '<div class="empty-state">Henüz fotoğraf yok.<br>Yukarıdaki butona tıklayarak ilk fotoğrafınızı çekin!</div>';
            updateStatus('Galeri boş');
          } else {
            gallery.innerHTML = html;
            const photoCount = gallery.querySelectorAll('.photo-card').length;
            updateStatus(photoCount + ' fotoğraf');
          }
          hideLoader();
        })
        .catch(err => {
          console.error('Galeri yükleme hatası:', err);
          updateStatus('❌ Bağlantı hatası!');
          document.getElementById('gallery').innerHTML = '<div class="empty-state">Bağlantı hatası! Lütfen yeniden deneyin.</div>';
          hideLoader();
        });
    }

    function capture() {
      if (loading) return;
      showLoader();
      updateStatus('Fotoğraf çekiliyor...');
      
      fetch('/capture')
        .then(response => {
          if (!response.ok) throw new Error('Çekim başarısız');
          updateStatus('✓ Fotoğraf çekildi! Sayfa yenileniyor...');
          setTimeout(() => location.reload(), 1000);
        })
        .catch(err => {
          console.error('Çekim hatası:', err);
          updateStatus('❌ Çekim hatası!');
          hideLoader();
          alert('Fotoğraf çekilemedi! SD kart takılı mı kontrol edin.');
        });
    }

    function deletePhoto(filename) {
      if (!confirm('Bu fotoğraf silinsin mi?')) return;
      showLoader();
      
      fetch('/delete?file=' + encodeURIComponent(filename))
        .then(response => {
          if (!response.ok) throw new Error('Silme başarısız');
          updateStatus('Fotoğraf silindi, sayfa yenileniyor...');
          setTimeout(() => location.reload(), 1000);
        })
        .catch(err => {
          console.error('Silme hatası:', err);
          updateStatus('❌ Silme hatası!');
          hideLoader();
        });
    }

    function clearGallery() {
      if (!confirm('⚠️ DİKKAT!\n\nSD karttaki TÜM fotoğraflar kalıcı olarak silinecek.\n\nDevam etmek istediğinize emin misiniz?')) return;
      
      showLoader();
      updateStatus('Tüm fotoğraflar siliniyor...');
      
      fetch('/deleteall')
        .then(response => {
          if (!response.ok) throw new Error('Toplu silme başarısız');
          updateStatus('✓ Tüm fotoğraflar silindi! Sayfa yenileniyor...');
          setTimeout(() => location.reload(), 1000);
        })
        .catch(err => {
          console.error('Toplu silme hatası:', err);
          updateStatus('❌ Silme hatası!');
          hideLoader();
        });
    }

    // Sayfa yüklendiğinde galeriyi yükle
    window.addEventListener('load', function() {
      updateStatus('Hazırlanıyor...');
      setTimeout(loadGallery, 500);
    });
  </script>
</body>
</html>
)=====";

// ===================== HANDLER FONKSİYONLARI =====================

// Ana Sayfa Handler (Dashboard)
static esp_err_t index_handler(httpd_req_t *req) {
  httpd_resp_set_type(req, "text/html");
  return httpd_resp_send(req, INDEX_HTML, strlen(INDEX_HTML));
}

// Galeri Sayfası Handler
static esp_err_t gallery_page_handler(httpd_req_t *req) {
  httpd_resp_set_type(req, "text/html");
  return httpd_resp_send(req, GALLERY_HTML, strlen(GALLERY_HTML));
}

// Status Handler (Dashboard için veri)
static esp_err_t status_handler(httpd_req_t *req) {
  String json = "{";
  json += "\"temp\":\"" + t_temp + "\",";
  json += "\"hum\":\"" + t_hum + "\",";
  json += "\"soil\":\"" + t_soil + "\",";
  json += "\"fanSly\":\"" + t_fanSly + "\",";
  json += "\"fanDz\":\"" + t_fanDz + "\",";
  json += "\"mode\":\"" + t_mode + "\"";
  json += "}";
  httpd_resp_set_type(req, "application/json");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// Canlı Görüntü (MJPEG Stream)
static esp_err_t stream_handler(httpd_req_t *req) {
  camera_fb_t *fb = NULL;
  esp_err_t res = ESP_OK;
  httpd_resp_set_type(req, "multipart/x-mixed-replace; boundary=frame");
  while (true) {
    fb = esp_camera_fb_get();
    if (!fb) {
      res = ESP_FAIL;
      break;
    }
    char part_buf[64];
    size_t hlen = snprintf(part_buf, 64, "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n", fb->len);
    res = httpd_resp_send_chunk(req, part_buf, hlen);
    if (res != ESP_OK) {
      esp_camera_fb_return(fb);
      break;
    }
    res = httpd_resp_send_chunk(req, (const char *)fb->buf, fb->len);
    esp_camera_fb_return(fb);
    if (res != ESP_OK) break;
    res = httpd_resp_send_chunk(req, "\r\n", 2);
    if (res != ESP_OK) break;
  }
  return res;
}

// History Handler
static esp_err_t history_handler(httpd_req_t *req) {
  String json = "[";
  for (int i = 0; i < historyCount; i++) {
    int idx = (historyIndex - historyCount + i + 20) % 20;
    if (i > 0) json += ",";
    json += "{\"time\":" + String(history[idx].time) + ",";
    json += "\"temp\":\"" + history[idx].temp + "\",";
    json += "\"hum\":\"" + history[idx].hum + "\",";
    json += "\"mode\":\"" + history[idx].mode + "\"}";
  }
  json += "]";
  httpd_resp_set_type(req, "application/json");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// ===================== GALERİ İÇİN HANDLERLAR =====================

// Galeri Liste Handler (HTML Fragment Döner)
static esp_err_t gallery_list_handler(httpd_req_t *req) {
  String html = "";
  int count = 0;

  File root = SD_MMC.open("/");
  if (!root) {
    Serial.println("SD kart açma hatası!");
    httpd_resp_send(req, "<p>SD kart hatası!</p>", HTTPD_RESP_USE_STRLEN);
    return ESP_OK;
  }

  File file = root.openNextFile();
  while (file) {
    if (!file.isDirectory()) {
      String filename = String(file.name());

      // Sadece .jpg dosyalarını listele
      if (filename.endsWith(".jpg") || filename.endsWith(".JPG")) {
        // Dosya adını temizle (başındaki / işaretini kaldır)
        if (filename.startsWith("/")) {
          filename = filename.substring(1);
        }

        count++;
        html += "<div class='photo-card'>";
        html += "<img src='/" + filename + "' onclick=\"window.open('/" + filename + "','_blank')\" alt='" + filename + "'>";
        html += "<div class='photo-name'>" + filename + "</div>";
        html += "<button class='btn btn-del' onclick=\"deletePhoto('" + filename + "')\">🗑️ Sil</button>";
        html += "</div>";
      }
    }
    file = root.openNextFile();
  }
  root.close();

  if (count == 0) {
    html = "<p>Henüz fotoğraf yok.</p>";
  }

  Serial.println("Listelenen fotoğraf sayısı: " + String(count));

  httpd_resp_set_type(req, "text/html; charset=utf-8");
  return httpd_resp_send(req, html.c_str(), html.length());
}

// ===================== EKLENEN KOD BAŞLANGICI =====================
// 360 Tarama Listesi Handler (JSON Döner - Python Uygulaması İçin)
static esp_err_t scan_list_handler(httpd_req_t *req) {
  Serial.println("📋 Tarama listesi istendi");

  // JSON başlat
  String json = "{";
  bool first = true;

  // SD kartı kontrol et
  if (!SD_MMC.begin()) {
    Serial.println("❌ SD kart erişim hatası");
    httpd_resp_sendstr(req, "{}");
    return ESP_OK;
  }

  // Kök dizini aç
  File root = SD_MMC.open("/");
  if (!root || !root.isDirectory()) {
    Serial.println("❌ Kök dizin açılamadı");
    httpd_resp_sendstr(req, "{}");
    return ESP_OK;
  }

  // Bulunan sessionları sakla (aynı session'ı tekrar eklememek için)
  String foundSessions[20];  // Maksimum 20 session
  int foundCount = 0;

  // Tüm dosyaları tara
  File file = root.openNextFile();
  while (file && foundCount < 20) {
    String filename = String(file.name());

    // Slash ile başlıyorsa kaldır
    if (filename.startsWith("/")) {
      filename = filename.substring(1);
    }

    Serial.println("  Dosya: " + filename);

    // 360_ ile başlayan dosyaları bul
    if (filename.startsWith("360_")) {
      // Format: 360_SESSIONID_COUNT.jpg
      // Örnek: 360_1738774123_0.jpg

      int firstUnderscore = filename.indexOf('_');
      int secondUnderscore = filename.indexOf('_', firstUnderscore + 1);

      if (firstUnderscore >= 0 && secondUnderscore > firstUnderscore) {
        String sessionID = filename.substring(firstUnderscore + 1, secondUnderscore);

        Serial.println("    → Session ID bulundu: " + sessionID);

        // Bu session daha önce eklendi mi kontrol et
        bool alreadyAdded = false;
        for (int i = 0; i < foundCount; i++) {
          if (foundSessions[i] == sessionID) {
            alreadyAdded = true;
            break;
          }
        }

        if (!alreadyAdded) {
          // Yeni session, listeye ekle
          foundSessions[foundCount++] = sessionID;

          // Bu session'a ait dosya sayısını hesapla
          int photoCount = 0;

          // Dizini baştan tara
          File root2 = SD_MMC.open("/");
          File file2 = root2.openNextFile();

          while (file2) {
            String fname2 = String(file2.name());
            if (fname2.startsWith("/")) fname2 = fname2.substring(1);

            // Bu session'a ait mi?
            if (fname2.startsWith("360_" + sessionID + "_")) {
              photoCount++;
            }

            file2 = root2.openNextFile();
          }
          root2.close();

          Serial.println("    → Fotoğraf sayısı: " + String(photoCount));

          // JSON'a ekle
          if (!first) {
            json += ",";
          }
          json += "\"" + sessionID + "\":" + String(photoCount);
          first = false;
        }
      }
    }

    file = root.openNextFile();
  }

  root.close();
  json += "}";

  Serial.println("📤 Gönderilen JSON: " + json);

  // HTTP yanıtını gönder
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_sendstr(req, json.c_str());

  return ESP_OK;
}

// ===================== EKLENEN KOD BİTİŞİ =====================

// Capture Handler (Her iki arayüz için ortak)
static esp_err_t capture_handler(httpd_req_t *req) {
  Serial.println("Fotoğraf çekme isteği alındı");

  if (takePhoto()) {
    Serial.println("Fotoğraf başarıyla çekildi");
    httpd_resp_set_type(req, "text/plain");
    return httpd_resp_send(req, "OK", 2);
  } else {
    Serial.println("Fotoğraf çekme başarısız!");
    return httpd_resp_send_500(req);
  }
}

// Canlı Snapshot (Dashboard için)
static esp_err_t capture_live_handler(httpd_req_t *req) {
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) return httpd_resp_send_500(req);
  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Content-Disposition", "inline");
  esp_err_t res = httpd_resp_send(req, (const char *)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  return res;
}

// Tekli Silme Handler
static esp_err_t delete_handler(httpd_req_t *req) {
  char query[256];
  char fileParam[256];

  if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK) {
    if (httpd_query_key_value(query, "file", fileParam, sizeof(fileParam)) == ESP_OK) {
      String filename = urlDecode(fileParam);

      // Dosya yolunu düzenle
      String filepath = filename;
      if (!filepath.startsWith("/")) {
        filepath = "/" + filepath;
      }

      Serial.println("Silinecek dosya: " + filepath);

      if (SD_MMC.remove(filepath.c_str())) {
        Serial.println("Dosya silindi: " + filepath);
        httpd_resp_set_type(req, "text/plain");
        return httpd_resp_send(req, "OK", 2);
      } else {
        Serial.println("Dosya silinemedi!");
      }
    }
  }

  return httpd_resp_send_500(req);
}

// Hepsini Sil Handler
static esp_err_t delete_all_handler(httpd_req_t *req) {
  Serial.println("Tüm fotoğraflar siliniyor...");
  int deletedCount = 0;

  File root = SD_MMC.open("/");
  if (!root) {
    Serial.println("SD kart açma hatası!");
    return httpd_resp_send_500(req);
  }

  File file = root.openNextFile();
  while (file) {
    String filename = String(file.name());

    if (!file.isDirectory() && (filename.endsWith(".jpg") || filename.endsWith(".JPG"))) {
      String fullPath = filename;
      if (!fullPath.startsWith("/")) {
        fullPath = "/" + fullPath;
      }

      file.close();  // Dosyayı kapat

      if (SD_MMC.remove(fullPath.c_str())) {
        deletedCount++;
        Serial.println("Silindi: " + fullPath);
      }

      file = root.openNextFile();
    } else {
      file = root.openNextFile();
    }
  }
  root.close();

  Serial.println("Toplam " + String(deletedCount) + " fotoğraf silindi");
  photoCount = 0;  // Sayacı sıfırla

  httpd_resp_set_type(req, "text/plain");
  return httpd_resp_send(req, "OK", 2);
}

// Dosya Sunma Handler (Wildcard)
static esp_err_t file_get_handler(httpd_req_t *req) {
  String path = String(req->uri);
  Serial.println("Dosya istendi: " + path);

  File file = SD_MMC.open(path.c_str(), FILE_READ);

  if (!file || file.isDirectory()) {
    Serial.println("Dosya bulunamadı: " + path);
    file.close();
    return httpd_resp_send_404(req);
  }

  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Cache-Control", "public, max-age=31536000");

  uint8_t *buffer = (uint8_t *)malloc(4096);
  if (buffer == NULL) {
    file.close();
    return httpd_resp_send_500(req);
  }

  size_t read_bytes;
  while (file.available()) {
    read_bytes = file.read(buffer, 4096);
    if (read_bytes > 0) {
      httpd_resp_send_chunk(req, (const char *)buffer, read_bytes);
    }
  }

  free(buffer);
  file.close();

  httpd_resp_send_chunk(req, NULL, 0);
  Serial.println("Dosya gönderildi: " + path);

  return ESP_OK;
}

// ===================== URI TANIMLARI =====================
static httpd_uri_t uri_root = { .uri = "/", .method = HTTP_GET, .handler = index_handler, .user_ctx = NULL };
static httpd_uri_t uri_galeri = { .uri = "/galeri", .method = HTTP_GET, .handler = gallery_page_handler, .user_ctx = NULL };
static httpd_uri_t uri_status = { .uri = "/status", .method = HTTP_GET, .handler = status_handler, .user_ctx = NULL };
static httpd_uri_t uri_stream = { .uri = "/stream", .method = HTTP_GET, .handler = stream_handler, .user_ctx = NULL };
static httpd_uri_t uri_history = { .uri = "/history", .method = HTTP_GET, .handler = history_handler, .user_ctx = NULL };
static httpd_uri_t uri_gallery_list = { .uri = "/gallery_list", .method = HTTP_GET, .handler = gallery_list_handler, .user_ctx = NULL };
static httpd_uri_t uri_scan_list = { .uri = "/360_list", .method = HTTP_GET, .handler = scan_list_handler, .user_ctx = NULL };
static httpd_uri_t uri_capture = { .uri = "/capture", .method = HTTP_GET, .handler = capture_handler, .user_ctx = NULL };
static httpd_uri_t uri_capture_live = { .uri = "/capture_live", .method = HTTP_GET, .handler = capture_live_handler, .user_ctx = NULL };
static httpd_uri_t uri_delete = { .uri = "/delete", .method = HTTP_GET, .handler = delete_handler, .user_ctx = NULL };
static httpd_uri_t uri_deleteall = { .uri = "/deleteall", .method = HTTP_GET, .handler = delete_all_handler, .user_ctx = NULL };
static httpd_uri_t uri_wildcard = { .uri = "/*", .method = HTTP_GET, .handler = file_get_handler, .user_ctx = NULL };

// ===================== SETUP & LOOP =====================
void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  Serial.begin(115200);
  Serial.println("\n\n=== ANTARES KAPSÜL V8 + GALERİ BAŞLATILIYOR ===");

  // Kamera yapılandırması
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  if (psramFound()) {
    // PSRAM varsa en yüksek çözünürlüğü zorla
    config.frame_size = FRAMESIZE_SXGA;  // 1280x1024
    config.jpeg_quality = 15;  // 10 çok iyi kalitedir (0-63 arası, düşük olan iyi)
    config.fb_count = 2;
  } else {
    // PSRAM yoksa mecburen düşür (yoksa çalışmaz)
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 20;
    config.fb_count = 1;
  }

  if (esp_camera_init(&config) != ESP_OK) {
    Serial.println("✗ Kamera başlatma hatası!");
    return;
  }
  Serial.println("✓ Kamera başlatıldı");

  sensor_t *s = esp_camera_sensor_get();
  s->set_vflip(s, 0);
  s->set_hmirror(s, 0);
  s->set_brightness(s, 0);
  s->set_contrast(s, 0);

  // SD Kart başlat
  if (!SD_MMC.begin()) {
    Serial.println("✗ SD Kart HATASI!");
  } else {
    uint8_t cardType = SD_MMC.cardType();
    if (cardType == CARD_NONE) {
      Serial.println("✗ SD Kart bulunamadı!");
    } else {
      Serial.println("✓ SD Kart hazır");
      uint64_t cardSize = SD_MMC.cardSize() / (1024 * 1024);
      Serial.printf("  SD Kart Boyutu: %lluMB\n", cardSize);

      // Mevcut fotoğraf sayısını hesapla
      File root = SD_MMC.open("/");
      File file = root.openNextFile();
      while (file) {
        if (!file.isDirectory()) {
          String name = String(file.name());
          if (name.endsWith(".jpg") || name.endsWith(".JPG")) {
            photoCount++;
          }
        }
        file = root.openNextFile();
      }
      root.close();
      Serial.printf("  Mevcut fotoğraf sayısı: %d\n", photoCount);
    }
  }

  // WiFi AP Başlat
  WiFi.softAP(ap_ssid, ap_password);
  delay(100);

  IPAddress IP = WiFi.softAPIP();
  Serial.println("✓ WiFi AP başlatıldı");
  Serial.println("  SSID: " + String(ap_ssid));
  Serial.println("  Şifre: " + String(ap_password));
  Serial.println("  IP Adresi: " + IP.toString());

  // HTTP Server başlat
  httpd_config_t server_config = HTTPD_DEFAULT_CONFIG();
  server_config.uri_match_fn = httpd_uri_match_wildcard;
  server_config.max_uri_handlers = 12;
  server_config.stack_size = 8192;

  if (httpd_start(&server, &server_config) == ESP_OK) {
    Serial.println("✓ Web sunucusu başlatıldı");

    httpd_register_uri_handler(server, &uri_root);
    httpd_register_uri_handler(server, &uri_galeri);
    httpd_register_uri_handler(server, &uri_status);
    httpd_register_uri_handler(server, &uri_stream);
    httpd_register_uri_handler(server, &uri_history);
    httpd_register_uri_handler(server, &uri_gallery_list);
    httpd_register_uri_handler(server, &uri_scan_list);
    httpd_register_uri_handler(server, &uri_capture);
    httpd_register_uri_handler(server, &uri_capture_live);
    httpd_register_uri_handler(server, &uri_delete);
    httpd_register_uri_handler(server, &uri_deleteall);
    httpd_register_uri_handler(server, &uri_wildcard);

    Serial.println("\n=== SİSTEM HAZIR ===");
    Serial.println("Dashboard: http://" + IP.toString());
    Serial.println("Galeri: http://" + IP.toString() + "/galeri");
    Serial.println("====================\n");
  } else {
    Serial.println("✗ Web sunucusu başlatılamadı!");
  }

  addLog(t_temp, t_hum, t_mode);
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();

    if (line.startsWith("DATA,")) {
      int idx1 = line.indexOf(',');
      int idx2 = line.indexOf(',', idx1 + 1);
      int idx3 = line.indexOf(',', idx2 + 1);
      int idx5 = line.indexOf(',', idx4 + 1);
      int idx6 = line.indexOf(',', idx5 + 1);
      int idx7 = line.indexOf(',', idx6 + 1);

      if (idx7 != -1) {
        t_temp = line.substring(idx1 + 1, idx2);
        t_hum = line.substring(idx2 + 1, idx3);
        t_soil = line.substring(idx3 + 1, idx4);
        t_heater = line.substring(idx4 + 1, idx5);
        t_fanSly = line.substring(idx5 + 1, idx6);
        t_fanDz = line.substring(idx6 + 1, idx7);
        t_mode = line.substring(idx7 + 1);

        static unsigned long lastLog = 0;
        if (millis() - lastLog > 10000UL) {
          addLog(t_temp, t_hum, t_mode);
          lastLog = millis();
        }
      }
    } else if (line.indexOf("360_START") >= 0) {
      is360Scanning = true;
      scan360Count = 0;
      scan360SessionID = millis();
      Serial.println("360 Scan Started: " + String(scan360SessionID));
    } else if (line.indexOf("360_END") >= 0) {
      is360Scanning = false;
      saveScanSession(scan360SessionID, scan360Count);  // ✨ BU SATIRI EKLE
      Serial.println("360 Scan Ended");
    } else if (line == "CEK") {
      takePhoto();
      Serial.println("Fotoğraf çekildi (Seri komut)");
    } else if (line == "DURUM") {
      Serial.println("\n=== SİSTEM DURUMU ===");
      Serial.println("WiFi AP: " + String(ap_ssid));
      Serial.println("IP: " + WiFi.softAPIP().toString());
      Serial.println("Toplam fotoğraf: " + String(photoCount));
      Serial.println("Mod: " + t_mode);
      Serial.println("Sıcaklık: " + t_temp + "°C");
      Serial.println("Nem: " + t_hum + "%");

      uint64_t cardSize = SD_MMC.cardSize() / (1024 * 1024);
      uint64_t usedSize = SD_MMC.usedBytes() / (1024 * 1024);
      Serial.printf("SD Kart: %lluMB / %lluMB\n", usedSize, cardSize);
      Serial.println("====================\n");
    }
  }

  delay(10);
}
