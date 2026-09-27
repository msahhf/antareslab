import { BrowserRouter, Routes, Route } from "react-router-dom";
import CommandMenu from "./components/ui/CommandMenu";
import Home from "./pages/Home";
import DocsLayout from "./components/layout/DocsLayout";
import Esp32Pinout from "./pages/electronics/Esp32Pinout";
import { SearchProvider } from "./context/SearchContext";

// Placeholder pages for sections under construction
const PagePlaceholder = ({ title }) => (
  <div className="prose lg:prose-xl">
    <h1 className="text-3xl font-bold text-gray-900 mb-4">{title}</h1>
    <p className="text-gray-600">
      Documentation for {title} is under construction.
    </p>
    <div className="mt-8 p-4 bg-yellow-50 border border-yellow-200 rounded text-yellow-800">
      🚧 This page is under construction.
    </div>
  </div>
);

function App() {
  return (
    <SearchProvider>
      <BrowserRouter>
        <CommandMenu />

        <Routes>
          {/* Landing Page (outside DocsLayout) */}
          <Route path="/" element={<Home />} />

          {/* Documentation Pages (inside DocsLayout) */}
          <Route element={<DocsLayout />}>
            {/* Architecture */}
            <Route
              path="/architecture"
              element={<PagePlaceholder title="Architecture Overview" />}
            />
            <Route
              path="/architecture/system"
              element={<PagePlaceholder title="System Architecture" />}
            />

            {/* API Reference */}
            <Route
              path="/api"
              element={<PagePlaceholder title="API Reference" />}
            />
            <Route
              path="/api/photos"
              element={<PagePlaceholder title="Photos API" />}
            />
            <Route
              path="/api/pipeline"
              element={<PagePlaceholder title="Pipeline API" />}
            />
            <Route
              path="/api/esp32"
              element={<PagePlaceholder title="ESP32 API" />}
            />
            <Route
              path="/api/arduino"
              element={<PagePlaceholder title="Arduino Commands" />}
            />

            {/* Specifications */}
            <Route
              path="/specs"
              element={<PagePlaceholder title="Specifications" />}
            />
            <Route
              path="/specs/uart-protocol"
              element={<PagePlaceholder title="UART Protocol" />}
            />
            <Route
              path="/specs/hardware-interface"
              element={<PagePlaceholder title="Hardware Interface" />}
            />

            {/* Electronics (existing) */}
            <Route
              path="/electronics"
              element={<PagePlaceholder title="Electronics" />}
            />
            <Route path="/electronics/pinout" element={<Esp32Pinout />} />

            {/* Studio (placeholder) */}
            <Route
              path="/studio"
              element={<PagePlaceholder title="Studio" />}
            />

            {/* Web (placeholder) */}
            <Route
              path="/web"
              element={<PagePlaceholder title="Web" />}
            />
          </Route>
        </Routes>
      </BrowserRouter>
    </SearchProvider>
  );
}

export default App;