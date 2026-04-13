import React from 'react';

const Navbar = () => {
  return (
    <nav className="bg-slate-900 border-b border-slate-800 px-6 py-4 flex items-center justify-between">
      <div className="flex items-center gap-2">
        <div className="w-8 h-8 rounded-lg bg-teal-500 flex items-center justify-center">
          <span className="text-white font-bold text-xl">A</span>
        </div>
        <h1 className="text-xl font-semibold text-slate-100">AntaresStudio</h1>
        <span className="ml-2 px-2 py-0.5 rounded-full bg-slate-800 text-slate-400 text-xs font-medium">Web Edition</span>
      </div>
      <div>
        <button className="px-4 py-2 bg-teal-600 hover:bg-teal-500 text-white rounded-lg transition-colors font-medium text-sm">
          Connect ESP32
        </button>
      </div>
    </nav>
  );
};

interface LayoutProps {
  children: React.ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  return (
    <div className="min-h-screen bg-slate-950 flex flex-col font-sans text-slate-200">
      <Navbar />
      <main className="flex-1 max-w-7xl w-full mx-auto p-6">
        {children}
      </main>
    </div>
  );
};

export default Layout;
