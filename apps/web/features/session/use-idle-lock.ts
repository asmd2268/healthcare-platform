'use client';

import {useEffect, useRef, useState} from 'react';

export function useIdleLock(timeoutMinutes = 15) {
  const [locked, setLocked] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    const reset = () => {
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setLocked(true), timeoutMinutes * 60_000);
    };
    const events = ['pointerdown', 'keydown', 'touchstart'];
    events.forEach((event) => window.addEventListener(event, reset));
    reset();
    return () => { events.forEach((event) => window.removeEventListener(event, reset)); if (timer.current) clearTimeout(timer.current); };
  }, [timeoutMinutes]);
  return {locked, lock: () => setLocked(true), unlock: () => setLocked(false)};
}
