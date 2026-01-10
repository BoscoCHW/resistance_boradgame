import { useEffect } from 'react';
import { AnalyticsChannel } from '../services/phoenixChannel';
import { useAnalyticsStore } from '../store/analyticsStore';

export function useAnalytics() {
  const updateStats = useAnalyticsStore((state) => state.updateStats);
  const setConnected = useAnalyticsStore((state) => state.setConnected);

  useEffect(() => {
    const channel = new AnalyticsChannel();

    const disconnect = channel.connect((stats) => {
      updateStats(stats);
      setConnected(true);
    });

    return () => {
      setConnected(false);
      disconnect();
    };
  }, [updateStats, setConnected]);
}
