import React from 'react';
import Callout from '../../components/ui/Callout';
import CodeBlock from '../../components/ui/CodeBlock';
import PropertiesTable from '../../components/ui/PropertiesTable';

const WebDeployment = () => {
  return (
    <div className="max-w-3xl">
      <h1 className="text-3xl font-bold text-gray-900 mb-4">Web Projesi Dağıtımı (Vercel)</h1>
      <p className="text-gray-600 mb-6 text-lg">
        AntaresWeb arayüzü, React tabanlı olup Vercel altyapısında barındırılmaktadır. Canlıya alma (deploy) süreçleri aşağıda detaylandırılmıştır.
      </p>

      <Callout type="info" title="CI/CD Otomasyonu">
        Github deposuna yapılan her "push" işlemi, Vercel tarafından otomatik olarak algılanır ve yeni sürüm oluşturulur.
      </Callout>

      <h2 className="text-xl font-bold text-gray-800 mt-8 mb-4">1. Manuel Build Alma</h2>
      <p className="text-gray-600 mb-2">Lokal testler için projeyi derlemek isterseniz:</p>
      
      <CodeBlock 
        language="bash"
        code={`# Bağımlılıkları yükle
npm install

# Build al (dist klasörü oluşur)
npm run build

# Lokal sunucuda önizle
npm run preview`} 
      />

      <h2 className="text-xl font-bold text-gray-800 mt-8 mb-4">2. Vercel Konfigürasyonu</h2>
      <p className="text-gray-600 mb-4">Projenin kök dizinindeki <code>vercel.json</code> ayarları:</p>

      <CodeBlock 
        language="json"
        code={`{
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    }
  ]
}`} 
      />

      <h2 className="text-xl font-bold text-gray-800 mt-8 mb-4">Ortam Değişkenleri (Environment Variables)</h2>
      <PropertiesTable 
        headers={["Değişken", "Tip", "Açıklama"]}
        data={[
          ["VITE_API_URL", "String", "Backend servisinin adresi"],
          ["VITE_ENV", "String", "development / production"],
          ["ANALYTICS_ID", "String", "Google Analytics takip kodu"],
        ]}
      />
    </div>
  );
};

export default WebDeployment;