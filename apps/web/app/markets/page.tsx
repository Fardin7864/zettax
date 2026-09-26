import type { Metadata } from "next";
import { Footer, Header } from "../site-shell";
import { MarketsDashboard } from "./markets-dashboard";

export const metadata: Metadata = {
  title: "Markets",
  description: "Explore live display prices and market charts on Zettax.",
};

export default function MarketsPage() {
  return (
    <>
      <Header />
      <MarketsDashboard />
      <Footer />
    </>
  );
}
