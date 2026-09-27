import React from "react";
import Callout from "../../components/ui/Callout";
import CodeBlock from "../../components/ui/CodeBlock";
import PropertiesTable from "../../components/ui/PropertiesTable";
import ZoomableImage from "../../components/ui/ZoomableImage";

const Esp32Pinout = () => {
  return (
    <div className="max-w-3xl">
      <h1 className="text-3xl font-bold text-gray-900 mb-4">
        ESP32 Pin Şeması ve Özellikleri
      </h1>
      <p className="text-gray-600 mb-6 text-lg leading-relaxed">
        Antares Electronics projelerinde ana denetleyici olarak kullandığımız
        ESP32-WROOM modülünün giriş/çıkış (GPIO) haritası ve elektriksel
        özellikleri aşağıdadır.
      </p>

      <hr className="my-8 border-gray-200" />

      {/* Görsel Alanı (Placeholder) */}
      <ZoomableImage
        src="https://lastminuteengineers.com/wp-content/uploads/iot/ESP32-Pinout.png"
        alt="ESP32 WROOM Pinout Şeması"
        caption="Şekil 1.1: ESP32-WROOM Modülü Pin Haritası (Tıklayarak büyütün)"
      />

      <h2 className="text-xl font-bold text-gray-800 mb-4">Kritik Uyarılar</h2>

      <Callout type="warning" title="Voltaj Seviyesi">
        ESP32 pinleri <strong>3.3V mantık seviyesiyle</strong> çalışır. 5V ile
        çalışan sensörleri doğrudan bağlamayın, voltaj bölücü veya Logic Level
        Converter kullanın.
      </Callout>

      <Callout type="danger" title="Input Only (Sadece Giriş) Pinler">
        GPIO 34, 35, 36 ve 39 pinleri sadece <strong>veri okuma (INPUT)</strong>{" "}
        için kullanılabilir. Çıkış (OUTPUT) veremezler.
      </Callout>

      <h2 className="text-xl font-bold text-gray-800 mt-8 mb-4">
        Özel Fonksiyonlu Pinler
      </h2>
      <p className="text-gray-600 mb-4">
        Bazı pinlerin açılışta (boot) özel görevleri vardır.
      </p>

      <PropertiesTable
        headers={["Pin Adı", "GPIO No", "Özellik", "Notlar"]}
        data={[
          ["ADC1_0", "GPIO 36", "Analog Giriş", "Sadece Giriş (Input Only)"],
          [
            "Boot",
            "GPIO 0",
            "Boot Modu",
            "GND'ye çekilirse yükleme modu açılır",
          ],
          ["LED", "GPIO 2", "Dahili LED", "Genellikle mavi led bağlıdır"],
          ["RX", "GPIO 3", "Serial RX", "USB Haberleşmesi için kullanılır"],
          ["TX", "GPIO 1", "Serial TX", "USB Haberleşmesi için kullanılır"],
        ]}
      />

      <h2 className="text-xl font-bold text-gray-800 mt-8 mb-4">
        Örnek Kod: Pin Tanımlama
      </h2>
      <p className="text-gray-600">
        Arduino IDE üzerinde Antares projeleri için standart pin tanımlama
        yapısı:
      </p>

      <CodeBlock
        language="cpp"
        code={`// Antares Electronics Standart Pin Yapısı
#define LED_PIN 2
#define SENSOR_PIN 34 // Sadece giriş

void setup() {
  Serial.begin(115200);
  
  pinMode(LED_PIN, OUTPUT);
  pinMode(SENSOR_PIN, INPUT);
  
  Serial.println("Antares System Ready...");
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  delay(1000);
  digitalWrite(LED_PIN, LOW);
  delay(1000);
}`}
      />
    </div>
  );
};

export default Esp32Pinout;
