import type { Metadata } from "next";
import Link from "next/link";
import { Footer, Header } from "../site-shell";
export const metadata: Metadata = {
  title: "Account Deletion",
  description: "Request deletion of your Zettax account and associated data.",
};
export default function AccountDeletion() {
  return (
    <>
      <Header />
      <main className="legal-page">
        <nav>
          <Link href="/">Zettax</Link> &nbsp; / &nbsp;{" "}
          <Link href="/privacy.html">Privacy policy</Link>
        </nav>
        <h1>Request deletion of your Zettax account</h1>
        <p>
          This page is available even if you no longer have the Zettax app. You
          can request deletion of your account and associated personal data by
          emailing us from the address associated with your account. Include
          “Delete my Zettax account” and the account email in your message. Do
          not send a password, government ID or payment PIN.
        </p>
        <p>
          <a
            className="button button-gold"
            href="mailto:raktobondhu@gmail.com?subject=Delete%20my%20Zettax%20account"
          >
            Email a deletion request
          </a>
        </p>
        <p>
          If the button does not open an email app, send your request to{" "}
          <a href="mailto:raktobondhu@gmail.com">raktobondhu@gmail.com</a>.
        </p>
        <p>
          We verify ownership before acting. Open trades, pending funding
          requests or applicable legal obligations may require additional
          review. Once verified, we close the account and delete or anonymize
          personal information that is no longer required. Transaction, security
          or audit records may be retained where legally required or needed for
          fraud prevention and disputes; we will explain the outcome for your
          request.
        </p>
        <p className="legal-muted">
          You can also find this request path in the app under Profile →
          Security. See our <Link href="/privacy.html">Privacy Policy</Link> for
          data categories and retention details.
        </p>
      </main>
      <Footer />
    </>
  );
}
