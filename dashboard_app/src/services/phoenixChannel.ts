import { Socket, Channel } from 'phoenix';

const SOCKET_URL = import.meta.env.VITE_PHOENIX_WS_URL || 'ws://localhost:4000/socket';

export interface AnalyticsStats {
  site_visits: number;
  rooms_created: number;
  games_started: number;
  good_team_wins: number;
  bad_team_wins: number;
}

export class AnalyticsChannel {
  private socket: Socket;
  private channel: Channel | null = null;
  private onStatsUpdate: ((stats: Partial<AnalyticsStats>) => void) | null = null;

  constructor() {
    this.socket = new Socket(SOCKET_URL, {
      params: {},
      reconnectAfterMs: (tries) => [1000, 2000, 5000, 10000][tries - 1] || 10000,
    });
  }

  connect(callback: (stats: Partial<AnalyticsStats>) => void) {
    this.onStatsUpdate = callback;
    this.socket.connect();

    this.channel = this.socket.channel('analytics:stats', {});

    this.channel.on('all_stats', (stats: AnalyticsStats) => {
      console.log('Received all stats:', stats);
      this.onStatsUpdate?.(stats);
    });

    this.channel.on('stat_updated', ({ metric, count }: { metric: string; count: number }) => {
      console.log('Stat updated:', metric, count);
      this.onStatsUpdate?.({ [metric as keyof AnalyticsStats]: count });
    });

    this.channel
      .join()
      .receive('ok', () => console.log('Joined analytics channel'))
      .receive('error', (err) => console.error('Failed to join channel:', err));

    return () => this.disconnect();
  }

  disconnect() {
    this.channel?.leave();
    this.socket.disconnect();
  }

  requestStats() {
    this.channel?.push('get_stats', {})
      .receive('ok', (stats) => this.onStatsUpdate?.(stats))
      .receive('error', (err) => console.error('Failed to get stats:', err));
  }
}
