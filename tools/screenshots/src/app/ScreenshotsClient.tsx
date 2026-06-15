"use client";

import React, { useRef, useEffect, useState, useCallback } from "react";
// html-to-image imported dynamically in the export handler (avoids SSR localStorage error)

// ─── Canvas dimensions (design at largest device size per family) ───────────
const IPHONE_W = 1320;
const IPHONE_H = 2868;
// iPad screenshots are LANDSCAPE — canvas is the long edge × short edge.
const IPAD_W = 2752;
const IPAD_H = 2064;

// ─── iPhone mockup pre-measured constants ────────────────────────────────────
const MK_W = 1022;
const MK_H = 2082;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

// ─── Export sizes ─────────────────────────────────────────────────────────────
const IPHONE_SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
  { label: '6.3"', w: 1206, h: 2622 },
  { label: '6.1"', w: 1125, h: 2436 },
] as const;

const IPAD_SIZES = [
  { label: '13" iPad', w: 2752, h: 2064 },
  { label: '12.9" iPad Pro', w: 2732, h: 2048 },
] as const;

type ExportSize = { label: string; w: number; h: number };

// ─── Design tokens ────────────────────────────────────────────────────────────
const C = {
  bg: "#080810",
  surface: "#0D0D1A",
  surface2: "#12122A",
  orange: "#FF4D00",
  cyan: "#00F5FF",
  violet: "#8B00FF",
  textPrimary: "#F0F0FF",
  textMuted: "#6B7080",
  glassBorder: "rgba(255,255,255,0.08)",
};

// ─── Typography helpers ───────────────────────────────────────────────────────
function label(text: string, w: number, color = C.orange): React.CSSProperties {
  return {
    fontFamily: "var(--font-chakra)",
    fontSize: w * 0.026,
    fontWeight: 700,
    letterSpacing: "0.18em",
    color,
    textTransform: "uppercase" as const,
    lineHeight: 1,
  };
}

function headline(size: number, color = C.textPrimary): React.CSSProperties {
  return {
    fontFamily: "var(--font-bebas)",
    fontSize: size,
    fontWeight: 400,
    color,
    lineHeight: 0.95,
    letterSpacing: "0.02em",
  };
}

function body(size: number, color = C.textMuted): React.CSSProperties {
  return {
    fontFamily: "var(--font-chakra)",
    fontSize: size,
    fontWeight: 400,
    color,
    lineHeight: 1.4,
  };
}

// ─── Phone component ──────────────────────────────────────────────────────────
function Phone({
  src,
  alt,
  style,
  placeholder,
}: {
  src: string;
  alt: string;
  style?: React.CSSProperties;
  placeholder?: string;
}) {
  const [failed, setFailed] = useState(false);

  return (
    <div
      style={{
        position: "relative",
        aspectRatio: `${MK_W}/${MK_H}`,
        ...style,
      }}
    >
      <img
        src="/mockup.png"
        alt=""
        style={{ display: "block", width: "100%", height: "100%" }}
        draggable={false}
      />
      <div
        style={{
          position: "absolute",
          zIndex: 10,
          overflow: "hidden",
          left: `${SC_L}%`,
          top: `${SC_T}%`,
          width: `${SC_W}%`,
          height: `${SC_H}%`,
          borderRadius: `${SC_RX}% / ${SC_RY}%`,
          background: C.surface,
        }}
      >
        {failed ? (
          /* Placeholder — only shown when image fails to load */
          <div
            style={{
              position: "absolute",
              inset: 0,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              gap: 12,
              background: C.surface,
            }}
          >
            <div
              style={{
                width: 48,
                height: 48,
                borderRadius: "50%",
                background: C.surface2,
                border: `2px solid ${C.glassBorder}`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
                <rect x="2" y="2" width="20" height="20" rx="4" stroke={C.textMuted} strokeWidth="1.5" />
                <circle cx="8.5" cy="8.5" r="2" stroke={C.textMuted} strokeWidth="1.5" />
                <path d="M2 16l5-5 4 4 3-3 5 5" stroke={C.textMuted} strokeWidth="1.5" strokeLinejoin="round" />
              </svg>
            </div>
            <span
              style={{
                fontFamily: "var(--font-chakra)",
                fontSize: 13,
                color: C.textMuted,
                textAlign: "center",
                padding: "0 16px",
              }}
            >
              {placeholder ?? "Add screenshot"}
            </span>
          </div>
        ) : (
          <img
            src={src}
            alt={alt}
            style={{
              display: "block",
              width: "100%",
              height: "100%",
              objectFit: "cover",
              objectPosition: "top",
            }}
            draggable={false}
            onError={() => setFailed(true)}
          />
        )}
      </div>
    </div>
  );
}

// ─── Shared decorative elements ───────────────────────────────────────────────
function OrangeGlow({ style }: { style?: React.CSSProperties }) {
  return (
    <div
      style={{
        position: "absolute",
        borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,77,0,0.35) 0%, transparent 70%)",
        pointerEvents: "none",
        ...style,
      }}
    />
  );
}

function CyanGlow({ style }: { style?: React.CSSProperties }) {
  return (
    <div
      style={{
        position: "absolute",
        borderRadius: "50%",
        background: "radial-gradient(circle, rgba(0,245,255,0.25) 0%, transparent 70%)",
        pointerEvents: "none",
        ...style,
      }}
    />
  );
}

function VioletGlow({ style }: { style?: React.CSSProperties }) {
  return (
    <div
      style={{
        position: "absolute",
        borderRadius: "50%",
        background: "radial-gradient(circle, rgba(139,0,255,0.3) 0%, transparent 70%)",
        pointerEvents: "none",
        ...style,
      }}
    />
  );
}

function GridLines({ w, h }: { w: number; h: number }) {
  const cols = 8;
  const rows = 12;
  const lines: React.ReactNode[] = [];
  for (let i = 1; i < cols; i++) {
    lines.push(
      <line
        key={`v${i}`}
        x1={(w / cols) * i}
        y1={0}
        x2={(w / cols) * i}
        y2={h}
        stroke="rgba(255,255,255,0.03)"
        strokeWidth="1"
      />
    );
  }
  for (let i = 1; i < rows; i++) {
    lines.push(
      <line
        key={`h${i}`}
        x1={0}
        y1={(h / rows) * i}
        x2={w}
        y2={(h / rows) * i}
        stroke="rgba(255,255,255,0.03)"
        strokeWidth="1"
      />
    );
  }
  return (
    <svg
      style={{ position: "absolute", inset: 0, pointerEvents: "none" }}
      width={w}
      height={h}
    >
      {lines}
    </svg>
  );
}

function ScanlineOverlay({ w, h }: { w: number; h: number }) {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        pointerEvents: "none",
        background: `repeating-linear-gradient(
          0deg,
          transparent,
          transparent 3px,
          rgba(0,0,0,0.04) 3px,
          rgba(0,0,0,0.04) 4px
        )`,
      }}
    />
  );
}

// ─── Pill badge ───────────────────────────────────────────────────────────────
function Pill({
  children,
  color = C.cyan,
  w,
}: {
  children: React.ReactNode;
  color?: string;
  w: number;
}) {
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: w * 0.012,
        fontFamily: "var(--font-chakra)",
        fontSize: w * 0.028,
        fontWeight: 600,
        color,
        letterSpacing: "0.06em",
        background: `${color}18`,
        border: `1px solid ${color}40`,
        borderRadius: 100,
        padding: `${w * 0.01}px ${w * 0.028}px`,
        lineHeight: 1,
      }}
    >
      {children}
    </span>
  );
}

// ─── Slide 1: Hero ────────────────────────────────────────────────────────────
// Layout: brand top → phone fills middle → gradient fade → tagline at bottom
// Phone is top-anchored at h*0.20 so it never collides with the brand block above.
// A gradient covers the lower ~30% so the tagline text is always legible.
function Slide1({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: "relative", width: w, height: h, background: C.bg, overflow: "hidden" }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <OrangeGlow style={{ width: w * 1.2, height: w * 1.2, top: h * 0.55, left: -w * 0.3 }} />
      <CyanGlow style={{ width: w * 0.9, height: w * 0.9, top: -w * 0.2, right: -w * 0.2 }} />
      <VioletGlow style={{ width: w * 0.6, height: w * 0.6, top: h * 0.25, left: w * 0.5 }} />

      {/* Brand at top — ends around y = h*0.19 */}
      <div style={{
        position: "absolute", top: h * 0.055, left: 0, right: 0, zIndex: 10,
        display: "flex", flexDirection: "column", alignItems: "center", gap: w * 0.018,
      }}>
        <img src="/icon.png" alt="BOBA Playbook" style={{ width: w * 0.16, height: w * 0.16, borderRadius: w * 0.035 }} />
        <span style={label("BOBA PLAYBOOK", w)}>BOBA PLAYBOOK</span>
      </div>

      {/* Phone — top-anchored at h*0.20, clear of brand block above */}
      <Phone
        src="/screenshots/home.png"
        alt="Home screen"
        placeholder="Home screen"
        style={{
          position: "absolute",
          width: w * 0.70,
          top: h * 0.20,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 2,
        }}
      />

      {/* Gradient fade — covers phone bottom so tagline is legible */}
      <div style={{
        position: "absolute",
        bottom: 0, left: 0, right: 0,
        height: h * 0.35,
        background: `linear-gradient(to top, ${C.bg} 45%, transparent)`,
        zIndex: 5,
        pointerEvents: "none",
      }} />

      {/* Tagline — over gradient, always on dark background */}
      <div style={{
        position: "absolute",
        bottom: h * 0.055,
        left: 0, right: 0,
        textAlign: "center",
        zIndex: 10,
      }}>
        <div style={headline(w * 0.09)}>
          Search. Scan.<br />Collect. Play.
        </div>
        <div style={{ marginTop: w * 0.025, ...body(w * 0.031) }}>
          The ultimate BOBA companion app
        </div>
      </div>
    </div>
  );
}

// ─── Slide 2: Search ─────────────────────────────────────────────────────────
// Layout: caption occupies top ~36%, phone is top-anchored at h*0.38 and bleeds
// off the bottom edge — no bottom text, no collision risk.
function Slide2({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: "relative", width: w, height: h, background: C.bg, overflow: "hidden" }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <CyanGlow style={{ width: w * 1.0, height: w * 1.0, top: -w * 0.3, left: -w * 0.2 }} />
      <OrangeGlow style={{ width: w * 0.7, height: w * 0.7, bottom: 0, right: -w * 0.1 }} />

      {/* Caption top — safe zone h*0.06 → ~h*0.36 */}
      <div style={{ position: "absolute", top: h * 0.06, left: w * 0.1, right: w * 0.08, zIndex: 10 }}>
        <div style={label("Search", w)}>THE FULL COLLECTION</div>
        <div style={{ marginTop: w * 0.025, ...headline(w * 0.115) }}>
          Every Card.<br />At Your<br />Fingertips.
        </div>
        <div style={{ marginTop: w * 0.03, ...body(w * 0.031) }}>
          17,968 cards. Instant search.<br />Filter by Weapon, Treatment, Set.
        </div>
        <div style={{ marginTop: w * 0.035, display: "flex", gap: w * 0.02, flexWrap: "nowrap" }}>
          <Pill color={C.cyan} w={w}>17,968 cards</Pill>
          <Pill color={C.orange} w={w}>Full images</Pill>
          <Pill color={C.violet} w={w}>Instant search</Pill>
        </div>
      </div>

      {/* Phone — top-anchored so it starts below the caption */}
      <Phone
        src="/screenshots/search.png"
        alt="Search screen"
        placeholder="Search screen"
        style={{
          position: "absolute",
          width: w * 0.78,
          top: h * 0.38,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 2,
        }}
      />
    </div>
  );
}

// ─── Slide 3: Scan ────────────────────────────────────────────────────────────
// Layout: label+headline at top (h*0.06→h*0.22), narrower phone top-anchored at
// h*0.25 (height ~1773px → bottom at h*0.867), gradient fade at bottom, body+pills
// below phone bottom with guaranteed clearance.
function Slide3({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: "relative", width: w, height: h, overflow: "hidden",
      background: `linear-gradient(160deg, #080810 0%, #0D0820 50%, #080810 100%)` }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <VioletGlow style={{ width: w * 1.1, height: w * 1.1, top: h * 0.3, left: -w * 0.3 }} />
      <CyanGlow style={{ width: w * 0.8, height: w * 0.8, top: -w * 0.1, right: -w * 0.2 }} />

      {/* Caption top — label + headline only; ends well before h*0.25 */}
      <div style={{ position: "absolute", top: h * 0.06, left: w * 0.1, right: w * 0.1, zIndex: 10 }}>
        <div style={label("Scan", w, C.violet)}>CAMERA · ON-DEVICE</div>
        <div style={{ marginTop: w * 0.025, ...headline(w * 0.115) }}>
          Point.<br />Shoot. Add.
        </div>
      </div>

      {/* Phone — top-anchored at h*0.25, width w*0.66 → height ~1773px → bottom at ~h*0.87 */}
      <Phone
        src="/screenshots/scan.png"
        alt="Scan screen"
        placeholder="Scan screen"
        style={{
          position: "absolute",
          width: w * 0.66,
          top: h * 0.25,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 2,
        }}
      />

      {/* Bottom gradient fade — phone fades into bg from h*0.78 downward */}
      <div style={{
        position: "absolute",
        bottom: 0, left: 0, right: 0,
        height: h * 0.28,
        background: `linear-gradient(to top, ${C.bg} 50%, transparent)`,
        zIndex: 5,
        pointerEvents: "none",
      }} />

      {/* Bottom caption — sits below phone bottom (~h*0.87), over gradient */}
      <div style={{
        position: "absolute",
        bottom: h * 0.055,
        left: w * 0.1, right: w * 0.1,
        zIndex: 10,
      }}>
        <div style={body(w * 0.031)}>
          Identifies any card in real time.<br />
          No uploads. Entirely on-device.
        </div>
        <div style={{ marginTop: w * 0.025, display: "flex", gap: w * 0.02 }}>
          <Pill color={C.violet} w={w}>Vision OCR</Pill>
          <Pill color={C.cyan} w={w}>Private</Pill>
        </div>
      </div>
    </div>
  );
}

// ─── Slide 4: Collect ─────────────────────────────────────────────────────────
// Layout: caption at top (h*0.06→~h*0.33), two phones in the lower 65%.
// Back phone: width w*0.50 → height ~1344px. Front phone: width w*0.65 → height ~1747px.
// Both bottom-anchored at h*0.01 → front phone top = 2868-29-1747 = ~1092px = h*0.381
// Caption ends at ~h*0.33 = 947px. Clearance: ~145px. No collision.
function Slide4({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: "relative", width: w, height: h, background: C.bg, overflow: "hidden" }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <OrangeGlow style={{ width: w * 1.0, height: w * 1.0, bottom: -w * 0.2, right: -w * 0.2 }} />
      <CyanGlow style={{ width: w * 0.6, height: w * 0.6, top: -w * 0.1, left: -w * 0.1 }} />

      {/* Caption — top zone, smaller headline to compress vertical footprint */}
      <div style={{ position: "absolute", top: h * 0.06, left: w * 0.1, right: w * 0.1, zIndex: 10 }}>
        <div style={label("Collect", w)}>YOUR COLLECTION</div>
        <div style={{ marginTop: w * 0.025, ...headline(w * 0.1) }}>
          Track what<br />you own.
        </div>
        <div style={{ marginTop: w * 0.03, ...body(w * 0.031) }}>
          Personal · For Sale · For Trade<br />Wanted · Grails
        </div>
        <div style={{ marginTop: w * 0.035, display: "flex", gap: w * 0.02, flexWrap: "wrap" }}>
          <Pill color={C.orange} w={w}>5 designations</Pill>
          <Pill color={C.cyan} w={w}>Cloud sync</Pill>
        </div>
      </div>

      {/* Back phone — smaller, rotated left, raised */}
      <Phone
        src="/screenshots/collect-2.png"
        alt="Collection detail"
        placeholder="Collection detail"
        style={{
          position: "absolute",
          width: w * 0.50,
          bottom: h * 0.10,
          left: -w * 0.04,
          transform: "rotate(-5deg)",
          opacity: 0.6,
          zIndex: 1,
        }}
      />
      {/* Front phone — larger, raised */}
      <Phone
        src="/screenshots/collect.png"
        alt="Collection screen"
        placeholder="Collection screen"
        style={{
          position: "absolute",
          width: w * 0.65,
          bottom: h * 0.10,
          right: -w * 0.04,
          zIndex: 2,
        }}
      />
    </div>
  );
}

// ─── Slide 5: Pricing ─────────────────────────────────────────────────────────
// Layout: caption block (label+headline+body+price widget+pills) occupies top ~42%,
// phone top-anchored at h*0.44 → bleeds off bottom. No collision.
// Caption height estimate: 34+33+288+40+118+66+190+40+37 = ~846px → ends at ~h*0.36.
// Phone starts at h*0.44 — 100px+ clearance.
function Slide5({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: "relative", width: w, height: h, overflow: "hidden",
      background: `linear-gradient(170deg, #080810 0%, #100808 60%, #080810 100%)` }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <OrangeGlow style={{ width: w * 0.9, height: w * 0.9, top: h * 0.5, left: w * 0.1 }} />
      <VioletGlow style={{ width: w * 0.6, height: w * 0.6, top: -w * 0.1, right: -w * 0.1 }} />

      {/* Caption top */}
      <div style={{ position: "absolute", top: h * 0.06, left: w * 0.1, right: w * 0.1, zIndex: 10 }}>
        <div style={label("Pricing", w, C.orange)}>RECENT SOLD COMPS</div>
        <div style={{ marginTop: w * 0.025, ...headline(w * 0.105) }}>
          Real sales.<br />Real prices.
        </div>
        <div style={{ marginTop: w * 0.028, ...body(w * 0.031) }}>
          Live market estimate plus<br />
          recent sold listings, per card.
        </div>

        {/* Price widget */}
        <div style={{
          marginTop: w * 0.04,
          background: C.surface,
          border: `1px solid ${C.glassBorder}`,
          borderRadius: w * 0.035,
          padding: `${w * 0.035}px ${w * 0.05}px`,
          display: "flex",
          justifyContent: "space-between",
        }}>
          {[
            { label: "LOW", value: "$4.99", color: C.cyan },
            { label: "AVG", value: "$12.50", color: C.orange },
            { label: "HIGH", value: "$28.00", color: C.violet },
          ].map(({ label: l, value, color }) => (
            <div key={l} style={{ textAlign: "center" }}>
              <div style={{ fontFamily: "var(--font-chakra)", fontSize: w * 0.02, fontWeight: 700, color: C.textMuted, letterSpacing: "0.15em" }}>{l}</div>
              <div style={{ fontFamily: "var(--font-bebas)", fontSize: w * 0.065, color, letterSpacing: "0.02em", lineHeight: 1.1 }}>{value}</div>
            </div>
          ))}
        </div>

        <div style={{ marginTop: w * 0.028, display: "flex", gap: w * 0.02, flexWrap: "wrap" }}>
          <Pill color={C.orange} w={w}>Recent sales</Pill>
          <Pill color={C.cyan} w={w}>Live market data</Pill>
        </div>
      </div>

      {/* Phone — top-anchored below caption, bleeds off bottom */}
      <Phone
        src="/screenshots/pricing.png"
        alt="Pricing screen"
        placeholder="Pricing screen"
        style={{
          position: "absolute",
          width: w * 0.76,
          top: h * 0.44,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 2,
        }}
      />
    </div>
  );
}

// ─── Slide 6: Play ────────────────────────────────────────────────────────────
// Layout: full caption at top (label+headline+body+pills, ends ~h*0.37),
// phone top-anchored at h*0.40 and bleeds off the bottom. All text above phone.
function Slide6({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: "relative", width: w, height: h, overflow: "hidden",
      background: `linear-gradient(150deg, #080810 0%, #080818 50%, #0A0810 100%)` }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <VioletGlow style={{ width: w * 1.1, height: w * 1.1, top: h * 0.1, left: -w * 0.3 }} />
      <OrangeGlow style={{ width: w * 0.7, height: w * 0.7, bottom: 0, right: -w * 0.1 }} />

      {/* Caption — full feature info at top, ends well before h*0.40 */}
      <div style={{ position: "absolute", top: h * 0.06, left: w * 0.1, right: w * 0.1, zIndex: 10 }}>
        <div style={label("Play", w, C.violet)}>RULES · STRATEGY · DECKS</div>
        <div style={{ marginTop: w * 0.025, ...headline(w * 0.105) }}>
          Know the rules.<br />Win the game.
        </div>
        <div style={{ marginTop: w * 0.028, ...body(w * 0.031) }}>
          Rookie to playmaker.<br />Rules, strategy, decks.
        </div>
        <div style={{ marginTop: w * 0.035, display: "flex", gap: w * 0.016, flexWrap: "nowrap" }}>
          <Pill color={C.violet} w={w}>Deck builder</Pill>
          <Pill color={C.orange} w={w}>Format legality</Pill>
          <Pill color={C.cyan} w={w}>Strategy guides</Pill>
        </div>
      </div>

      {/* Phone — raised closer to caption */}
      <Phone
        src="/screenshots/play.png"
        alt="Play screen"
        placeholder="Play screen"
        style={{
          position: "absolute",
          width: w * 0.76,
          top: h * 0.32,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 2,
        }}
      />
    </div>
  );
}

// ─── Slide 7: Decks (deck builder feature) ───────────────────────────────────
// Layout: caption block at top (label+headline+body+pills, ends ~h*0.36),
// phone top-anchored at h*0.40 and bleeds off the bottom.
function SlideDecks({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: "relative", width: w, height: h, overflow: "hidden",
      background: `linear-gradient(155deg, #080810 0%, #0A0A20 50%, #080810 100%)` }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <CyanGlow style={{ width: w * 1.0, height: w * 1.0, top: h * 0.05, right: -w * 0.3 }} />
      <OrangeGlow style={{ width: w * 0.7, height: w * 0.7, bottom: 0, left: -w * 0.1 }} />
      <VioletGlow style={{ width: w * 0.5, height: w * 0.5, top: h * 0.4, left: w * 0.5 }} />

      {/* Caption — top zone */}
      <div style={{ position: "absolute", top: h * 0.06, left: w * 0.1, right: w * 0.1, zIndex: 10 }}>
        <div style={label("Decks", w, C.cyan)}>DECK BUILDER</div>
        <div style={{ marginTop: w * 0.025, ...headline(w * 0.105) }}>
          Build legal.<br />Battle ready.
        </div>
        <div style={{ marginTop: w * 0.028, ...body(w * 0.031) }}>
          Format legality. Weapon counts.<br />
          Battle Day Score totals.
        </div>
        <div style={{ marginTop: w * 0.035, display: "flex", gap: w * 0.016, flexWrap: "nowrap" }}>
          <Pill color={C.cyan} w={w}>Format legality</Pill>
          <Pill color={C.orange} w={w}>Battle Day Score</Pill>
          <Pill color={C.violet} w={w}>Save & sync</Pill>
        </div>
      </div>

      {/* Phone — top-anchored below caption, bleeds off bottom */}
      <Phone
        src="/screenshots/decks.png"
        alt="Decks editor"
        placeholder="Decks editor"
        style={{
          position: "absolute",
          width: w * 0.76,
          top: h * 0.40,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 2,
        }}
      />
    </div>
  );
}

// ─── Slide 8: More features ───────────────────────────────────────────────────
function Slide7({ w, h }: { w: number; h: number }) {
  const features = [
    { icon: "🔍", text: "Search 17K+ cards" },
    { icon: "📸", text: "On-device scan" },
    { icon: "📦", text: "Collection tracker" },
    { icon: "💰", text: "Live market prices" },
    { icon: "🃏", text: "Deck builder" },
    { icon: "📱", text: "iPad first-class" },
    { icon: "🔗", text: "Public collections" },
    { icon: "🛒", text: "Breaks & stores" },
  ];

  return (
    <div style={{ position: "relative", width: w, height: h, overflow: "hidden",
      background: `linear-gradient(180deg, #080810 0%, #0D0D1A 100%)` }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <OrangeGlow style={{ width: w * 0.8, height: w * 0.8, top: h * 0.3, left: -w * 0.2 }} />
      <CyanGlow style={{ width: w * 0.7, height: w * 0.7, top: h * 0.2, right: -w * 0.2 }} />
      <VioletGlow style={{ width: w * 0.5, height: w * 0.5, bottom: h * 0.1, left: w * 0.3 }} />

      {/* App icon + wordmark */}
      <div style={{
        position: "absolute",
        top: h * 0.06,
        left: 0,
        right: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: w * 0.018,
      }}>
        <img
          src="/icon.png"
          alt="BOBA Playbook"
          style={{ width: w * 0.20, height: w * 0.20, borderRadius: w * 0.045 }}
        />
        <div style={label("", w)}>
          <span style={headline(w * 0.07)}>BOBA PLAYBOOK</span>
        </div>
      </div>

      {/* Headline */}
      <div style={{
        position: "absolute",
        top: h * 0.26,
        left: 0,
        right: 0,
        textAlign: "center",
        padding: `0 ${w * 0.08}px`,
      }}>
        <div style={headline(w * 0.13)}>
          And so<br />much more.
        </div>
        <div style={{ marginTop: w * 0.025, ...body(w * 0.033) }}>
          Everything you need for BOBA.<br />Made by fans.
        </div>
      </div>

      {/* Feature grid — pulled up close to headline */}
      <div style={{
        position: "absolute",
        top: h * 0.44,
        left: w * 0.07,
        right: w * 0.07,
        display: "grid",
        gridTemplateColumns: "1fr 1fr",
        gap: w * 0.03,
      }}>
        {features.map(({ icon, text }) => (
          <div
            key={text}
            style={{
              display: "flex",
              alignItems: "center",
              gap: w * 0.03,
              background: C.surface,
              border: `1px solid ${C.glassBorder}`,
              borderRadius: w * 0.028,
              padding: `${w * 0.032}px ${w * 0.035}px`,
            }}
          >
            <span style={{ fontSize: w * 0.048 }}>{icon}</span>
            <span style={{ fontFamily: "var(--font-chakra)", fontSize: w * 0.032, fontWeight: 500, color: C.textPrimary }}>{text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── iPad mockup component (CSS-only frame) ──────────────────────────────────
// Aspect 770/1000 matches the inner-screen 92% × 94.4% to a 3:4 device — using
// the wrong outer aspect causes black bars or stretched screenshots.
function IPad({
  src,
  alt,
  style,
  placeholder,
  landscape = false,
}: {
  src: string;
  alt: string;
  style?: React.CSSProperties;
  placeholder?: string;
  landscape?: boolean;
}) {
  const [failed, setFailed] = useState(false);

  // Bezel geometry transposes between orientations so the frame stays even
  // and the capture fills a 4:3 screen with no black bars. Outer aspect flips
  // 770/1000 (portrait) ↔ 1000/770 (landscape); the camera moves to the
  // short (left) edge in landscape.
  const outerAspect = landscape ? "1000/770" : "770/1000";
  const screen = landscape
    ? { left: "2.8%", top: "4%", width: "94.4%", height: "92%" }
    : { left: "4%", top: "2.8%", width: "92%", height: "94.4%" };
  const camera: React.CSSProperties = landscape
    ? { left: "1.2%", top: "50%", transform: "translateY(-50%)", width: "0.65%", height: "0.9%" }
    : { top: "1.2%", left: "50%", transform: "translateX(-50%)", width: "0.9%", height: "0.65%" };

  return (
    <div style={{ position: "relative", aspectRatio: outerAspect, ...style }}>
      <div
        style={{
          width: "100%",
          height: "100%",
          borderRadius: "5% / 3.6%",
          background: "linear-gradient(180deg, #2C2C2E 0%, #1C1C1E 100%)",
          position: "relative",
          overflow: "hidden",
          boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.1), 0 8px 40px rgba(0,0,0,0.6)",
        }}
      >
        {/* Front camera dot */}
        <div
          style={{
            position: "absolute",
            ...camera,
            borderRadius: "50%",
            background: "#111113",
            border: "1px solid rgba(255,255,255,0.08)",
            zIndex: 20,
          }}
        />
        {/* Bezel edge highlight */}
        <div
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: "5% / 3.6%",
            border: "1px solid rgba(255,255,255,0.06)",
            pointerEvents: "none",
            zIndex: 15,
          }}
        />
        {/* Screen area */}
        <div
          style={{
            position: "absolute",
            ...screen,
            borderRadius: "2.2% / 1.6%",
            overflow: "hidden",
            background: C.surface,
          }}
        >
          {failed ? (
            <div
              style={{
                position: "absolute",
                inset: 0,
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                gap: 12,
                background: C.surface,
              }}
            >
              <div
                style={{
                  width: 64,
                  height: 64,
                  borderRadius: "50%",
                  background: C.surface2,
                  border: `2px solid ${C.glassBorder}`,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none">
                  <rect x="2" y="2" width="20" height="20" rx="4" stroke={C.textMuted} strokeWidth="1.5" />
                  <circle cx="8.5" cy="8.5" r="2" stroke={C.textMuted} strokeWidth="1.5" />
                  <path d="M2 16l5-5 4 4 3-3 5 5" stroke={C.textMuted} strokeWidth="1.5" strokeLinejoin="round" />
                </svg>
              </div>
              <span
                style={{
                  fontFamily: "var(--font-chakra)",
                  fontSize: 16,
                  color: C.textMuted,
                  textAlign: "center",
                  padding: "0 24px",
                }}
              >
                {placeholder ?? "Add iPad screenshot"}
              </span>
            </div>
          ) : (
            <img
              src={src}
              alt={alt}
              style={{
                display: "block",
                width: "100%",
                height: "100%",
                objectFit: "cover",
                objectPosition: "top",
              }}
              draggable={false}
              onError={() => setFailed(true)}
            />
          )}
        </div>
      </div>
    </div>
  );
}

// ─── iPad slides (LANDSCAPE) ──────────────────────────────────────────────────
// Same narrative arc as the iPhone slides, recomposed for the landscape iPad
// canvas (2752×2064): a vertically-centered text column on one side, the
// landscape device on the other. Typography sizes off `h` (≈ the old portrait
// width) so headline/pill weights match the iPhone set instead of doubling
// with the now-wider `w`. Sides alternate slide-to-slide for rhythm.

type PadPill = { color: string; text: string };

// Shared landscape feature layout: text column + device, no wrapping pills.
function IPadFeature({
  w, h, bg, glows, side = "left",
  sub, subColor = C.orange, head, copy, pills, extra,
  src, alt, placeholder,
}: {
  w: number; h: number; bg?: string; glows?: React.ReactNode; side?: "left" | "right";
  sub: string; subColor?: string; head: string; copy: string; pills: PadPill[];
  extra?: React.ReactNode;
  src: string; alt: string; placeholder: string;
}) {
  const textLeft = side === "left";
  // Pills size off a reduced base so three fit on ONE line inside the column.
  const pillBase = h * 0.6;
  return (
    <div style={{ position: "relative", width: w, height: h, overflow: "hidden", background: bg ?? C.bg }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />
      {glows}

      {/* Text column — vertically centered */}
      <div style={{
        position: "absolute", top: 0, bottom: 0,
        left: textLeft ? w * 0.055 : "auto",
        right: textLeft ? "auto" : w * 0.055,
        width: w * 0.42,
        display: "flex", flexDirection: "column", justifyContent: "center",
        zIndex: 10,
      }}>
        <div style={label(sub, h, subColor)}>{sub}</div>
        <div style={{ marginTop: h * 0.022, ...headline(h * 0.072) }}>{head}</div>
        <div style={{ marginTop: h * 0.024, ...body(h * 0.026) }}>{copy}</div>
        {extra}
        <div style={{ marginTop: h * 0.03, display: "flex", gap: h * 0.014, flexWrap: "nowrap" }}>
          {pills.map((p) => (
            <Pill key={p.text} color={p.color} w={pillBase}>{p.text}</Pill>
          ))}
        </div>
      </div>

      {/* Device — vertically centered on the opposite side, bleeding off-edge */}
      <IPad
        landscape
        src={src}
        alt={alt}
        placeholder={placeholder}
        style={{
          position: "absolute",
          top: "50%",
          left: textLeft ? "auto" : -w * 0.02,
          right: textLeft ? -w * 0.02 : "auto",
          transform: "translateY(-50%)",
          width: w * 0.50,
          zIndex: 2,
        }}
      />
    </div>
  );
}

// iPad Slide 1 — Hero (landscape: brand/tagline left, device right)
function IPadSlide1({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: "relative", width: w, height: h, background: C.bg, overflow: "hidden" }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <OrangeGlow style={{ width: w * 0.7, height: w * 0.7, top: h * 0.45, left: -w * 0.15 }} />
      <CyanGlow style={{ width: w * 0.5, height: w * 0.5, top: -w * 0.12, right: -w * 0.12 }} />
      <VioletGlow style={{ width: w * 0.35, height: w * 0.35, top: h * 0.2, left: w * 0.46 }} />

      {/* Brand + tagline — left column, vertically centered */}
      <div style={{
        position: "absolute", top: 0, bottom: 0, left: w * 0.06, width: w * 0.42,
        display: "flex", flexDirection: "column", justifyContent: "center", zIndex: 10,
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: h * 0.022 }}>
          <img src="/icon.png" alt="BOBA Playbook" style={{ width: h * 0.12, height: h * 0.12, borderRadius: h * 0.026 }} />
          <span style={label("BOBA PLAYBOOK", h)}>BOBA PLAYBOOK</span>
        </div>
        <div style={{ marginTop: h * 0.04, ...headline(h * 0.11) }}>
          Search. Scan. Collect. Play.
        </div>
        <div style={{ marginTop: h * 0.028, ...body(h * 0.03) }}>
          The ultimate BOBA companion app — now first-class on iPad.
        </div>
      </div>

      {/* Device — right side, vertically centered, bleeding off-edge */}
      <IPad
        landscape
        src="/screenshots-ipad/home.png"
        alt="iPad home screen"
        placeholder="Drop iPad home screenshot"
        style={{
          position: "absolute", top: "50%", right: -w * 0.04,
          transform: "translateY(-50%)", width: w * 0.52, zIndex: 2,
        }}
      />
    </div>
  );
}

// iPad Slide 2 — Search (text right, device left)
function IPadSlide2({ w, h }: { w: number; h: number }) {
  return (
    <IPadFeature
      w={w} h={h} side="right"
      glows={<>
        <CyanGlow style={{ width: w * 0.7, height: w * 0.7, top: -w * 0.18, right: -w * 0.12 }} />
        <OrangeGlow style={{ width: w * 0.5, height: w * 0.5, bottom: -w * 0.1, left: -w * 0.05 }} />
      </>}
      sub="THE FULL COLLECTION"
      head="Every card. At your fingertips."
      copy="17,968 cards. Instant search. Filter by Weapon, Treatment, Set."
      pills={[
        { color: C.cyan, text: "17,968 cards" },
        { color: C.orange, text: "Full images" },
        { color: C.violet, text: "Instant search" },
      ]}
      src="/screenshots-ipad/search.png"
      alt="iPad search screen"
      placeholder="Drop iPad search screenshot"
    />
  );
}

// iPad Slide 3 — Scan (text left, device right)
function IPadSlide3({ w, h }: { w: number; h: number }) {
  return (
    <IPadFeature
      w={w} h={h} side="left"
      bg={`linear-gradient(160deg, #080810 0%, #0D0820 50%, #080810 100%)`}
      glows={<>
        <VioletGlow style={{ width: w * 0.75, height: w * 0.75, top: h * 0.25, left: -w * 0.15 }} />
        <CyanGlow style={{ width: w * 0.5, height: w * 0.5, top: -w * 0.08, right: -w * 0.12 }} />
      </>}
      sub="CAMERA · ON-DEVICE" subColor={C.violet}
      head="Point. Shoot. Add."
      copy="Identifies any card in real time. No uploads. Entirely on-device."
      pills={[
        { color: C.violet, text: "Vision OCR" },
        { color: C.cyan, text: "Private" },
      ]}
      src="/screenshots-ipad/scan.png"
      alt="iPad scan screen"
      placeholder="Drop iPad scan screenshot"
    />
  );
}

// iPad Slide 4 — Collect (text left, device right)
function IPadSlide4({ w, h }: { w: number; h: number }) {
  return (
    <IPadFeature
      w={w} h={h} side="left"
      glows={<>
        <OrangeGlow style={{ width: w * 0.7, height: w * 0.7, bottom: -w * 0.12, right: -w * 0.12 }} />
        <CyanGlow style={{ width: w * 0.45, height: w * 0.45, top: -w * 0.05, left: -w * 0.05 }} />
      </>}
      sub="YOUR COLLECTION"
      head="Track what you own."
      copy="Personal · For Sale · For Trade · Wanted · Grails"
      pills={[
        { color: C.orange, text: "5 designations" },
        { color: C.cyan, text: "Cloud sync" },
        { color: C.violet, text: "Swipe to delete" },
      ]}
      src="/screenshots-ipad/collect.png"
      alt="iPad collection screen"
      placeholder="Drop iPad collection screenshot"
    />
  );
}

// iPad Slide 5 — Pricing (text right, device left)
function IPadSlide5({ w, h }: { w: number; h: number }) {
  return (
    <IPadFeature
      w={w} h={h} side="right"
      bg={`linear-gradient(170deg, #080810 0%, #100808 60%, #080810 100%)`}
      glows={<>
        <OrangeGlow style={{ width: w * 0.6, height: w * 0.6, top: h * 0.45, right: w * 0.02 }} />
        <VioletGlow style={{ width: w * 0.4, height: w * 0.4, top: -w * 0.05, left: -w * 0.05 }} />
      </>}
      sub="RECENT SOLD COMPS" subColor={C.orange}
      head="Real sales. Real prices."
      copy="Live market estimate plus recent sold listings, per card."
      extra={
        <div style={{
          marginTop: h * 0.03,
          background: C.surface,
          border: `1px solid ${C.glassBorder}`,
          borderRadius: h * 0.025,
          padding: `${h * 0.022}px ${h * 0.04}px`,
          display: "flex",
          gap: h * 0.045,
          alignSelf: "flex-start",
        }}>
          {[
            { l: "LOW", v: "$4.99", c: C.cyan },
            { l: "AVG", v: "$12.50", c: C.orange },
            { l: "HIGH", v: "$28.00", c: C.violet },
          ].map(({ l, v, c }) => (
            <div key={l} style={{ textAlign: "center" }}>
              <div style={{ fontFamily: "var(--font-chakra)", fontSize: h * 0.018, fontWeight: 700, color: C.textMuted, letterSpacing: "0.15em" }}>{l}</div>
              <div style={{ fontFamily: "var(--font-bebas)", fontSize: h * 0.055, color: c, letterSpacing: "0.02em", lineHeight: 1.1 }}>{v}</div>
            </div>
          ))}
        </div>
      }
      pills={[
        { color: C.orange, text: "Recent sales" },
        { color: C.cyan, text: "Live market data" },
      ]}
      src="/screenshots-ipad/pricing.png"
      alt="iPad pricing screen"
      placeholder="Drop iPad pricing screenshot"
    />
  );
}

// iPad Slide 6 — Play (text left, device right)
function IPadSlide6({ w, h }: { w: number; h: number }) {
  return (
    <IPadFeature
      w={w} h={h} side="left"
      bg={`linear-gradient(150deg, #080810 0%, #080818 50%, #0A0810 100%)`}
      glows={<>
        <VioletGlow style={{ width: w * 0.75, height: w * 0.75, top: h * 0.1, left: -w * 0.18 }} />
        <OrangeGlow style={{ width: w * 0.45, height: w * 0.45, bottom: -w * 0.05, right: -w * 0.05 }} />
      </>}
      sub="RULES · STRATEGY · DECKS" subColor={C.violet}
      head="Know the rules. Win the game."
      copy="Rookie to playmaker. Rules, strategy, decks."
      pills={[
        { color: C.violet, text: "Deck builder" },
        { color: C.orange, text: "Format legality" },
        { color: C.cyan, text: "Strategy guides" },
      ]}
      src="/screenshots-ipad/play.png"
      alt="iPad play screen"
      placeholder="Drop iPad play screenshot"
    />
  );
}

// iPad Slide 7 — Decks (text right, device left)
function IPadSlideDecks({ w, h }: { w: number; h: number }) {
  return (
    <IPadFeature
      w={w} h={h} side="right"
      bg={`linear-gradient(155deg, #080810 0%, #0A0A20 50%, #080810 100%)`}
      glows={<>
        <CyanGlow style={{ width: w * 0.7, height: w * 0.7, top: h * 0.05, right: -w * 0.15 }} />
        <OrangeGlow style={{ width: w * 0.45, height: w * 0.45, bottom: -w * 0.05, left: -w * 0.05 }} />
      </>}
      sub="DECK BUILDER" subColor={C.cyan}
      head="Build legal. Battle ready."
      copy="Saved decks · Pool · Editor — three columns, drag-and-drop."
      pills={[
        { color: C.cyan, text: "Format legality" },
        { color: C.orange, text: "Drag-drop" },
        { color: C.violet, text: "Battle Day Score" },
      ]}
      src="/screenshots-ipad/decks.png"
      alt="iPad decks 3-column"
      placeholder="Drop iPad decks 3-column screenshot"
    />
  );
}

// iPad Slide 8 — More features
function IPadSlide7({ w, h }: { w: number; h: number }) {
  const features = [
    { icon: "🔍", text: "Search 17K+ cards" },
    { icon: "📸", text: "On-device scan" },
    { icon: "📦", text: "Collection tracker" },
    { icon: "💰", text: "Live market prices" },
    { icon: "🃏", text: "Deck builder" },
    { icon: "📱", text: "iPad first-class" },
    { icon: "🔗", text: "Public collections" },
    { icon: "🛒", text: "Breaks & stores" },
  ];

  return (
    <div style={{ position: "relative", width: w, height: h, overflow: "hidden",
      background: `linear-gradient(180deg, #080810 0%, #0D0D1A 100%)` }}>
      <GridLines w={w} h={h} />
      <ScanlineOverlay w={w} h={h} />

      <OrangeGlow style={{ width: w * 0.5, height: w * 0.5, top: h * 0.1, left: -w * 0.1 }} />
      <CyanGlow style={{ width: w * 0.45, height: w * 0.45, top: -w * 0.1, right: -w * 0.1 }} />
      <VioletGlow style={{ width: w * 0.3, height: w * 0.3, bottom: -w * 0.05, left: w * 0.42 }} />

      {/* Header — icon + wordmark + headline, centered at top */}
      <div style={{
        position: "absolute",
        top: h * 0.08,
        left: 0,
        right: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: h * 0.016,
        zIndex: 10,
        textAlign: "center",
        padding: `0 ${w * 0.08}px`,
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: h * 0.02 }}>
          <img
            src="/icon.png"
            alt="BOBA Playbook"
            style={{ width: h * 0.1, height: h * 0.1, borderRadius: h * 0.022 }}
          />
          <div style={headline(h * 0.06)}>BOBA PLAYBOOK</div>
        </div>
        <div style={{ marginTop: h * 0.012, ...headline(h * 0.085) }}>
          And so much more.
        </div>
        <div style={body(h * 0.028)}>
          Everything you need for BOBA. Made by fans.
        </div>
      </div>

      {/* Feature grid — 4-col × 2-row on the wide landscape canvas */}
      <div style={{
        position: "absolute",
        bottom: h * 0.1,
        left: w * 0.06,
        right: w * 0.06,
        display: "grid",
        gridTemplateColumns: "repeat(4, 1fr)",
        gap: h * 0.022,
        zIndex: 10,
      }}>
        {features.map(({ icon, text }) => (
          <div
            key={text}
            style={{
              display: "flex",
              alignItems: "center",
              gap: h * 0.018,
              background: C.surface,
              border: `1px solid ${C.glassBorder}`,
              borderRadius: h * 0.02,
              padding: `${h * 0.022}px ${h * 0.024}px`,
            }}
          >
            <span style={{ fontSize: h * 0.035 }}>{icon}</span>
            <span style={{ fontFamily: "var(--font-chakra)", fontSize: h * 0.022, fontWeight: 500, color: C.textPrimary }}>{text}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Slide registries ─────────────────────────────────────────────────────────
const IPHONE_SLIDES = [
  { id: "slide1", title: "Hero", Component: Slide1 },
  { id: "slide2", title: "Search", Component: Slide2 },
  { id: "slide3", title: "Scan", Component: Slide3 },
  { id: "slide4", title: "Collect", Component: Slide4 },
  { id: "slide5", title: "Pricing", Component: Slide5 },
  { id: "slide6", title: "Play", Component: Slide6 },
  { id: "slide7", title: "Decks", Component: SlideDecks },
  { id: "slide8", title: "More", Component: Slide7 },
];

const IPAD_SLIDES = [
  { id: "ipad-slide1", title: "Hero", Component: IPadSlide1 },
  { id: "ipad-slide2", title: "Search", Component: IPadSlide2 },
  { id: "ipad-slide3", title: "Scan", Component: IPadSlide3 },
  { id: "ipad-slide4", title: "Collect", Component: IPadSlide4 },
  { id: "ipad-slide5", title: "Pricing", Component: IPadSlide5 },
  { id: "ipad-slide6", title: "Play", Component: IPadSlide6 },
  { id: "ipad-slide7", title: "Decks", Component: IPadSlideDecks },
  { id: "ipad-slide8", title: "More", Component: IPadSlide7 },
];

// ─── Preview wrapper with ResizeObserver scaling ──────────────────────────────
function ScreenshotPreview({
  id,
  title,
  children,
  exportSize,
  canvasW,
  canvasH,
}: {
  id: string;
  title: string;
  children: React.ReactNode;
  exportSize: ExportSize;
  canvasW: number;
  canvasH: number;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const innerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.15);
  const [exporting, setExporting] = useState(false);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => {
      const { width } = el.getBoundingClientRect();
      setScale(width / canvasW);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [canvasW]);

  const handleExport = useCallback(async () => {
    const el = innerRef.current;
    if (!el || exporting) return;
    setExporting(true);

    // Track which <img> srcs we replaced so we can restore them in finally{}
    const originalSrcs = new Map<HTMLImageElement, string>();

    try {
      // 1. Wait for fonts
      await document.fonts.ready;

      // 2. Pre-convert every <img> in the slide to a base64 data URL and
      // swap it into img.src. We do this because html-to-image's internal
      // image fetcher silently fails to embed Next.js dev-server assets
      // in some environments — the export renders with empty img slots
      // (mockup frame missing, screenshot missing). Inlining the bytes
      // before capture sidesteps the fetcher entirely.
      //
      // We RE-ENCODE through a canvas rather than inlining the raw bytes.
      // The iPad screenshots are 2732×2048 PNGs at 14–16 MB each; a raw
      // base64 inline (~19 MB string) overflows html-to-image's SVG
      // <foreignObject> embed and silently fails to decode — the slide
      // renders with a blank device screen. Re-encoding opaque shots as
      // JPEG drops them to well under 1 MB; assets with transparency
      // (mockup frame, app icon) keep PNG so their alpha survives.
      const MAX_EDGE = 2048; // plenty for the device-screen area at 2752 export; keeps data URLs small for Safari
      const imgs = Array.from(el.querySelectorAll("img"));
      for (const img of imgs) {
        if (img.src.startsWith("data:")) continue;
        try {
          const resp = await fetch(img.src);
          if (!resp.ok) continue;
          const blob = await resp.blob();
          const bmp = await createImageBitmap(blob);
          const scaleDown = Math.min(1, MAX_EDGE / Math.max(bmp.width, bmp.height));
          const cw = Math.round(bmp.width * scaleDown);
          const ch = Math.round(bmp.height * scaleDown);
          const canvas = document.createElement("canvas");
          canvas.width = cw;
          canvas.height = ch;
          const ctx = canvas.getContext("2d")!;
          ctx.drawImage(bmp, 0, 0, cw, ch);
          bmp.close();

          // Probe corners + center for transparency. Opaque → JPEG (tiny);
          // any transparency → PNG (preserve alpha).
          let hasAlpha = false;
          for (const [px, py] of [[0, 0], [cw - 1, 0], [0, ch - 1], [cw - 1, ch - 1], [cw >> 1, ch >> 1]]) {
            if (ctx.getImageData(px, py, 1, 1).data[3] < 255) { hasAlpha = true; break; }
          }
          const dataUrl = hasAlpha
            ? canvas.toDataURL("image/png")
            : canvas.toDataURL("image/jpeg", 0.95);

          originalSrcs.set(img, img.src);
          img.src = dataUrl;
          // Wait for the swapped-in src to be ready to paint
          if (img.decode) {
            try { await img.decode(); } catch { /* ignore */ }
          }
        } catch (err) {
          console.warn("[export] failed to inline image", img.src, err);
        }
      }

      const htmlToImage = await import("html-to-image");

      const opts = {
        width: canvasW,
        height: canvasH,
        pixelRatio: exportSize.w / canvasW,
        // Remove the CSS scale transform in the clone so it renders at native size
        style: { transform: "none", transformOrigin: "top left" },
      };

      // Warm-up passes. html-to-image renders the slide into an SVG
      // <foreignObject> and loads it as an image; WebKit/Safari decodes the
      // embedded data-URL <img> tags ASYNCHRONOUSLY, so the FIRST toPng pass
      // captures before the screenshot has painted — producing a blank device
      // screen. Chrome decodes synchronously and is fine on pass 1, but Safari
      // needs the earlier passes to prime the decode. We run a few passes and
      // keep only the last. (Do NOT collapse to a single capture — that's what
      // silently broke the Safari export.)
      let dataUrl = "";
      for (let pass = 0; pass < 3; pass++) {
        dataUrl = await htmlToImage.toPng(el, opts);
      }

      const safeLabel = exportSize.label.replace(/"/g, "in").replace(/\s+/g, "-");
      const link = document.createElement("a");
      link.download = `boba-${id}-${safeLabel}-${exportSize.w}x${exportSize.h}.png`;
      link.href = dataUrl;
      link.click();
    } finally {
      // Restore original src on every img we touched
      for (const [img, src] of originalSrcs) {
        img.src = src;
      }
      setExporting(false);
    }
  }, [id, exportSize, exporting, canvasW, canvasH]);

  const previewH = canvasW * scale * (canvasH / canvasW);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      <div
        ref={containerRef}
        onClick={handleExport}
        title={`Export ${title}`}
        style={{
          cursor: exporting ? "wait" : "pointer",
          position: "relative",
          width: "100%",
          height: previewH,
          overflow: "hidden",
          borderRadius: 8,
          outline: exporting ? `2px solid ${C.orange}` : "none",
        }}
      >
        <div
          ref={innerRef}
          style={{
            transformOrigin: "top left",
            transform: `scale(${scale})`,
            width: canvasW,
            height: canvasH,
          }}
        >
          {children}
        </div>
      </div>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          padding: "0 2px",
        }}
      >
        <span style={{ fontFamily: "var(--font-chakra)", fontSize: 11, color: C.textMuted }}>
          {title}
        </span>
        <span
          onClick={handleExport}
          style={{
            fontFamily: "var(--font-chakra)",
            fontSize: 10,
            color: exporting ? C.orange : C.cyan,
            cursor: "pointer",
            letterSpacing: "0.1em",
            textTransform: "uppercase",
          }}
        >
          {exporting ? "Exporting…" : "↓ Export"}
        </span>
      </div>
    </div>
  );
}

// ─── Main page ────────────────────────────────────────────────────────────────
type Device = "iphone" | "ipad";

export default function ScreenshotsClient() {
  const [device, setDevice] = useState<Device>(() => {
    if (typeof window !== "undefined") {
      const d = new URLSearchParams(window.location.search).get("device");
      if (d === "ipad" || d === "iphone") return d;
    }
    return "iphone";
  });
  const [sizeIdx, setSizeIdx] = useState(0);

  const sizes: readonly ExportSize[] = device === "iphone" ? IPHONE_SIZES : IPAD_SIZES;
  const exportSize = sizes[Math.min(sizeIdx, sizes.length - 1)];
  const slides = device === "iphone" ? IPHONE_SLIDES : IPAD_SLIDES;
  const canvasW = device === "iphone" ? IPHONE_W : IPAD_W;
  const canvasH = device === "iphone" ? IPHONE_H : IPAD_H;

  // Reset size index when device changes (sizes arrays are different lengths)
  const switchDevice = (d: Device) => {
    setDevice(d);
    setSizeIdx(0);
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#050508",
        padding: "24px 0 48px",
        fontFamily: "var(--font-chakra)",
      }}
    >
      {/* Toolbar */}
      <div
        style={{
          position: "sticky",
          top: 0,
          zIndex: 100,
          background: "rgba(5,5,8,0.95)",
          backdropFilter: "blur(12px)",
          borderBottom: "1px solid rgba(255,255,255,0.06)",
          padding: "12px 32px",
          display: "flex",
          alignItems: "center",
          gap: 24,
          flexWrap: "wrap",
        }}
      >
        <span
          style={{
            fontFamily: "var(--font-bebas)",
            fontSize: 22,
            color: C.orange,
            letterSpacing: "0.05em",
          }}
        >
          BOBA Playbook — Screenshots
        </span>

        {/* Device toggle */}
        <div style={{ display: "flex", gap: 6, marginLeft: "auto", alignItems: "center" }}>
          <span style={{ fontSize: 11, color: C.textMuted, letterSpacing: "0.1em", textTransform: "uppercase" }}>
            Device:
          </span>
          {(["iphone", "ipad"] as const).map((d) => (
            <button
              key={d}
              onClick={() => switchDevice(d)}
              style={{
                fontFamily: "var(--font-chakra)",
                fontSize: 11,
                fontWeight: device === d ? 700 : 400,
                color: device === d ? C.orange : C.textMuted,
                background: device === d ? `${C.orange}15` : "transparent",
                border: `1px solid ${device === d ? C.orange : "rgba(255,255,255,0.1)"}`,
                borderRadius: 4,
                padding: "4px 12px",
                cursor: "pointer",
                letterSpacing: "0.08em",
                textTransform: "uppercase",
              }}
            >
              {d}
            </button>
          ))}
        </div>

        {/* Size dropdown */}
        <div style={{ display: "flex", gap: 8 }}>
          <span style={{ fontSize: 11, color: C.textMuted, alignSelf: "center", letterSpacing: "0.1em", textTransform: "uppercase" }}>
            Size:
          </span>
          {sizes.map((s, i) => (
            <button
              key={s.label}
              onClick={() => setSizeIdx(i)}
              style={{
                fontFamily: "var(--font-chakra)",
                fontSize: 11,
                fontWeight: sizeIdx === i ? 700 : 400,
                color: sizeIdx === i ? C.cyan : C.textMuted,
                background: sizeIdx === i ? `${C.cyan}15` : "transparent",
                border: `1px solid ${sizeIdx === i ? C.cyan : "rgba(255,255,255,0.1)"}`,
                borderRadius: 4,
                padding: "4px 10px",
                cursor: "pointer",
                letterSpacing: "0.05em",
              }}
            >
              {s.label} — {s.w}×{s.h}
            </button>
          ))}
        </div>
      </div>

      {/* Instructions */}
      <div
        style={{
          margin: "24px 32px 0",
          padding: "12px 20px",
          background: `${C.cyan}10`,
          border: `1px solid ${C.cyan}30`,
          borderRadius: 6,
          fontFamily: "var(--font-chakra)",
          fontSize: 12,
          color: C.textMuted,
          lineHeight: 1.5,
        }}
      >
        <strong style={{ color: C.cyan }}>Adding screenshots:</strong>{" "}
        Drop iPhone captures (portrait, ideally 1320×2868 from 6.9&quot; sim or device) into{" "}
        <code style={{ color: C.textPrimary, background: "rgba(255,255,255,0.05)", padding: "1px 6px", borderRadius: 3 }}>
          tools/screenshots/public/screenshots/
        </code>{" "}
        as{" "}
        <code style={{ color: C.textPrimary, background: "rgba(255,255,255,0.05)", padding: "1px 6px", borderRadius: 3 }}>
          home / search / scan / collect / collect-2 / pricing / play / decks.png
        </code>.
        Drop iPad captures (LANDSCAPE, ideally 2732×2048 from 12.9&quot; iPad Pro) into{" "}
        <code style={{ color: C.textPrimary, background: "rgba(255,255,255,0.05)", padding: "1px 6px", borderRadius: 3 }}>
          tools/screenshots/public/screenshots-ipad/
        </code>{" "}
        as{" "}
        <code style={{ color: C.textPrimary, background: "rgba(255,255,255,0.05)", padding: "1px 6px", borderRadius: 3 }}>
          home / search / scan / collect / pricing / play / decks.png
        </code>.
        Click any slide to export it at the selected resolution.
      </div>

      {/* Screenshot grid */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: device === "iphone"
            ? "repeat(auto-fill, minmax(200px, 1fr))"
            : "repeat(auto-fill, minmax(280px, 1fr))",
          gap: 24,
          padding: "24px 32px",
          maxWidth: 1600,
          margin: "0 auto",
        }}
      >
        {slides.map(({ id, title, Component }) => (
          <ScreenshotPreview
            key={id}
            id={id}
            title={title}
            exportSize={exportSize}
            canvasW={canvasW}
            canvasH={canvasH}
          >
            <Component w={canvasW} h={canvasH} />
          </ScreenshotPreview>
        ))}
      </div>
    </div>
  );
}
