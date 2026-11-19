"use client";

import { useCallback, useSyncExternalStore } from "react";

// localStorage as an external store: the server render and the first client render
// both see the fallback, then the stored value. No hydration mismatch, no setState in
// an effect. Writes notify every hook that reads the same key.
const listeners = new Set<() => void>();

function subscribe(listener: () => void) {
  listeners.add(listener);
  window.addEventListener("storage", listener);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", listener);
  };
}

export function useStoredString(key: string, fallback: string): [string, (value: string) => void] {
  const value = useSyncExternalStore(
    subscribe,
    () => localStorage.getItem(key) ?? fallback,
    () => fallback,
  );
  const set = useCallback((next: string) => {
    localStorage.setItem(key, next);
    listeners.forEach((l) => l());
  }, [key]);
  return [value, set];
}

/** True on iPhone/iPad; false during the server render. */
export function useIsIOS(): boolean {
  return useSyncExternalStore(
    () => () => {},
    () => /iPhone|iPad|iPod/.test(navigator.userAgent),
    () => false,
  );
}
