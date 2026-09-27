import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Globe, Box, Cpu, ArrowRight, BookOpen } from 'lucide-react';

const Home = () => {
  const navigate = useNavigate();

  // Proje Verileri
  const projects = [
    {
      id: 'web',
      title: 'Antares Web',
      description: 'Web hizmetleri, sunucu dağıtımı ve arayüz dokümantasyon merkezi.',
      icon: <Globe size={40} />,
      color: 'bg-blue-50 text-blue-600',
      border: 'hover:border-blue-500',
      path: '/web'
    },
    {
      id: 'studio',
      title: 'Antares Studio',
      description: '3D baskı hizmetleri, model kütüphanesi ve üretim parametreleri.',
      icon: <Box size={40} />,
      color: 'bg-orange-50 text-orange-600',
      border: 'hover:border-orange-500',
      path: '/studio'
    },
    {
      id: 'electronics',
      title: 'Antares Electronics',
      description: 'ESP32, IoT sensör verileri, gömülü sistemler ve devre şemaları.',
      icon: <Cpu size={40} />,
      color: 'bg-emerald-50 text-emerald-600',
      border: 'hover:border-emerald-500',
      path: '/electronics'
    }
  ];

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center p-6">
      
      {/* Hero Bölümü (Başlık) */}
      <div className="text-center max-w-2xl mb-12">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-100 text-indigo-700 text-sm font-medium mb-4">
          <BookOpen size={16} />
          <span>AntaresLab Dokümantasyon v1.0</span>
        </div>
        <h1 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4 tracking-tight">
          Antares<span className="text-indigo-600">Lab</span> Ekosistemi
        </h1>
        <p className="text-lg text-gray-600">
          Geliştirdiğimiz tüm teknolojilerin teknik detaylarına, kullanım kılavuzlarına ve API referanslarına buradan ulaşabilirsiniz.
        </p>
      </div>

      {/* Kartlar Grid Yapısı */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-6xl w-full">
        {projects.map((project) => (
          <div 
            key={project.id}
            onClick={() => navigate(project.path)}
            className={`
              relative group bg-white p-8 rounded-2xl shadow-sm border border-gray-200 
              cursor-pointer transition-all duration-300 ease-in-out
              hover:shadow-xl hover:-translate-y-1 ${project.border}
            `}
          >
            {/* İkon Kutusu */}
            <div className={`w-16 h-16 rounded-xl flex items-center justify-center mb-6 ${project.color} transition-colors`}>
              {project.icon}
            </div>

            {/* İçerik */}
            <h3 className="text-2xl font-bold text-gray-900 mb-3 group-hover:text-gray-800">
              {project.title}
            </h3>
            <p className="text-gray-600 mb-6 leading-relaxed">
              {project.description}
            </p>

            {/* "İncele" Linki */}
            <div className="flex items-center font-semibold text-sm group-hover:translate-x-1 transition-transform duration-300">
              <span className={project.color.split(' ')[1]}>Dökümanı İncele</span>
              <ArrowRight size={16} className={`ml-2 ${project.color.split(' ')[1]}`} />
            </div>
          </div>
        ))}
      </div>

      {/* Footer Benzeri Alt Bilgi */}
      <div className="mt-16 text-gray-400 text-sm">
        &copy; {new Date().getFullYear()} AntaresLab. Hızlı arama için <kbd className="bg-gray-200 px-2 py-0.5 rounded text-gray-600 font-sans">Ctrl + K</kbd> kullanın.
      </div>
    </div>
  );
};

export default Home;