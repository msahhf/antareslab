import { useState, useEffect } from 'react';
import Layout from './components/Layout';
import SessionList from './components/SessionList';
import Viewer3D from './components/Viewer3D';
import CameraStream from './components/CameraStream';
import { ProgressStream } from './services/api';

function App() {
  const [jobId, setJobId] = useState<string | null>(null);
  const [progress, setProgress] = useState<number>(0);
  const [status, setStatus] = useState<string>('Idle');

  useEffect(() => {
    let stream: ProgressStream | null = null;

    if (jobId) {
      stream = new ProgressStream();
      stream.connect(
        jobId,
        (data) => {
          setProgress(data.progress || 0);
          setStatus(data.status || 'Processing...');
          if (data.progress === 100) {
             setStatus('Completed');
             setJobId(null);
          }
        },
        (err) => {
          console.error("SSE Error:", err);
          setStatus('Connection Error / Disconnected');
          setJobId(null);
        }
      );
    }

    return () => {
      if (stream) stream.disconnect();
    };
  }, [jobId]);

  const handleStartProcessing = () => {
    // Generate a mock job ID for now until we fully wire it
    const mockJobId = "job_" + Math.random().toString(36).substring(7);
    setJobId(mockJobId);
    setProgress(0);
    setStatus('Initializing Pipeline...');
  };

  return (
    <Layout>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 h-[calc(100vh-100px)]">
         {/* Left Sidebar (Camera & Sessions) */}
         <div className="lg:col-span-1 h-full flex flex-col gap-6">
           <CameraStream />
           <SessionList />
         </div>

         {/* Right Main Area (3D Viewer & Controls) */}
         <div className="lg:col-span-2 h-full flex flex-col gap-6">
           <Viewer3D />
           
           <div className="bg-slate-900 flex-1 rounded-xl border border-slate-800 p-6 flex flex-col justify-center items-center text-center">
             
             {jobId ? (
               <div className="w-full max-w-md">
                 <h3 className="text-lg font-medium text-slate-200 mb-2">{status}</h3>
                 <div className="w-full bg-slate-800 rounded-full h-3 mb-4 overflow-hidden border border-slate-700">
                   <div className="bg-teal-500 h-3 rounded-full transition-all duration-300" style={{ width: `${progress}%` }}></div>
                 </div>
                 <p className="text-sm text-slate-400">{progress}% Completed</p>
               </div>
             ) : (
               <>
                 <div className="w-16 h-16 rounded-full bg-teal-500/10 flex items-center justify-center mb-4 border border-teal-500/20">
                    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-teal-400">
                      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10"/>
                    </svg>
                 </div>
                 <h3 className="text-lg font-medium text-slate-200 mb-2">Ready for Reconstruction</h3>
                 <p className="text-sm text-slate-400 max-w-sm mb-6">
                   Select pending sessions from the left panel to start the 3D generation process using FastAPI & CUDA.
                 </p>
                 <button 
                   onClick={handleStartProcessing}
                   className="px-5 py-2.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg transition-colors border border-slate-700 font-medium"
                 >
                   Start Processing
                 </button>
               </>
             )}
             
           </div>
         </div>
      </div>
    </Layout>
  );
}

export default App;
