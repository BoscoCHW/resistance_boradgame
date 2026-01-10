import React from 'react';

interface StatCardProps {
  label: string;
  value: number;
  icon: string;
  color: string;
}

export const StatCard: React.FC<StatCardProps> = ({ label, value, icon, color }) => {
  return (
    <div className={`bg-white rounded-lg shadow-lg p-6 border-l-4 ${color}`}>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-gray-500 text-sm uppercase tracking-wide">{label}</p>
          <p className="text-4xl font-bold text-gray-800 mt-2">
            {value.toLocaleString()}
          </p>
        </div>
        <div className="text-5xl">{icon}</div>
      </div>
    </div>
  );
};
