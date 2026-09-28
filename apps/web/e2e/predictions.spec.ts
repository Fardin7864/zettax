import { test, expect } from "@playwright/test";
const id = "12345678-1234-1234-1234-123456789012";
const q = {
  id,
  creator: "Zettax",
  creatorId: null,
  creatorAvatarUrl: null,
  symbol: "BTC/USD",
  instrumentId: "btc-usd",
  condition: "ABOVE",
  targetPrice: "82500.00",
  referencePrice: "82000",
  referenceSource: "BINANCE_1S_V1:BTCUSDT",
  referenceTimestamp: new Date().toISOString(),
  expiresAt: new Date(Date.now() + 3600000).toISOString(),
  status: "OPEN",
  outcome: null,
  settlementPrice: null,
  settlementSource: null,
  settlementTimestamp: null,
  cancellationReason: null,
  participantCount: 100,
  yesDemoPool: "123456.00",
  noDemoPool: "98565.00",
  demoYesPoolShare: 55.6,
  pricePrecision: 2,
  generationContext: {
    explanation: "Compare the future price with the price one hour ago.",
    anchorPrice: "82500",
    anchorTimestamp: new Date(Date.now() - 3600000).toISOString(),
  },
};
test.use({
  channel: "chrome",
  baseURL: process.env.PREDICTION_TEST_URL || "http://localhost:3002",
});
test.beforeEach(async ({ page }) => {
  await page.route("**/api/predictions/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    let data: unknown;
    if (path.endsWith("/config"))
      data = { googleClientId: "", socketOrigin: "" };
    else if (path.endsWith("/users/me"))
      return route.fulfill({
        status: 401,
        json: { message: "Sign in required" },
      });
    else if (path.endsWith(`/questions/${id}`)) data = q;
    else data = { items: [q], nextCursor: null };
    await route.fulfill({ json: { data } });
  });
  await page.route("**/api/market/**", (route) =>
    route.fulfill({ json: { data: [] } }),
  );
});
for (const width of [320, 360, 390, 430, 768, 1024, 1440]) {
  test(`prediction view fits ${width}px and keeps download visible`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/predictions");
    await expect(
      page.getByRole("heading", { name: "Will BTC/USD be above $82,500.00?" }),
    ).toBeVisible();
    await expect(page.locator("header .header-download")).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.getByRole("button", { name: /Zettax · Price-based/ }).click();
    await expect(
      page.getByRole("dialog", { name: "Prediction details" }),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog")).toHaveCount(0);
    await page.screenshot({
      path: `test-results/predictions-${width}.png`,
      fullPage: true,
    });
  });
}
test("guest participation opens sign-in without sending a stake", async ({
  page,
}) => {
  await page.goto("/predictions");
  await page.getByRole("button", { name: /Zettax · Price-based/ }).click();
  await page.getByRole("button", { name: "Predict YES", exact: true }).click();
  await expect(
    page.getByRole("dialog", { name: "Sign in", exact: true }),
  ).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(
    page.getByRole("dialog", { name: "Prediction details" }),
  ).toBeVisible();
});
test("low-priced targets retain market precision", async ({ page }) => {
  await page.route("**/api/predictions/prediction/questions?*", (route) =>
    route.fulfill({
      json: {
        data: {
          items: [
            {
              ...q,
              symbol: "ADA/USD",
              targetPrice: "0.2388",
              referencePrice: "0.2391",
              pricePrecision: 4,
            },
          ],
          nextCursor: null,
        },
      },
    }),
  );
  await page.goto("/predictions");
  await expect(
    page.getByRole("heading", { name: "Will ADA/USD be above $0.2388?" }),
  ).toBeVisible();
  await expect(
    page.getByText(/Reference \$0.2391 · Target \$0.2388/),
  ).toBeVisible();
});
