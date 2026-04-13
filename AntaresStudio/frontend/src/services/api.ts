import axios from 'axios';

const API_BASE_URL = 'http://localhost:8000/api';

export const api = axios.create({
  baseURL: API_BASE_URL,
});

export const getEsp32Scans = async () => {
  const response = await api.get('/esp32/scans');
  return response.data;
};

export const startReconstruction = async (imagePaths: string[], outDir: string, mode: string = 'balanced') => {
  const response = await api.post('/pipeline/reconstruct', {
    image_paths: imagePaths,
    out_dir: outDir,
    mode: mode,
  });
  return response.data;
};

// SSE Hook helper (Not a standard React Hook, just a class wrapper)
export class ProgressStream {
  private eventSource: EventSource | null = null;

  connect(jobId: string, onMessage: (data: any) => void, onError: (err: any) => void) {
    this.eventSource = new EventSource(`${API_BASE_URL}/events/${jobId}/progress`);
    
    this.eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        onMessage(data);
      } catch (e) {
        console.error("Failed to parse SSE data", e);
      }
    };

    this.eventSource.onerror = (error) => {
      onError(error);
      this.disconnect();
    };
  }

  disconnect() {
    if (this.eventSource) {
      this.eventSource.close();
      this.eventSource = null;
    }
  }
}
