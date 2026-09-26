import type { Metadata } from "next";
import Link from "next/link";
import { Footer, Header } from "../site-shell";
export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Zettax handles account, trading and support data.",
};
export default function Privacy() {
  return (
    <>
      <Header />
      <main className="legal-page">
        <nav>
          <Link href="/">Zettax</Link> &nbsp; / &nbsp;{" "}
          <Link href="/account-deletion.html">Account deletion</Link>
        </nav>
        <h1>Privacy Policy</h1>
        <p className="legal-muted">Effective 25 September 2026</p>
        <p>
          Zettax is published by Kodzie (TECHVILO LTD). This policy covers the
          Zettax Android app and zettax.app website.
        </p>
        <h2>Information we handle</h2>
        <p>
          If you create an account, we handle your email address, authentication
          details, optional phone number, profile information you provide,
          sign-in sessions and device information needed to protect the account.
          If you choose Google sign-in, we receive the account identity
          information needed to authenticate you. We do not receive your Google
          password.
        </p>
        <p>
          We keep your watchlist, virtual balances, trading activity, account
          history, notifications, and deposit or withdrawal request details. A
          request can include a mobile-wallet number, payment reference and an
          optional screenshot. A profile photo is optional. Public market-price
          information comes from external data providers and is displayed as
          reference data; a virtual trade does not purchase the underlying
          asset.
        </p>
        <h2>Why we use it</h2>
        <p>
          We use this information to run your account, process requests, show
          balances and history, provide trading and market displays, prevent
          fraud and unauthorized access, resolve disputes, and respond to
          support or privacy requests. The website and app store technical data
          needed for ordinary delivery and security.
        </p>
        <h2>Service providers and disclosure</h2>
        <p>
          Our hosting, database and object-storage providers process data on our
          behalf. Optional screenshots and profile images are stored in
          access-controlled object storage. Google processes Google sign-in and
          Google Play distribution under its own terms. We do not sell your
          personal information. We may disclose information where required by
          law or to investigate abuse, and only share request details with a
          payment service where needed to handle that request.
        </p>
        <h2>Retention and security</h2>
        <p>
          Optional deposit screenshots are scheduled for deletion seven days
          after upload. Other account, transaction, security and audit records
          are retained while needed to operate the service and for applicable
          legal, fraud-prevention or dispute obligations. We use HTTPS in
          transit and restricted access to stored data. No online service can
          promise absolute security.
        </p>
        <h2>Your choices and deletion</h2>
        <p>
          You can update profile information in Zettax. To request account and
          associated-data deletion, use the{" "}
          <Link href="/account-deletion.html">
            Zettax account-deletion page
          </Link>
          , which works without reinstalling the app. We verify account
          ownership and review any outstanding requests before closing an
          account. We delete or anonymize data that is no longer required, while
          retaining records where legally necessary; we will explain any
          retention that applies to your request.
        </p>
        <h2>Children</h2>
        <p>
          Zettax is not designed for children. People under 18 should not create
          an account.
        </p>
        <h2>Contact</h2>
        <p>
          Privacy questions:{" "}
          <a href="mailto:raktobondhu@gmail.com?subject=Zettax%20privacy%20request">
            raktobondhu@gmail.com
          </a>
          .
        </p>
      </main>
      <Footer />
    </>
  );
}
