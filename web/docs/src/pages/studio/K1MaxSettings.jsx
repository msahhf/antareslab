import React from 'react';
import Callout from '../../components/ui/Callout';
import PropertiesTable from '../../components/ui/PropertiesTable';
import ZoomableImage from '../../components/ui/ZoomableImage';

const K1MaxSettings = () => {
  return (
    <div className="max-w-3xl">
      <h1 className="text-3xl font-bold text-gray-900 mb-4">Creality K1 Max Parametreleri</h1>
      <p className="text-gray-600 mb-6 text-lg">
        Antares Studio üretim parkurundaki ana yazıcımız K1 Max için optimize edilmiş dilimleme (slicer) ayarlarıdır.
      </p>

      {/* Temsili Resim */}
      <ZoomableImage 
        src="https://cdn.qukasoft.com/f/443764/b3NXVUpHVTArYkI4Tmk4Z0dNOXJKYjhQSVl5OA/p/creality-k1-max-yuksek-hizli-3d-yazici-41373979.png"
        alt="Creality K1 Max"
        caption="Creality K1 Max - CoreXY Kapalı Kabin Yazıcı"
      />

      <Callout type="warning" title="Hyper PLA Uyarısı">
        Yüksek hızlı baskılarda (300mm/s+) mutlaka <strong>Creality Hyper PLA</strong> veya eşdeğer "High Flow" filament kullanın. Standart PLA tıkanma yapabilir.
      </Callout>

      <h2 className="text-xl font-bold text-gray-800 mt-8 mb-4">Hyper PLA Baskı Ayarları</h2>
      <PropertiesTable 
        headers={["Parametre", "Değer", "Notlar"]}
        data={[
          ["Nozzle Sıcaklığı", "220°C - 230°C", "Hıza göre artırılmalı"],
          ["Tabla (Bed) Sıcaklığı", "60°C", "PEI tabla için ideal"],
          ["Baskı Hızı (Print Speed)", "300 mm/s", "Dış duvarlarda 200 mm/s"],
          ["Geri Çekme (Retraction)", "0.8 mm", "Direct Drive olduğu için düşük tutun"],
          ["Fan Hızı", "%100", "Köprülerde (bridging) tam güç"],
        ]}
      />

      <h2 className="text-xl font-bold text-gray-800 mt-8 mb-4">Sorun Giderme</h2>
      <div className="space-y-4">
        <div className="p-4 border border-red-100 bg-red-50 rounded-lg">
          <h3 className="font-bold text-red-800">1. İlk Katman Yapışmıyor</h3>
          <p className="text-sm text-red-700 mt-1">
            Tabla kalibrasyonunu (Auto-leveling) tekrarlayın ve Z-Offset değerini -0.05mm aşağı çekin. Tablaya yapıştırıcı (stick) sürün.
          </p>
        </div>
        <div className="p-4 border border-orange-100 bg-orange-50 rounded-lg">
          <h3 className="font-bold text-orange-800">2. Ghosting / Ringing (Titreşim İzleri)</h3>
          <p className="text-sm text-orange-700 mt-1">
            "Input Shaping" kalibrasyonunu tekrar çalıştırın. Kemer gerginliğini kontrol edin.
          </p>
        </div>
      </div>

    </div>
  );
};

export default K1MaxSettings;