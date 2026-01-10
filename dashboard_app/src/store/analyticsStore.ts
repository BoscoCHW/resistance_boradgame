import { create } from 'zustand';
import { AnalyticsStats } from '../services/phoenixChannel';

interface AnalyticsStore {
  stats: AnalyticsStats;
  connected: boolean;
  updateStats: (newStats: Partial<AnalyticsStats>) => void;
  setConnected: (connected: boolean) => void;
}

export const useAnalyticsStore = create<AnalyticsStore>((set) => ({
  stats: {
    site_visits: 0,
    rooms_created: 0,
    games_started: 0,
    good_team_wins: 0,
    bad_team_wins: 0,
  },
  connected: false,
  updateStats: (newStats) =>
    set((state) => ({
      stats: { ...state.stats, ...newStats },
    })),
  setConnected: (connected) => set({ connected }),
}));
