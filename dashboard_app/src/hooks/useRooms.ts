import { useEffect, useRef } from 'react';
import { RoomsService } from '../services/roomsService';
import { useRoomsStore } from '../store/roomsStore';

const POLLING_INTERVAL = 3000; // 3 seconds

export function useRooms() {
  const { setRooms, setLoading, setError } = useRoomsStore();
  const intervalRef = useRef<number | null>(null);
  const serviceRef = useRef(new RoomsService());

  const fetchRooms = async () => {
    try {
      setLoading(true);
      const rooms = await serviceRef.current.fetchRooms();
      setRooms(rooms);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Failed to fetch rooms');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchRooms();

    intervalRef.current = window.setInterval(fetchRooms, POLLING_INTERVAL);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, []); 

  return { refetch: fetchRooms };
}
