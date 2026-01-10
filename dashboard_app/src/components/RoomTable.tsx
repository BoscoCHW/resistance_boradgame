import React from 'react';
import { useRoomsStore } from '../store/roomsStore';
import { useRooms } from '../hooks/useRooms';

export const RoomTable: React.FC = () => {
  useRooms(); // Start polling when component mounts

  const { rooms, loading, error, lastUpdated } = useRoomsStore();

  // Sort rooms: pregame first, then by room code
  const sortedRooms = [...rooms].sort((a, b) => {
    if (a.type !== b.type) {
      return a.type === 'pregame' ? -1 : 1;
    }
    return a.room_code.localeCompare(b.room_code);
  });

  return (
    <div className="bg-white rounded-lg shadow-lg p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-2xl font-bold text-gray-800">Active Rooms</h2>
        <div className="text-sm text-gray-500">
          {lastUpdated && (
            <span>Last updated: {lastUpdated.toLocaleTimeString()}</span>
          )}
        </div>
      </div>

      {error && (
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          Error: {error}
        </div>
      )}

      {loading && rooms.length === 0 ? (
        <div className="text-center py-8 text-gray-500">Loading rooms...</div>
      ) : rooms.length === 0 ? (
        <div className="text-center py-8 text-gray-500">No active rooms</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Room Code
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Type
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Players
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {sortedRooms.map((room) => (
                <tr key={room.room_code} className="hover:bg-gray-50">
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-mono font-bold text-gray-900">
                    {room.room_code}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span
                      className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${
                        room.type === 'pregame'
                          ? 'bg-blue-100 text-blue-800'
                          : 'bg-green-100 text-green-800'
                      }`}
                    >
                      {room.type === 'pregame' ? 'Lobby' : 'In Game'}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {room.player_count}/{room.max_players}
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-500">
                    {room.status}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};
