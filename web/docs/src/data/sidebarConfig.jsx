// SPDX-License-Identifier: Apache-2.0

import { Globe, Code, FileText, Cpu, BookOpen } from "lucide-react";

export const sidebarConfig = {
  architecture: {
    title: "Architecture",
    icon: <Globe size={20} className="text-blue-600" />,
    items: [
      { label: "Overview", path: "/architecture" },
      { label: "System Architecture", path: "/architecture/system" },
    ]
  },
  api: {
    title: "API Reference",
    icon: <Code size={20} className="text-purple-600" />,
    items: [
      { label: "Overview", path: "/api" },
      { label: "Photos API", path: "/api/photos" },
      { label: "Pipeline API", path: "/api/pipeline" },
      { label: "ESP32 API", path: "/api/esp32" },
      { label: "Arduino Commands", path: "/api/arduino" },
    ]
  },
  specs: {
    title: "Specifications",
    icon: <FileText size={20} className="text-amber-600" />,
    items: [
      { label: "Overview", path: "/specs" },
      { label: "UART Protocol", path: "/specs/uart-protocol" },
      { label: "Hardware Interface", path: "/specs/hardware-interface" },
    ]
  },
  electronics: {
    title: "Electronics",
    icon: <Cpu size={20} className="text-emerald-600" />,
    items: [
      { label: "Overview", path: "/electronics" },
      { label: "ESP32 Pinout", path: "/electronics/pinout" },
    ]
  }
};