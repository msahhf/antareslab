import React from 'react';
import { Info, AlertTriangle, CheckCircle, Ban } from 'lucide-react';

const variants = {
  info: { 
    styles: "bg-blue-50 border-blue-200 text-blue-900", 
    icon: <Info className="w-5 h-5 text-blue-600" /> 
  },
  warning: { 
    styles: "bg-amber-50 border-amber-200 text-amber-900", 
    icon: <AlertTriangle className="w-5 h-5 text-amber-600" /> 
  },
  success: { 
    styles: "bg-emerald-50 border-emerald-200 text-emerald-900", 
    icon: <CheckCircle className="w-5 h-5 text-emerald-600" /> 
  },
  danger: { 
    styles: "bg-red-50 border-red-200 text-red-900", 
    icon: <Ban className="w-5 h-5 text-red-600" /> 
  },
};

const Callout = ({ type = "info", title, children }) => {
  const variant = variants[type] || variants.info;

  return (
    <div className={`flex gap-3 p-4 rounded-lg border my-6 ${variant.styles}`}>
      <div className="flex-shrink-0 mt-0.5">
        {variant.icon}
      </div>
      <div>
        {title && <h4 className="font-bold text-sm mb-1 opacity-90">{title}</h4>}
        <div className="text-sm leading-relaxed opacity-90">
          {children}
        </div>
      </div>
    </div>
  );
};

export default Callout;