"use client";

import React, { useRef, useEffect, useState, useCallback } from "react";
// html-to-image imported dynamically in the export handler (avoids SSR localStorage error)

// ─── Canvas dimensions (design at largest iPhone size) ──────────────────────
const CW = 1320;
const CH = 2868;

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
const SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
  { label: '6.3"', w: 1206, h: 2622 },
  { label: '6.1"', w: 1125, h: 2436 },
] as const;

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
          17,739 cards. Instant search.<br />Filter by element, set, and rarity.
        </div>
        <div style={{ marginTop: w * 0.035, display: "flex", gap: w * 0.025, flexWrap: "wrap" }}>
          <Pill color={C.cyan} w={w}>17,739 cards</Pill>
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
        <div style={label("Pricing", w, C.orange)}>EBAY SOLD DATA</div>
        <div style={{ marginTop: w * 0.025, ...headline(w * 0.105) }}>
          Real sales.<br />Real prices.
        </div>
        <div style={{ marginTop: w * 0.028, ...body(w * 0.031) }}>
          Low, average, and high comps<br />
          across 7, 30, and 90-day windows.
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
          <Pill color={C.orange} w={w}>eBay sold listings</Pill>
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
          Rookie · Substitution · Playmaker
        </div>
        <div style={{ marginTop: w * 0.035, display: "flex", gap: w * 0.02, flexWrap: "wrap" }}>
          <Pill color={C.violet} w={w}>3 game modes</Pill>
          <Pill color={C.orange} w={w}>Deck builder</Pill>
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

// ─── Slide 7: More features ───────────────────────────────────────────────────
function Slide7({ w, h }: { w: number; h: number }) {
  const features = [
    { icon: "🔍", text: "Instant card search" },
    { icon: "📸", text: "On-device card scan" },
    { icon: "📦", text: "Collection tracker" },
    { icon: "💰", text: "eBay price comps" },
    { icon: "🃏", text: "Deck builder" },
    { icon: "📖", text: "Full rules reference" },
    { icon: "⭐", text: "Grails & wishlists" },
    { icon: "☁️", text: "Cloud sync" },
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

// ─── Slide registry ───────────────────────────────────────────────────────────
const SLIDES = [
  { id: "slide1", title: "Hero", Component: Slide1 },
  { id: "slide2", title: "Search", Component: Slide2 },
  { id: "slide3", title: "Scan", Component: Slide3 },
  { id: "slide4", title: "Collect", Component: Slide4 },
  { id: "slide5", title: "Pricing", Component: Slide5 },
  { id: "slide6", title: "Play", Component: Slide6 },
  { id: "slide7", title: "More", Component: Slide7 },
];

// ─── Preview wrapper with ResizeObserver scaling ──────────────────────────────
// Export strategy: capture the preview's inner div directly (it IS the full CW×CH
// slide — just visually scaled via CSS transform). We override transform:"none" in
// the html-to-image clone so it renders at native size. This avoids the blank-image
// bug caused by off-screen elements that never get fonts/images loaded by the browser.
function ScreenshotPreview({
  id,
  title,
  children,
  exportSize,
}: {
  id: string;
  title: string;
  children: React.ReactNode;
  exportSize: (typeof SIZES)[number];
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
      setScale(width / CW);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const handleExport = useCallback(async () => {
    const el = innerRef.current;
    if (!el || exporting) return;
    setExporting(true);
    try {
      await document.fonts.ready;
      const htmlToImage = await import("html-to-image");

      const opts = {
        width: CW,
        height: CH,
        pixelRatio: exportSize.w / CW,
        // Remove the CSS scale transform in the clone so it renders at native CW×CH
        style: { transform: "none", transformOrigin: "top left" },
        cacheBust: true,
      };

      // First call warms up font + image embedding; second call is the real capture
      await htmlToImage.toPng(el, opts);
      const dataUrl = await htmlToImage.toPng(el, opts);

      const link = document.createElement("a");
      link.download = `boba-${id}-${exportSize.label.replace(/"/g, "in")}.png`;
      link.href = dataUrl;
      link.click();
    } finally {
      setExporting(false);
    }
  }, [id, exportSize, exporting]);

  const previewH = CW * scale * (CH / CW);

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
            width: CW,
            height: CH,
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
export default function ScreenshotsClient() {
  const [sizeIdx, setSizeIdx] = useState(0);
  const exportSize = SIZES[sizeIdx];

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

        <div style={{ display: "flex", gap: 8, marginLeft: "auto" }}>
          <span style={{ fontSize: 11, color: C.textMuted, alignSelf: "center", letterSpacing: "0.1em", textTransform: "uppercase" }}>
            Size:
          </span>
          {SIZES.map((s, i) => (
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
        <strong style={{ color: C.cyan }}>Adding screenshots:</strong> Drop your iPhone 15 Pro captures into{" "}
        <code style={{ color: C.textPrimary, background: "rgba(255,255,255,0.05)", padding: "1px 6px", borderRadius: 3 }}>
          tools/screenshots/public/screenshots/
        </code>{" "}
        using these filenames:{" "}
        <code style={{ color: C.textPrimary, background: "rgba(255,255,255,0.05)", padding: "1px 6px", borderRadius: 3 }}>
          home.png, search.png, scan.png, collect.png, collect-2.png, pricing.png, play.png
        </code>.
        Click any slide to export it at the selected resolution.
      </div>

      {/* Screenshot grid */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))",
          gap: 24,
          padding: "24px 32px",
          maxWidth: 1600,
          margin: "0 auto",
        }}
      >
        {SLIDES.map(({ id, title, Component }) => (
          <ScreenshotPreview key={id} id={id} title={title} exportSize={exportSize}>
            <Component w={CW} h={CH} />
          </ScreenshotPreview>
        ))}
      </div>
    </div>
  );
}
