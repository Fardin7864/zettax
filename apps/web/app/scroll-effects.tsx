"use client";

import { useEffect } from "react";

const selectors = [
  ".section-heading",
  ".market-card",
  ".icon-card",
  ".chart-layout",
  ".step",
  ".learn-layout",
  ".phones",
  ".trust-grid > div",
  ".pricing-grid > div",
  ".community .container",
  ".faq-list details",
].join(", ");

export function ScrollEffects() {
  useEffect(() => {
    if (
      !window.IntersectionObserver ||
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      return;
    }

    const elements = Array.from(
      document.querySelectorAll<HTMLElement>(selectors),
    );
    const observer = new IntersectionObserver(
      (entries, activeObserver) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add("in-view");
          activeObserver.unobserve(entry.target);
        }
      },
      { threshold: 0.08, rootMargin: "0px 0px -6% 0px" },
    );

    for (const element of elements) {
      element.classList.add("reveal-item");
      if (element.getBoundingClientRect().top < window.innerHeight * 0.92) {
        element.classList.add("in-view");
      } else {
        const siblings = Array.from(element.parentElement?.children ?? []);
        element.style.setProperty(
          "--reveal-delay",
          `${Math.min(siblings.indexOf(element) % 6, 5) * 45}ms`,
        );
        observer.observe(element);
      }
    }
    document.documentElement.classList.add("motion-active");

    return () => {
      observer.disconnect();
      document.documentElement.classList.remove("motion-active");
      for (const element of elements) {
        element.classList.remove("reveal-item", "in-view");
        element.style.removeProperty("--reveal-delay");
      }
    };
  }, []);

  return null;
}
