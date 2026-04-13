import React from 'react';

// Mock data for sessions
const dummySessions = [
  { id: '1704067200', count: 36, status: 'Completed', date: '2026-01-01 12:00' },
  { id: '1704070800', count: 18, status: 'Processing', date: '2026-01-01 13:00' },
  { id: '1704157200', count: 36, status: 'Pending', date: '2026-01-02 13:00' },
];

const SessionList = () => {
  return (
    <div className="bg-slate-900 rounded-xl border border-slate-800 overflow-hidden flex flex-col h-full">
      <div className="px-6 py-4 border-b border-slate-800 flex justify-between items-center">
        <h2 className="text-lg font-semibold text-slate-100">ESP32 Sessions</h2>
        <button className="text-teal-400 hover:text-teal-300 text-sm font-medium transition-colors">
          Refresh
        </button>
      </div>
      
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {dummySessions.map((session) => (
          <div key={session.id} className="bg-slate-800/50 hover:bg-slate-800 border border-slate-700/50 rounded-lg p-4 cursor-pointer transition-all group">
            <div className="flex justify-between items-start mb-2">
              <div>
                <span className="text-xs text-slate-400 block mb-1">{session.date}</span>
                <h3 className="text-slate-200 font-medium group-hover:text-teal-400 transition-colors">Session {session.id}</h3>
              </div>
              <span className={`px-2.5 py-1 rounded text-xs font-semibold ${
                session.status === 'Completed' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 
                session.status === 'Processing' ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20' : 
                'bg-slate-700 text-slate-300 border border-slate-600'
              }`}>
                {session.status}
              </span>
            </div>
            
            <div className="flex items-center gap-4 text-sm text-slate-400 mt-3 pt-3 border-t border-slate-700/50">
               <div className="flex items-center gap-1.5">
                  <div className="w-1.5 h-1.5 rounded-full bg-slate-500"></div>
                  <span>{session.count} images</span>
               </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default SessionList;
