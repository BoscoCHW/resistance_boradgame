import { create } from 'zustand';

export interface Room {
  room_code: string;
  type: 'pregame' | 'game';
  player_count: number;
  max_players: number;
  status: string;
  // Pregame-specific
  ready_count?: number;
  // Game-specific
  round?: number;
  stage?: string;
}

interface RoomsStore {
  rooms: Room[];
  loading: boolean;
  error: string | null;
  lastUpdated: Date | null;
  setRooms: (rooms: Room[]) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearRooms: () => void;
}

export const useRoomsStore = create<RoomsStore>((set) => ({
  rooms: [],
  loading: false,
  error: null,
  lastUpdated: null,
  setRooms: (rooms) =>
    set({
      rooms,
      lastUpdated: new Date(),
      error: null,
    }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error, loading: false }),
  clearRooms: () => set({ rooms: [], error: null }),
}));
