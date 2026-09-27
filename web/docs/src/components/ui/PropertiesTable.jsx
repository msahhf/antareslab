import React from 'react';

const PropertiesTable = ({ headers, data }) => {
  return (
    <div className="overflow-x-auto my-6 border border-gray-200 rounded-lg">
      <table className="w-full text-sm text-left">
        <thead className="bg-gray-50 text-gray-700 font-semibold border-b border-gray-200">
          <tr>
            {headers.map((head, i) => (
              <th key={i} className="px-6 py-3">{head}</th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {data.map((row, i) => (
            <tr key={i} className="hover:bg-gray-50/50">
              {row.map((cell, j) => (
                <td key={j} className="px-6 py-3 text-gray-600 font-mono">
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

export default PropertiesTable;