import Image from "next/image";
import Link from "next/link";
import { downloadUrl, Footer, Header } from "./site-shell";

const marketCards = [
  {
    icon: "₿",
    tone: "orange",
    title: "Crypto",
    copy: "Explore Bitcoin, Ethereum and digital markets.",
  },
  {
    icon: "$",
    tone: "teal",
    title: "Forex",
    copy: "Follow major and minor currency pairs.",
  },
  {
    icon: "◈",
    tone: "blue",
    title: "Stocks",
    copy: "Discover global company shares.",
  },
  {
    icon: "◆",
    tone: "gold",
    title: "Commodities",
    copy: "Watch gold, oil and more.",
  },
  {
    icon: "▥",
    tone: "purple",
    title: "Indices",
    copy: "See how leading markets move.",
  },
];
const reasons = [
  {
    icon: "♛",
    title: "Clear Experience",
    copy: "Simple tools and clear information.",
  },
  {
    icon: "▧",
    title: "Global Markets",
    copy: "Access five market categories.",
  },
  {
    icon: "▤",
    title: "Powerful Tools",
    copy: "Charts built to make trends easier to read.",
  },
  {
    icon: "◉",
    title: "Demo Trading",
    copy: "Practice with virtual funds before you decide.",
  },
  {
    icon: "⬡",
    title: "Secure Account",
    copy: "Controls designed to protect your data.",
  },
  {
    icon: "▣",
    title: "Learn & Grow",
    copy: "Build confidence with useful guides.",
  },
];
const features = [
  {
    icon: "⌁",
    title: "Real-Time Charts",
    copy: "Market charts and indicators",
  },
  { icon: "◎", title: "Demo Trading", copy: "Practice without real funds" },
  {
    icon: "◈",
    title: "Multiple Markets",
    copy: "Crypto, forex, stocks and more",
  },
  {
    icon: "♧",
    title: "Market Context",
    copy: "Keep an eye on important moves",
  },
  {
    icon: "☆",
    title: "Asset Discovery",
    copy: "Explore markets that interest you",
  },
  {
    icon: "▣",
    title: "Portfolio Tracking",
    copy: "See virtual performance clearly",
  },
  { icon: "▣", title: "English & Bangla", copy: "Use the app your way" },
  {
    icon: "↝",
    title: "Funding Requests",
    copy: "Manage supported request flows",
  },
  {
    icon: "⬡",
    title: "Account Security",
    copy: "Protect access to your account",
  },
  {
    icon: "△",
    title: "Secure Sessions",
    copy: "Manage access to your account",
  },
  { icon: "◫", title: "Market Insights", copy: "Analysis for better context" },
  {
    icon: "✦",
    title: "Educational Resources",
    copy: "Guides and market knowledge",
  },
];
const steps = [
  ["Create Account", "Sign up in the app to get started."],
  ["Try Demo Trading", "Explore virtual funds and practice."],
  ["Explore Markets", "Study prices, charts and trends."],
  ["Build Your Skills", "Learn the tools at your own pace."],
  ["Trade With Clarity", "Use the experience that fits you."],
];
const faqs = [
  [
    "Is Zettax free to use?",
    "You can explore the public site and practice in the web demo for free. The app also provides a virtual demo experience.",
  ],
  [
    "What markets can I explore?",
    "Zettax presents crypto, forex, stocks, commodities and indices. Data availability and freshness vary by market and provider.",
  ],
  [
    "Does demo trading use real money?",
    "No. Demo balances and orders are virtual. The web demo is stored only in this browser.",
  ],
  [
    "How do I download the app?",
    "Use the Download App button to open Zettax's Google Play testing page. Google Play may ask you to sign in with an eligible tester account.",
  ],
  [
    "How is my data handled?",
    "Read our privacy policy for the data we collect, why we use it and how to request deletion.",
  ],
];

function SectionTitle({
  label,
  title,
  copy,
  link,
  href,
}: {
  label: string;
  title: string;
  copy?: string;
  link?: string;
  href?: string;
}) {
  return (
    <div className="section-heading">
      <div>
        <span className="eyebrow">• {label} •</span>
        <h2>{title}</h2>
        {copy && <p>{copy}</p>}
      </div>
      {link && href && (
        <Link className="section-link" href={href}>
          {link} <span>→</span>
        </Link>
      )}
    </div>
  );
}

function IconCard({
  icon,
  title,
  copy,
  tone = "gold",
}: {
  icon: string;
  title: string;
  copy: string;
  tone?: string | undefined;
}) {
  return (
    <article className="icon-card">
      <div className={`card-icon ${tone}`}>{icon}</div>
      <h3>{title}</h3>
      <p>{copy}</p>
    </article>
  );
}

export default function Home() {
  return (
    <>
      <Header />
      <main>
        <section className="hero" id="top">
          <div className="hero-bg" />
          <div className="container hero-inner">
            <div className="hero-copy">
              <span className="hero-pill">
                Trade Smarter <span>•</span> A Brighter Financial Future
              </span>
              <h1>
                Trade. Learn.
                <br />
                <span>Explore Markets.</span>
              </h1>
              <p>
                Access global markets — crypto, forex, stocks, commodities and
                indices — all in one powerful experience.
              </p>
              <div className="hero-buttons">
                <a className="button button-gold" href={downloadUrl}>
                  ▷ &nbsp; Get Zettax on Google Play
                </a>
                <Link className="button button-outline" href="/demo">
                  Try Demo Trading <span>→</span>
                </Link>
              </div>
              <div className="store-note">
                <span className="store-icons">
                  ● <span>▷</span>
                </span>
                <span>
                  Available on Android
                  <br />
                  <small>Explore the app, anytime.</small>
                </span>
              </div>
            </div>
            <div className="hero-phone">
              <Image
                src="/images/phone_trade_cutout.png"
                alt="Zettax trading app preview"
                fill
                priority
                sizes="(max-width: 700px) 78vw, 32vw"
              />
            </div>
            <aside className="hero-widgets">
              <div className="market-widget">
                <div className="widget-top">
                  <strong>Market Snapshot</strong>
                  <Link href="/markets" aria-label="Explore markets">
                    →
                  </Link>
                </div>
                <div className="ticker-row">
                  <span className="coin orange">₿</span>
                  <b>BTC</b>
                  <span>67,432.18</span>
                  <em>+2.45%</em>
                </div>
                <div className="ticker-row">
                  <span className="coin blue">◆</span>
                  <b>ETH</b>
                  <span>3,221.14</span>
                  <em>+1.12%</em>
                </div>
                <div className="ticker-row">
                  <span className="coin gold">◆</span>
                  <b>Gold</b>
                  <span>2,348.50</span>
                  <em className="negative">-0.62%</em>
                </div>
                <div className="ticker-row">
                  <span className="coin purple">€</span>
                  <b>EUR/USD</b>
                  <span>1.0821</span>
                  <em>+0.18%</em>
                </div>
                <small className="sample-label">Illustrative prices</small>
              </div>
              <Link href="/demo" className="demo-widget">
                <span className="demo-ring">◎</span>
                <span>
                  Demo Account<strong>$10,000.00</strong>
                  <small>Virtual balance</small>
                </span>
                <span className="round-arrow">→</span>
              </Link>
              <span className="hero-signoff">
                Your journey
                <br />
                starts here.
              </span>
            </aside>
          </div>
        </section>

        <section className="section container" id="markets">
          <SectionTitle
            label="EXPLORE"
            title="Explore Global Markets"
            copy="A clear view across the markets that matter to you."
            link="View All Markets"
            href="/markets"
          />
          <div className="market-grid">
            {marketCards.map((item) => (
              <Link href="/markets" className="market-card" key={item.title}>
                <div className={`market-icon ${item.tone}`}>{item.icon}</div>
                <h3>{item.title}</h3>
                <p>{item.copy}</p>
                <span className="card-arrow">↗</span>
              </Link>
            ))}
          </div>
        </section>

        <section className="section container" id="why">
          <SectionTitle
            label="WHY CHOOSE ZETTAX"
            title="A Smarter Way to Trade"
            copy="Everything you need to explore, learn and grow — in one place."
          />
          <div className="reason-grid">
            {reasons.map((item, i) => (
              <IconCard
                key={item.title}
                {...item}
                tone={i === 3 ? "teal" : "gold"}
              />
            ))}
          </div>
        </section>

        <section className="section container" id="features">
          <SectionTitle
            label="KEY FEATURES"
            title="Everything You Need for Smarter Trading"
            link="Try the Demo"
            href="/demo"
          />
          <div className="feature-grid">
            {features.map((item, i) => (
              <IconCard
                key={item.title}
                {...item}
                tone={
                  [
                    "blue",
                    "teal",
                    "gold",
                    "red",
                    "red",
                    "teal",
                    "blue",
                    "red",
                    "teal",
                    "purple",
                    "gold",
                    "gold",
                  ][i]
                }
              />
            ))}
          </div>
        </section>

        <section className="chart-section" id="tools">
          <div className="container">
            <SectionTitle
              label="PROFESSIONAL CHARTING"
              title="Advanced Charts & Trading Tools"
              copy="Follow the market with clear visuals and useful indicators."
            />
            <div className="chart-layout">
              <ul className="check-list">
                <li>Interactive candlestick charts</li>
                <li>Technical indicators</li>
                <li>Multiple timeframes</li>
                <li>Drawing and chart tools</li>
                <li>Market context at a glance</li>
              </ul>
              <div className="chart-art">
                <Image
                  src="/images/chart_desktop.webp"
                  alt="Example of a trading chart and indicators"
                  fill
                  sizes="(max-width: 700px) 95vw, 70vw"
                />
              </div>
            </div>
          </div>
        </section>

        <section className="section container" id="how">
          <SectionTitle
            label="GET STARTED"
            title="How It Works"
            copy="Start exploring Zettax in a few simple steps."
          />
          <div className="steps">
            {steps.map(([title, copy], i) => (
              <div className="step" key={title}>
                <span className="step-number">{i + 1}</span>
                <div>
                  <h3>{title}</h3>
                  <p>{copy}</p>
                </div>
                {i < steps.length - 1 && <span className="step-arrow">→</span>}
              </div>
            ))}
          </div>
        </section>

        <section className="section container" id="learn">
          <SectionTitle
            label="LEARN BY DOING"
            title="How to Trade on Zettax"
            copy="A simple path from your first chart to your first virtual trade."
          />
          <div className="learn-layout">
            <div className="learn-copy">
              <h3>Explore before you trade.</h3>
              <p>
                Start with market basics, then use the demo to learn how charts,
                orders and a portfolio fit together.
              </p>
              <Link className="button button-outline" href="/demo">
                Open Web Demo →
              </Link>
            </div>
            <div className="video-art">
              <Image
                src="/images/video_guide.webp"
                alt="Zettax trading guide preview"
                fill
                sizes="(max-width: 700px) 100vw, 55vw"
              />
            </div>
            <div className="chapters">
              <strong>Learning path</strong>
              {[
                "Platform overview",
                "Reading a price chart",
                "Placing a virtual trade",
                "Managing risk",
                "Reviewing your portfolio",
              ].map((x, i) => (
                <div key={x}>
                  <span>{String(i + 1).padStart(2, "0")}</span>
                  {x}
                  <span>↗</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="experience" id="screens">
          <div className="container">
            <SectionTitle
              label="APP EXPERIENCE"
              title="A Powerful Trading Experience"
              copy="Follow your favorite markets from a focused mobile interface."
            />
            <p className="gallery-hint">Swipe to explore the app screens →</p>
            <div className="phones">
              <div>
                <Image
                  src="/images/phone_markets_cutout.png"
                  alt="Markets screen"
                  fill
                  sizes="(max-width: 700px) 70vw, 20vw"
                />
              </div>
              <div>
                <Image
                  src="/images/phone_trading_cutout.png"
                  alt="Trading screen"
                  fill
                  sizes="(max-width: 700px) 70vw, 20vw"
                />
              </div>
              <div>
                <Image
                  src="/images/phone_portfolio_cutout.png"
                  alt="Portfolio screen"
                  fill
                  sizes="(max-width: 700px) 70vw, 20vw"
                />
              </div>
              <div>
                <Image
                  src="/images/phone_learn_cutout.png"
                  alt="Learning screen"
                  fill
                  sizes="(max-width: 700px) 70vw, 20vw"
                />
              </div>
            </div>
          </div>
        </section>

        <section className="section container trust">
          <SectionTitle
            label="TRUST & SECURITY"
            title="Trade With Confidence"
            copy="Keep your focus on learning with secure account controls and clear virtual trading labels."
          />
          <div className="trust-grid">
            <div>
              <span>⬡</span>
              <strong>Account security</strong>
              <small>Access controls</small>
            </div>
            <div>
              <span>◉</span>
              <strong>Virtual demo</strong>
              <small>Practice safely</small>
            </div>
            <div>
              <span>▣</span>
              <strong>Clear records</strong>
              <small>Review your activity</small>
            </div>
            <div>
              <span>◆</span>
              <strong>Data privacy</strong>
              <small>Know how data is handled</small>
            </div>
          </div>
        </section>

        <section className="section container pricing" id="pricing">
          <SectionTitle
            label="GET STARTED"
            title="Explore at Your Own Pace"
            copy="Start with the parts of Zettax that help you learn."
          />
          <div className="pricing-grid">
            <div>
              <span>01</span>
              <h3>Explore markets</h3>
              <p>
                Browse the public market overview and learn what each category
                offers.
              </p>
              <Link href="/markets">Explore markets →</Link>
            </div>
            <div>
              <span>02</span>
              <h3>Practice for free</h3>
              <p>
                Use the browser demo with virtual funds. No account or payment
                is needed.
              </p>
              <Link href="/demo">Try the demo →</Link>
            </div>
            <div>
              <span>03</span>
              <h3>Get the app</h3>
              <p>
                Take the Zettax experience to Android for more tools and account
                features.
              </p>
              <a href={downloadUrl}>Download app →</a>
            </div>
          </div>
        </section>

        <section className="section container academy">
          <SectionTitle
            label="ZETTAX ACADEMY"
            title="Learn, Improve and Grow"
            copy="Build your knowledge and practice with useful concepts."
          />
          <div className="academy-grid">
            {[
              ["▣", "Trading Basics", "Understand the fundamentals"],
              ["▥", "Technical Analysis", "Read charts and indicators"],
              ["⬡", "Risk Management", "Think about position size"],
              ["◈", "Market Insights", "Follow market context"],
              ["△", "Beginner’s Guide", "Take your first steps"],
            ].map(([icon, title, copy]) => (
              <IconCard
                key={title}
                icon={icon ?? ""}
                title={title ?? ""}
                copy={copy ?? ""}
                tone="teal"
              />
            ))}
          </div>
        </section>

        <section className="community">
          <div className="container">
            <span className="eyebrow">• BUILD YOUR KNOWLEDGE •</span>
            <h2>Your Journey Starts Here</h2>
            <p>
              Explore the markets, practice with virtual funds, and build your
              confidence step by step.
            </p>
            <div className="community-actions">
              <Link className="button button-gold" href="/demo">
                Try Demo Trading
              </Link>
              <a className="button button-outline" href={downloadUrl}>
                Download App
              </a>
            </div>
          </div>
        </section>

        <section className="section container faq" id="faq">
          <SectionTitle label="QUESTIONS" title="Frequently Asked Questions" />
          <div className="faq-list">
            {faqs.map(([question, answer]) => (
              <details key={question}>
                <summary>
                  {question}
                  <span>⌄</span>
                </summary>
                <p>{answer}</p>
              </details>
            ))}
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
