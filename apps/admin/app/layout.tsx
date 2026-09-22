import type { Metadata } from "next";
import "./styles.css";

export const metadata: Metadata = {
  title: "Zettax Operations",
  description: "Secure operational console for Zettax",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
