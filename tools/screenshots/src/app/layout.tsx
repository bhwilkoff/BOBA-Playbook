import type { Metadata } from "next";
import { Bebas_Neue, Chakra_Petch } from "next/font/google";

const bebasNeue = Bebas_Neue({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-bebas",
});

const chakraPetch = Chakra_Petch({
  weight: ["300", "400", "500", "600", "700"],
  subsets: ["latin"],
  variable: "--font-chakra",
});

export const metadata: Metadata = {
  title: "BOBA Playbook — App Store Screenshots",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={`${bebasNeue.variable} ${chakraPetch.variable}`} style={{ margin: 0, padding: 0, background: "#080810" }}>
        {children}
      </body>
    </html>
  );
}
