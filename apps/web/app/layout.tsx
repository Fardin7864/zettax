import type { Metadata } from "next";
import "./styles.css";
import { ScrollEffects } from "./scroll-effects";

export const metadata: Metadata = {
  metadataBase: new URL("https://zettax.app"),
  title: {
    default: "Zettax | Trade. Learn. Explore Markets.",
    template: "%s | Zettax",
  },
  description:
    "Explore global markets, learn with clear tools, and practice trading with virtual funds on Zettax.",
  openGraph: {
    title: "Zettax | Trade. Learn. Explore Markets.",
    description:
      "Markets, education, and a virtual demo trading experience in one place.",
    images: ["/landing-hero.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <ScrollEffects />
        {children}
      </body>
    </html>
  );
}
