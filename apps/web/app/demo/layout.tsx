import type { Metadata } from "next";
export const metadata: Metadata = {
  title: "Demo Trading",
  description:
    "Practice trading with virtual funds in the Zettax browser demo.",
};
export default function DemoLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
