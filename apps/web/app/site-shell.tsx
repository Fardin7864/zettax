"use client";

import Link from "next/link";
import Image from "next/image";
import { useState } from "react";

const downloadUrl =
  "https://play.google.com/apps/internaltest/4701631069547597293";

export function Brand() {
  return (
    <Link href="/" className="brand" aria-label="Zettax home">
      <Image
        src="/images/zettax-mark.png"
        alt=""
        width={38}
        height={38}
        priority
      />
      <span className="brand-wordmark" aria-hidden="true">
        <Image
          src="/images/zettax-wordmark.png"
          alt=""
          width={113}
          height={113}
          priority
        />
      </span>
    </Link>
  );
}

export function Header() {
  const [open, setOpen] = useState(false);
  return (
    <header className="header">
      <div className="container header-inner">
        <Brand />
        <nav className={open ? "nav open" : "nav"} aria-label="Main navigation">
          <Link href="/markets" onClick={() => setOpen(false)}>
            Markets
          </Link>
          <Link href="/#features" onClick={() => setOpen(false)}>
            Features
          </Link>
          <Link href="/#learn" onClick={() => setOpen(false)}>
            Learn
          </Link>
          <Link href="/#tools" onClick={() => setOpen(false)}>
            Tools
          </Link>
          <Link href="/#pricing" onClick={() => setOpen(false)}>
            Pricing
          </Link>
          <Link href="/#company" onClick={() => setOpen(false)}>
            Company
          </Link>
          <Link href="/#faq" onClick={() => setOpen(false)}>
            FAQ
          </Link>
        </nav>
        <div className="header-actions">
          <Link className="header-login" href="/demo">
            Try Demo
          </Link>
          <a className="button button-gold header-download" href={downloadUrl}>
            Download App
          </a>
        </div>
        <button
          className="menu-toggle"
          type="button"
          aria-label={open ? "Close menu" : "Open menu"}
          aria-expanded={open}
          onClick={() => setOpen(!open)}
        >
          <span></span>
          <span></span>
          <span></span>
        </button>
      </div>
    </header>
  );
}

export function Footer() {
  return (
    <footer className="footer" id="company">
      <div className="container footer-grid">
        <div>
          <Brand />
          <p>
            Explore markets with clarity. Learn, practice, and grow at your own
            pace.
          </p>
          <small>
            Virtual demo trading. Market displays are for information, not
            execution.
          </small>
        </div>
        <div>
          <strong>Explore</strong>
          <Link href="/markets">Markets</Link>
          <Link href="/#features">Features</Link>
          <Link href="/#learn">Learn</Link>
        </div>
        <div>
          <strong>Platform</strong>
          <Link href="/demo">Demo trading</Link>
          <a href={downloadUrl}>Download Android app</a>
          <Link href="/#faq">FAQ</Link>
        </div>
        <div>
          <strong>Legal</strong>
          <Link href="/privacy.html">Privacy policy</Link>
          <Link href="/account-deletion.html">Account deletion</Link>
          <a href="mailto:raktobondhu@gmail.com">Contact</a>
        </div>
      </div>
      <div className="container footer-bottom">
        © {new Date().getFullYear()} Zettax. All rights reserved.
      </div>
    </footer>
  );
}

export { downloadUrl };
