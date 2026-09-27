import React, { useState, useEffect } from "react";
import { X, ZoomIn } from "lucide-react";

const ZoomableImage = ({ src, alt, caption }) => {
  const [isOpen, setIsOpen] = useState(false);

  // ESC tuşuna basınca kapatma özelliği
  useEffect(() => {
    const handleEsc = (e) => {
      if (e.key === "Escape") setIsOpen(false);
    };
    window.addEventListener("keydown", handleEsc);
    return () => window.removeEventListener("keydown", handleEsc);
  }, []);

  return (
    <>
      {/* --- 1. KÜÇÜK GÖRÜNÜM (THUMBNAIL) --- */}
      <figure className="my-6 group">
        <div 
          className="relative overflow-hidden rounded-xl border border-gray-200 cursor-zoom-in bg-gray-100"
          onClick={() => setIsOpen(true)}
        >
          {/* Görsel */}
          <img 
            src={src} 
            alt={alt} 
            className="w-full h-auto object-cover transition-transform duration-300 group-hover:scale-105"
          />
          
          {/* Hover Overlay (Üzerine gelince çıkan ikon) */}
          <div className="absolute inset-0 bg-black/0 group-hover:bg-black/10 transition-colors flex items-center justify-center">
             <ZoomIn className="text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow-md" size={32} />
          </div>
        </div>
        
        {/* Resim Altı Yazısı (Caption) */}
        {caption && (
          <figcaption className="text-center text-sm text-gray-500 mt-2 italic">
            {caption}
          </figcaption>
        )}
      </figure>

      {/* --- 2. TAM EKRAN MODU (LIGHTBOX) --- */}
      {isOpen && (
        <div 
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4 animate-in fade-in duration-200"
          onClick={() => setIsOpen(false)} // Boşluğa tıklayınca kapat
        >
          {/* Kapatma Butonu */}
          <button 
            className="absolute top-6 right-6 text-white/70 hover:text-white bg-black/20 hover:bg-black/50 p-2 rounded-full transition-all"
            onClick={() => setIsOpen(false)}
          >
            <X size={32} />
          </button>

          {/* Büyük Görsel */}
          <img 
            src={src} 
            alt={alt} 
            className="max-w-full max-h-[90vh] rounded-lg shadow-2xl object-contain scale-in-95 animate-in duration-300"
            onClick={(e) => e.stopPropagation()} // Resme tıklayınca kapanmasın
          />
          
          {/* Zoom Modunda Altyazı */}
          {caption && (
            <div className="absolute bottom-6 left-0 w-full text-center px-4">
              <span className="bg-black/60 text-white px-4 py-2 rounded-full text-sm">
                {caption}
              </span>
            </div>
          )}
        </div>
      )}
    </>
  );
};

export default ZoomableImage;