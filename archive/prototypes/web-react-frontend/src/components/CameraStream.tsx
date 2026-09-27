import React, { useState } from 'react';

const CameraStream = () => {
  const [streamError, setStreamError] = useState(false);
  const streamUrl = "http://localhost:8000/api/esp32/stream";

  return (
    <div className="w-full h-64 bg-slate-900 rounded-xl border border-slate-800 overflow-hidden relative group">
      <div className="absolute top-4 left-4 z-10">
         <span className="bg-slate-800/80 backdrop-blur-md text-teal-400 px-3 py-1 rounded-full text-xs font-semibold uppercase tracking-wider border border-teal-500/20 flex items-center gap-2">
           <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></span>
           Live Camera
         </span>
      </div>
      
      {streamError ? (
        <div className="w-full h-full flex flex-col items-center justify-center text-slate-500 gap-3">
          <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M2 12h4l3-9 5 18 3-9h5"/>
          </svg>
          <span className="text-sm">Camera Stream Offline</span>
        </div>
      ) : (
        <img 
          src={streamUrl} 
          alt="ESP32 Live Stream" 
          className="w-full h-full object-cover"
          onError={() => setStreamError(true)}
        />
      )}
    </div>
  );
};

export default CameraStream;
