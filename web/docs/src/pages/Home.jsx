// SPDX-License-Identifier: Apache-2.0

import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Globe, BookOpen, Code, Cpu, ArrowRight, FileText } from 'lucide-react';

const Home = () => {
  const navigate = useNavigate();

  const sections = [
    {
      id: 'architecture',
      title: 'Architecture',
      description: 'System overview, component responsibilities, data flow, and communication protocols.',
      icon: <Globe size={40} />,
      color: 'bg-blue-50 text-blue-600',
      border: 'hover:border-blue-500',
      path: '/architecture'
    },
    {
      id: 'api',
      title: 'API Reference',
      description: 'Complete REST API documentation for Backend and ESP32 endpoints.',
      icon: <Code size={40} />,
      color: 'bg-purple-50 text-purple-600',
      border: 'hover:border-purple-500',
      path: '/api'
    },
    {
      id: 'specs',
      title: 'Specifications',
      description: 'UART protocol, hardware interfaces, pin mappings, and electrical specs.',
      icon: <FileText size={40} />,
      color: 'bg-amber-50 text-amber-600',
      border: 'hover:border-amber-500',
      path: '/specs'
    },
    {
      id: 'electronics',
      title: 'Electronics',
      description: 'ESP32 pinout, sensor interfaces, and hardware integration guides.',
      icon: <Cpu size={40} />,
      color: 'bg-emerald-50 text-emerald-600',
      border: 'hover:border-emerald-500',
      path: '/electronics'
    }
  ];

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center p-6">
      
      {/* Hero Section */}
      <div className="text-center max-w-2xl mb-12">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-100 text-indigo-700 text-sm font-medium mb-4">
          <BookOpen size={16} />
          <span>AntaresLab Documentation v1.0</span>
        </div>
        <h1 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4 tracking-tight">
          Antares<span className="text-indigo-600">Lab</span> Documentation
        </h1>
        <p className="text-lg text-gray-600">
          Technical documentation for the AntaresLab photogrammetry-based 3D scanning system.
          Covers architecture, APIs, hardware interfaces, and development guides.
        </p>
      </div>

      {/* Section Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8 max-w-6xl w-full">
        {sections.map((section) => (
          <div 
            key={section.id}
            onClick={() => navigate(section.path)}
            className={`
              relative group bg-white p-8 rounded-2xl shadow-sm border border-gray-200 
              cursor-pointer transition-all duration-300 ease-in-out
              hover:shadow-xl hover:-translate-y-1 ${section.border}
            `}
          >
            {/* Icon Box */}
            <div className={`w-16 h-16 rounded-xl flex items-center justify-center mb-6 ${section.color} transition-colors`}>
              {section.icon}
            </div>

            {/* Content */}
            <h3 className="text-2xl font-bold text-gray-900 mb-3 group-hover:text-gray-800">
              {section.title}
            </h3>
            <p className="text-gray-600 mb-6 leading-relaxed">
              {section.description}
            </p>

            {/* "View" Link */}
            <div className="flex items-center font-semibold text-sm group-hover:translate-x-1 transition-transform duration-300">
              <span className={section.color.split(' ')[1]}>View Documentation</span>
              <ArrowRight size={16} className={`ml-2 ${section.color.split(' ')[1]}`} />
            </div>
          </div>
        ))}
      </div>

      {/* Footer */}
      <div className="mt-16 text-gray-400 text-sm">
        &copy; {new Date().getFullYear()} AntaresLab. Press <kbd className="bg-gray-200 px-2 py-0.5 rounded text-gray-600 font-sans">Ctrl + K</kbd> for command menu.
      </div>
    </div>
  );
};

export default Home;