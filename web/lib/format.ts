// Dutch number formatting, same output as Kabelmeter/Core/Format.swift.
const nl = "nl-NL";

export const meters = (v: number) =>
  `${v.toLocaleString(nl, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} m`;

export const orderLength = (v: number) =>
  `${v.toLocaleString(nl, { minimumFractionDigits: 0, maximumFractionDigits: 1 })} m`;

export const pieces = (p: number[]) => p.map(orderLength).join(" + ");

export const euro = (v: number) => v.toLocaleString(nl, { style: "currency", currency: "EUR" });
