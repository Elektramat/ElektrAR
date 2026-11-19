"use client";

import { useCallback, useMemo } from "react";
import { useStoredString } from "./storage.ts";
import { roundToCents, type Cable } from "./pricing.ts";

export type CartItem = {
  cableId: string;
  sku: string;
  name: string;
  crossSection: string;
  pricePerMeter: number;
  meters: number;
  productUrl: string;
  isSample: boolean;
};

const KEY = "kabelmeter.cart.v1";

export const linePrice = (item: CartItem) => roundToCents(item.meters * item.pricePerMeter);

function parse(raw: string): CartItem[] {
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

/** In-app cart in localStorage. The same cable twice becomes one line, like the iPhone app. */
export function useCart() {
  const [raw, setRaw] = useStoredString(KEY, "[]");
  const items = useMemo(() => parse(raw), [raw]);
  const read = useCallback(() => parse(localStorage.getItem(KEY) ?? "[]"), []);
  const save = useCallback((next: CartItem[]) => setRaw(JSON.stringify(next)), [setRaw]);

  const add = useCallback((cable: Cable, meters: number) => {
    if (!Number.isFinite(meters) || meters <= 0) return;
    const current = read();
    const existing = current.find((i) => i.cableId === cable.id);
    save(existing
      ? current.map((i) => (i.cableId === cable.id ? { ...i, meters: i.meters + meters } : i))
      : [...current, { cableId: cable.id, sku: cable.sku, name: cable.name, crossSection: cable.crossSection,
                       pricePerMeter: cable.pricePerMeter, meters, productUrl: cable.productUrl,
                       isSample: cable.isSample }]);
  }, [read, save]);

  const remove = useCallback((cableId: string) => save(read().filter((i) => i.cableId !== cableId)), [read, save]);
  const clear = useCallback(() => save([]), [save]);
  const total = roundToCents(items.reduce((sum, i) => sum + linePrice(i), 0));

  return { items, add, remove, clear, total };
}
