import { useState } from "react";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { vscDarkPlus } from "react-syntax-highlighter/dist/esm/styles/prism"; // VS Code Dark Teması
import { Copy, Check } from "lucide-react";

const CodeBlock = ({ code, language = "cpp" }) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000); // 2 saniye sonra ikonu geri çevir
  };

  return (
    <div className="relative group rounded-lg overflow-hidden my-4 border border-gray-700">
      {/* Kopyala Butonu */}
      <button
        onClick={handleCopy}
        className="absolute right-2 top-2 p-2 bg-gray-800 text-gray-300 rounded hover:bg-gray-700 transition-all opacity-0 group-hover:opacity-100"
        title="Kodu Kopyala"
      >
        {copied ? <Check size={16} className="text-green-400" /> : <Copy size={16} />}
      </button>

      {/* Kod Alanı */}
      <SyntaxHighlighter
        language={language}
        style={vscDarkPlus}
        customStyle={{ margin: 0, padding: "1.5rem", fontSize: "0.9rem" }}
        showLineNumbers={true}
      >
        {code}
      </SyntaxHighlighter>
    </div>
  );
};

export default CodeBlock;