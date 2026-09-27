import React, { useState, useEffect } from "react";
import { Outlet, useLocation, NavLink, Link } from "react-router-dom";
import { sidebarConfig } from "../../data/sidebarConfig.jsx";
import { ChevronLeft, Menu, X, Search } from "lucide-react";
import { useSearch } from "../../context/SearchContext"; // Context eklendi

const DocsLayout = () => {
  const location = useLocation();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const { setOpen } = useSearch(); // Arama kutusunu açmak için fonksiyonu aldık

  // URL'den hangi bölümde olduğumuzu anla (örn: /web/kurulum -> 'web')
  const currentSection = location.pathname.split("/")[1];
  const config = sidebarConfig[currentSection] || { title: "Docs", items: [] };

  // Sayfa değiştiğinde mobil menüyü otomatik kapat (UX kuralı)
  useEffect(() => {
    setIsMobileMenuOpen(false);
  }, [location.pathname]);

  return (
    <div className="flex h-screen bg-white overflow-hidden">
      {/* --- MOBİL HEADER (Sadece küçük ekranda görünür) --- */}
      <div className="md:hidden fixed top-0 left-0 w-full h-16 bg-white border-b border-gray-200 z-40 flex items-center px-4 justify-between">
        {/* Sol Taraf: İkon ve Başlık */}
        <div className="flex items-center gap-2 font-bold text-gray-800">
          {config.icon}
          <span className="truncate max-w-[150px]">{config.title}</span>
        </div>

        {/* Sağ Taraf: Buton Grubu */}
        <div className="flex items-center gap-1">
          {/* 1. ARAMA BUTONU (YENİ EKLENDİ) */}
          <button
            onClick={() => setOpen(true)}
            className="p-2 text-gray-600 hover:bg-gray-100 rounded-md active:scale-95 transition-transform"
            aria-label="Arama Yap"
          >
            <Search size={22} />
          </button>

          {/* 2. MENÜ BUTONU */}
          <button
            onClick={() => setIsMobileMenuOpen(true)}
            className="p-2 text-gray-600 hover:bg-gray-100 rounded-md active:scale-95 transition-transform"
            aria-label="Menüyü Aç"
          >
            <Menu size={24} />
          </button>
        </div>
      </div>

      {/* --- MOBİL OVERLAY (Menü açılınca arkadaki karartı) --- */}
      {isMobileMenuOpen && (
        <div
          className="fixed inset-0 bg-black/50 z-40 md:hidden animate-in fade-in duration-200"
          onClick={() => setIsMobileMenuOpen(false)}
        />
      )}

      {/* --- SIDEBAR (Hem Mobil Hem Desktop İçin Ortak Yapı) --- */}
      <aside
        className={`
        fixed md:static inset-y-0 left-0 z-50 w-64 bg-gray-50 border-r border-gray-200 flex flex-col transition-transform duration-300 ease-in-out
        ${isMobileMenuOpen ? "translate-x-0" : "-translate-x-full md:translate-x-0"}
      `}
      >
        {/* Sidebar Üst Kısım: Geri Dön ve Başlık */}
        <div className="p-4 border-b border-gray-200 flex justify-between items-start">
          <div>
            <Link
              to="/"
              className="flex items-center text-xs text-gray-500 hover:text-gray-900 mb-4 transition-colors"
            >
              <ChevronLeft size={14} className="mr-1" /> Ana Sayfaya Dön
            </Link>

            <div className="flex items-center gap-2 font-bold text-gray-800 text-lg">
              {config.icon}
              <span>{config.title}</span>
            </div>
          </div>

          {/* Mobilde Menüyü Kapatma Butonu (X) */}
          <button
            onClick={() => setIsMobileMenuOpen(false)}
            className="md:hidden p-1 text-gray-500 hover:text-gray-900"
          >
            <X size={20} />
          </button>
        </div>

        {/* Menü Linkleri */}
        <nav className="flex-1 overflow-y-auto p-4 space-y-1">
          {config.items &&
            config.items.map((item) => (
              <NavLink
                key={item.path}
                to={item.path}
                end={item.path === `/${currentSection}`}
                className={({ isActive }) => `
                block px-3 py-2 rounded-md text-sm font-medium transition-all
                ${
                  isActive
                    ? "bg-gray-200 text-gray-900 shadow-sm"
                    : "text-gray-600 hover:bg-gray-100 hover:text-gray-900"
                }
              `}
              >
                {item.label}
              </NavLink>
            ))}
        </nav>

        {/* Sidebar Footer */}
        <div className="p-4 border-t border-gray-200 text-xs text-gray-400">
          AntaresLab v1.0
        </div>
      </aside>

      {/* --- ANA İÇERİK --- */}
      <main className="flex-1 overflow-y-auto w-full pt-16 md:pt-0">
        {/* pt-16: Mobil header yüksekliği kadar boşluk */}
        <div className="max-w-4xl mx-auto p-6 md:p-12 min-h-full">
          <Outlet />
        </div>
      </main>
    </div>
  );
};

export default DocsLayout;
