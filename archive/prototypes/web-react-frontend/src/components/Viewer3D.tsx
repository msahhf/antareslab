import React, { Suspense } from 'react';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Stage, useGLTF } from '@react-three/drei';

// This component expects a GLTF or GLB URL. 
// Open3D outputs PLY/OBJ, so we might need a converter or a different loader in the future,
// but for standard web viewing, GLTF is preferred. We will mock it for now.
const Model = ({ url }: { url: string }) => {
  // const { scene } = useGLTF(url); // Requires an actual GLTF file
  return (
    <mesh>
      <boxGeometry args={[1, 1, 1]} />
      <meshStandardMaterial color="hotpink" />
    </mesh>
  );
};

interface ViewerProps {
  modelUrl?: string;
}

const Viewer3D: React.FC<ViewerProps> = ({ modelUrl }) => {
  return (
    <div className="w-full h-[500px] bg-slate-900 rounded-xl border border-slate-800 overflow-hidden relative">
      <div className="absolute top-4 left-4 z-10">
         <span className="bg-slate-800/80 backdrop-blur-md text-teal-400 px-3 py-1 rounded-full text-xs font-semibold uppercase tracking-wider border border-teal-500/20">
           Live 3D View
         </span>
      </div>
      <Canvas shadows dpr={[1, 2]} camera={{ position: [0, 0, 4], fov: 50 }}>
        <Suspense fallback={null}>
          <Stage environment="city" intensity={0.5}>
            <Model url={modelUrl || ""} />
          </Stage>
        </Suspense>
        <OrbitControls makeDefault autoRotate autoRotateSpeed={0.5} />
      </Canvas>
    </div>
  );
};

export default Viewer3D;
