import { Globe, Box, Cpu } from "lucide-react";

export const sidebarConfig = {
  web: {
    title: "Antares Web",
    icon: <Globe size={20} className="text-blue-600" />,
    items: [
      { label: "Giriş", path: "/web" },
      { label: "Kurulum", path: "/web/installation" },
      { label: "Deployment (Vercel)", path: "/web/deployment" },
      { label: "API Yapısı", path: "/web/api" },
    ]
  },
  studio: {
    title: "Antares Studio",
    icon: <Box size={20} className="text-orange-600" />,
    items: [
      { label: "Genel Bakış", path: "/studio" },
      { label: "K1 Max Ayarları", path: "/studio/k1-settings" },
      { label: "Filament Profilleri", path: "/studio/filaments" },
      { label: "Hata Çözümleri", path: "/studio/troubleshoot" },
    ]
  },
  electronics: {
    title: "Antares Electronics",
    icon: <Cpu size={20} className="text-emerald-600" />,
    items: [
      { label: "Başlangıç", path: "/electronics" },
      { label: "ESP32 Pinout", path: "/electronics/pinout" },
      { label: "Sensör Verileri", path: "/electronics/sensors" },
      { label: "Haberleşme (MQTT)", path: "/electronics/mqtt" },
    ]
  }
};