import { BrowserRouter, Routes, Route } from "react-router-dom";
import CommandMenu from "./components/ui/CommandMenu";
import Home from "./pages/Home";
import DocsLayout from "./components/layout/DocsLayout";
import Esp32Pinout from "./pages/electronics/Esp32Pinout";
import WebDeployment from "./pages/web/WebDeployment";
import K1MaxSettings from "./pages/studio/K1MaxSettings";
import { SearchProvider } from "./context/SearchContext";

// Örnek İçerik Sayfaları (Test için)
const PagePlaceholder = ({ title }) => (
  <div className="prose lg:prose-xl">
    <h1 className="text-3xl font-bold text-gray-900 mb-4">{title}</h1>
    <p className="text-gray-600">
      Buraya {title} ile ilgili detaylı dokümantasyon ve açıklamalar gelecek.
      Markdown içerikleri veya React bileşenleri burada gösterilecek.
    </p>
    <div className="mt-8 p-4 bg-yellow-50 border border-yellow-200 rounded text-yellow-800">
      🚧 Bu sayfa yapım aşamasındadır.
    </div>
  </div>
);

function App() {
  return (
    <SearchProvider>
      <BrowserRouter>
        <CommandMenu />

        <Routes>
          {/* Landing Page (Layout dışında) */}
          <Route path="/" element={<Home />} />

          {/* Dokümantasyon Sayfaları (DocsLayout içinde) */}
          <Route element={<DocsLayout />}>
            {/* Antares Web Rotaları */}
            <Route
              path="/web"
              element={<PagePlaceholder title="Antares Web: Giriş" />}
            />
            <Route path="/web/deployment" element={<WebDeployment />} />{" "}
            {/* GÜNCELLENDİ */}
            <Route
              path="/web/installation"
              element={<PagePlaceholder title="Web Kurulumu" />}
            />
            {/* Antares Studio Rotaları */}
            <Route
              path="/studio"
              element={<PagePlaceholder title="Antares Studio: Giriş" />}
            />
            <Route path="/studio/k1-settings" element={<K1MaxSettings />} />{" "}
            {/* GÜNCELLENDİ */}
            {/* Antares Electronics Rotaları */}
            <Route
              path="/electronics"
              element={<PagePlaceholder title="Antares Electronics: Giriş" />}
            />
            <Route path="/electronics/pinout" element={<Esp32Pinout />} />{" "}
            {/* Değişen kısım burası */}
          </Route>
        </Routes>
      </BrowserRouter>
    </SearchProvider>
  );
}

export default App;
