import { Command } from "cmdk";
import { Search } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { sidebarConfig } from "../../data/sidebarConfig";
import { useSearch } from "../../context/SearchContext"; // Context'i çektik

export default function CommandMenu() {
  const { open, setOpen } = useSearch(); // State artık buradan geliyor
  const navigate = useNavigate();

  const runCommand = (path) => {
    setOpen(false);
    navigate(path);
  };

  return (
    <Command.Dialog
      open={open}
      onOpenChange={setOpen}
      label="Global Arama Menüsü" // ÇÖZÜM 1: DialogTitle hatası için label
      aria-describedby={undefined} // ÇÖZÜM 2: Description hatası için
      className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full max-w-lg bg-white border border-gray-200 shadow-2xl rounded-xl p-2 z-50 animate-in fade-in zoom-in-95 duration-200"
    >
      {/* Radix UI erişilebilirlik için gizli başlık ister, bunu ekleyerek console hatasını kesin çözeriz */}
      <div className="sr-only">
        <h2>AntaresLab Arama</h2>
        <p>Projeler arasında geçiş yapmak için komutları kullanın.</p>
      </div>

      <div
        className="flex items-center border-b px-3 pb-2"
        cmdk-input-wrapper=""
      >
        <Search className="w-5 h-5 text-gray-400 mr-2" />
        <Command.Input
          placeholder="AntaresLab içinde ara..."
          className="w-full py-2 outline-none text-gray-700 text-sm placeholder:text-gray-400"
        />
      </div>

      <Command.List className="max-h-64 overflow-y-auto mt-2 p-1">
        <Command.Empty className="p-4 text-center text-sm text-gray-500">
          Sonuç bulunamadı.
        </Command.Empty>

        {Object.entries(sidebarConfig).map(([key, section]) => (
          <Command.Group
            key={key}
            heading={section.title}
            className="text-xs text-gray-400 font-bold px-2 py-1 mb-1"
          >
            {section.items.map((item) => (
              <Command.Item
                key={item.path}
                className="flex items-center gap-2 px-2 py-2 hover:bg-indigo-50 hover:text-indigo-700 rounded cursor-pointer text-sm text-gray-700 transition-colors aria-selected:bg-indigo-50 aria-selected:text-indigo-700"
                onSelect={() => runCommand(item.path)}
              >
                <span className="opacity-50">{section.icon}</span>
                <span>{item.label}</span>
              </Command.Item>
            ))}
          </Command.Group>
        ))}
      </Command.List>
    </Command.Dialog>
  );
}
