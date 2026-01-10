import { Room } from '../store/roomsStore';

const API_URL = import.meta.env.VITE_PHOENIX_HTTP_URL || 'http://localhost:4000/api';

interface RoomsResponse {
  data: Room[];
  timestamp: string;
  total_count: number;
}

export class RoomsService {
  async fetchRooms(): Promise<Room[]> {
    try {
      const response = await fetch(`${API_URL}/rooms`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data: RoomsResponse = await response.json();
      return data.data;
    } catch (error) {
      console.error('Failed to fetch rooms:', error);
      throw error;
    }
  }
}
