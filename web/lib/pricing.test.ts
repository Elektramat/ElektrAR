// Runs the shared cases that the Swift tests also run. `npm test` (node --test).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { billedPieces, quote, type SalesUnit } from "./pricing.ts";
import { euro, meters, orderLength, pieces } from "./format.ts";

const cases = JSON.parse(readFileSync(new URL("../../shared/pricing-cases.json", import.meta.url), "utf8")) as {
  pieces: { required: number; sales: SalesUnit; pieces: number[] }[];
  quotes: { measured: number; reserve: number; pricePerMeter: number; sales: SalesUnit;
            quote: { billedLength: number; price: number } | null }[];
};

test("shared pieces cases", () => {
  for (const c of cases.pieces) {
    assert.deepEqual(billedPieces(c.required, c.sales), c.pieces, `required ${c.required}`);
  }
});

test("shared quote cases", () => {
  for (const c of cases.quotes) {
    const q = quote({ pricePerMeter: c.pricePerMeter, sales: c.sales }, c.measured, c.reserve);
    assert.equal(q?.billedLength ?? null, c.quote?.billedLength ?? null, `measured ${c.measured}`);
    assert.equal(q?.price ?? null, c.quote?.price ?? null, `measured ${c.measured}`);
  }
});

test("invalid input gives no quote", () => {
  const cable = { pricePerMeter: 1, sales: { type: "perMeter", step: 1, minimum: 1 } as SalesUnit };
  assert.equal(quote(cable, -1, 0.15), null);
  assert.equal(quote(cable, Number.NaN, 0.15), null);
  assert.equal(quote(cable, Number.POSITIVE_INFINITY, 0.15), null);
});

test("huge length falls back without hanging", () => {
  const p = billedPieces(50_000, { type: "fixedLengths", lengthsM: [10, 100] });
  assert.equal(p.reduce((a, b) => a + b, 0), 50_000);
});

test("Dutch formatting", () => {
  assert.equal(meters(7.4), "7,4 m");
  assert.equal(orderLength(10), "10 m");
  assert.equal(orderLength(3.5), "3,5 m");
  assert.equal(pieces([100, 25]), "100 m + 25 m");
  assert.match(euro(9.9), /€\s9,90/);
});
