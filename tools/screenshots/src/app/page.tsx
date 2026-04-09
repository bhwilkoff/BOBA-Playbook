"use client";
import dynamic from "next/dynamic";

// Disable SSR for the screenshot generator — it's a pure client-side dev tool
// and html-to-image / ResizeObserver require browser APIs
const ScreenshotsClient = dynamic(() => import("./ScreenshotsClient"), {
  ssr: false,
  loading: () => (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: "monospace",
        color: "#6B7080",
        background: "#050508",
      }}
    >
      Loading…
    </div>
  ),
});

export default function Page() {
  return <ScreenshotsClient />;
}
