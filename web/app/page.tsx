"use client";

import Image from "next/image";
import { useMemo, useRef, useState } from "react";
import catalog from "@/lib/cables.json";
import { useCart, linePrice } from "@/lib/cart";
import { useIsIOS, useStoredString } from "@/lib/storage";
import { euro, meters, orderLength, pieces } from "@/lib/format";
import { CONNECTION_ALLOWANCE, DEFAULT_RESERVE, quote, type Cable } from "@/lib/pricing";

const cables = catalog as Cable[];
const DISCLAIMER =
  "Dit is een schatting. Controleer de lengte zelf en laat het aansluiten over aan een installateur.";

type Segment = { id: number; text: string };

/** "2,5" and "2.5" both work; empty or invalid gives null. */
function parseMeters(text: string): number | null {
  const trimmed = text.trim().replace(",", ".");
  if (trimmed === "") return null;
  const value = Number(trimmed);
  return Number.isFinite(value) && value >= 0 && value <= 10_000 ? value : null;
}

export default function KabelmeterPage() {
  const cart = useCart();
  const [cableId, setCableId] = useStoredString("kabelmeter.cable", cables[0]?.id ?? "");
  const [segments, setSegments] = useState<Segment[]>([{ id: 1, text: "" }]);
  const [reservePercent, setReservePercent] = useState(Math.round(DEFAULT_RESERVE * 100));
  const [query, setQuery] = useState("");
  const [pickerOpen, setPickerOpen] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const isIOS = useIsIOS();
  const cartDialog = useRef<HTMLDialogElement>(null);
  const nextId = useRef(2);

  const cable = cables.find((c) => c.id === cableId) ?? cables[0];
  const measured = segments.reduce((sum, s) => sum + (parseMeters(s.text) ?? 0), 0);
  const result = cable ? quote(cable, measured, reservePercent / 100) : null;
  const hasSample = cables.some((c) => c.isSample);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return cables;
    return cables.filter((c) => [c.name, c.crossSection, c.use].some((v) => v.toLowerCase().includes(q)));
  }, [query]);

  function chooseCable(id: string) {
    setCableId(id);
    setPickerOpen(false);
    setQuery("");
  }

  function updateSegment(id: number, text: string) {
    setSegments((list) => list.map((s) => (s.id === id ? { ...s, text } : s)));
  }

  function addSegment() {
    setSegments((list) => [...list, { id: nextId.current++, text: "" }]);
  }

  function removeSegment(id: number) {
    setSegments((list) => (list.length === 1 ? [{ id: list[0].id, text: "" }] : list.filter((s) => s.id !== id)));
  }

  function show(message: string) {
    setToast(message);
    setTimeout(() => setToast((current) => (current === message ? null : current)), 2200);
  }

  function addToCart() {
    if (!cable || !result) return;
    cart.add(cable, result.billedLength);
    show(`${orderLength(result.billedLength)} ${cable.name} toegevoegd`);
  }

  return (
    <div className="app">
      <header className="header">
        <div>
          <p className="brand-small">Elektramat</p>
          <h1 className="brand">Kabelmeter</h1>
          <p className="tagline">Nooit te weinig of te veel kabel. Vul je route in en de juiste lengte staat in je winkelmand.</p>
        </div>
        <button className="icon-button" aria-label={`Winkelmand, ${cart.items.length} artikelen`}
                onClick={() => cartDialog.current?.showModal()}>
          <span aria-hidden>🛒</span>
          {cart.items.length > 0 && <span className="badge">{cart.items.length}</span>}
        </button>
      </header>

      <main>
        <section className="card" aria-labelledby="kabel">
          <h2 id="kabel"><span className="step">1</span>Kies je kabel</h2>
          {cable && !pickerOpen && (
            <button className="cable-row" onClick={() => setPickerOpen(true)} aria-label={`Gekozen: ${cable.name}. Wijzig kabel`}>
              <CablePhoto cable={cable} />
              <div>
                <p className="cable-name">{cable.name}</p>
                <p className="cable-meta">{cable.crossSection} · {euro(cable.pricePerMeter)} per meter · {cable.stock}</p>
                {cable.isSample && <span className="sample">Voorbeelddata</span>}
              </div>
              <span className="selected">Wijzig</span>
            </button>
          )}
          {pickerOpen && (
            <div>
              <input className="search" type="search" placeholder="Zoek kabel" value={query} autoFocus
                     onChange={(e) => setQuery(e.target.value)} aria-label="Zoek kabel" />
              {filtered.length === 0 && <p className="muted">Geen kabel gevonden voor “{query}”.</p>}
              {filtered.map((c) => (
                <button key={c.id} className="cable-row" onClick={() => chooseCable(c.id)} aria-pressed={c.id === cableId}>
                  <CablePhoto cable={c} />
                  <div>
                    <p className="cable-name">{c.name}</p>
                    <p className="cable-meta">{c.crossSection} · {euro(c.pricePerMeter)} per meter</p>
                  </div>
                  {c.id === cableId && <span className="selected">✓</span>}
                </button>
              ))}
            </div>
          )}
        </section>

        <section className="card" aria-labelledby="route">
          <h2 id="route"><span className="step">2</span>Vul de lengte van je route in</h2>
          <p className="muted" style={{ marginBottom: 12 }}>
            Meet langs de muur: omhoog, opzij en omlaag apart. Per stuk in meters.
          </p>
          {segments.map((s, index) => {
            const invalid = s.text.trim() !== "" && parseMeters(s.text) === null;
            return (
              <div className="segment" key={s.id}>
                <label htmlFor={`seg-${s.id}`}>Stuk {index + 1}</label>
                <input id={`seg-${s.id}`} inputMode="decimal" placeholder="0,0" value={s.text}
                       aria-invalid={invalid} autoComplete="off"
                       onChange={(e) => updateSegment(s.id, e.target.value)} />
                <button className="ghost" aria-label={`Verwijder stuk ${index + 1}`} onClick={() => removeSegment(s.id)}>✕</button>
              </div>
            );
          })}
          <button className="link-button" onClick={addSegment}>+ Stuk toevoegen</button>
          <div className="note">
            {isIOS
              ? "Meten met de camera kan in de Kabelmeter-app voor iPhone. Safari op de iPhone ondersteunt geen AR-meting in de browser."
              : "Meten met de camera kan in de Kabelmeter-app voor iPhone. In de browser vul je de lengte zelf in."}
          </div>
        </section>

        <section className="card" aria-labelledby="bestel">
          <h2 id="bestel"><span className="step">3</span>Bestel de juiste lengte</h2>
          <p className="muted">
            We rekenen {reservePercent}% reserve en {orderLength(CONNECTION_ALLOWANCE)} voor de aansluitingen, afgerond
            zoals de kabel verkocht wordt. {DISCLAIMER}
          </p>
          {hasSample && <p className="muted"><span className="sample">Voorbeelddata</span> Sommige prijzen zijn voorbeelden.</p>}
        </section>
      </main>

      <div className="price-bar" role="region" aria-label="Prijs">
        <div className="price-inner">
          <div className="price-top">
            <div className="lengths" aria-live="polite">
              <p>Gemeten: {meters(measured)}</p>
              <p>Te bestellen: {result ? pieces(result.pieces) : "–"}</p>
            </div>
            <div className="price" aria-live="polite">
              {result ? euro(result.price) : cable ? <>{euro(cable.pricePerMeter)}<small>per meter</small></> : "–"}
            </div>
          </div>
          <div className="reserve">
            <span>Reserve {reservePercent}% + {orderLength(CONNECTION_ALLOWANCE)} aansluiting</span>
            <div className="stepper">
              <button aria-label="Minder reserve" disabled={reservePercent <= 0}
                      onClick={() => setReservePercent((r) => Math.max(0, r - 5))}>−</button>
              <button aria-label="Meer reserve" disabled={reservePercent >= 30}
                      onClick={() => setReservePercent((r) => Math.min(30, r + 5))}>+</button>
            </div>
          </div>
          <button className="cta" disabled={!result} onClick={addToCart}>
            {result ? `Voeg ${pieces(result.pieces)} toe aan winkelmand` : "Vul eerst een lengte in"}
          </button>
        </div>
      </div>

      <dialog ref={cartDialog} aria-labelledby="cart-title" onClick={(e) => e.target === cartDialog.current && cartDialog.current?.close()}>
        <div className="sheet">
          <div className="sheet-head">
            <h2 id="cart-title">Winkelmand</h2>
            <button className="link-button" onClick={() => cartDialog.current?.close()}>Klaar</button>
          </div>
          {cart.items.length === 0 && <p className="muted">Je winkelmand is leeg. Vul een route in en voeg de kabel toe.</p>}
          {cart.items.map((item) => (
            <div className="line" key={item.cableId}>
              <div className="line-top"><span>{item.name}</span><span>{euro(linePrice(item))}</span></div>
              <p className="cable-meta">{item.crossSection} · {orderLength(item.meters)} × {euro(item.pricePerMeter)} per meter</p>
              <a className="secondary-cta" href={item.productUrl} target="_blank" rel="noopener noreferrer">
                Bestel op elektramat.nl
              </a>
              <button className="link-button" onClick={() => cart.remove(item.cableId)}>Verwijder</button>
            </div>
          ))}
          {cart.items.length > 0 && (
            <>
              <div className="total"><span>Totaal</span><span>{euro(cart.total)}</span></div>
              <button className="link-button" onClick={cart.clear}>Winkelmand leegmaken</button>
            </>
          )}
          <p className="muted">{DISCLAIMER}</p>
        </div>
      </dialog>

      {toast && <div className="toast" role="status">{toast}</div>}
    </div>
  );
}

function CablePhoto({ cable }: { cable: Cable }) {
  // Photos are copied from the iPhone app's bundle by scripts/sync-catalog.mjs.
  return <Image className="cable-photo" src={`/cables/${cable.sku}.jpg`} alt="" width={56} height={56} />;
}
