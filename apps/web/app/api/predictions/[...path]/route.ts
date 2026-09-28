import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";

const base = (
  process.env.MARKET_API_BASE_URL || "https://api.zettax.app/api/v1"
).replace(/\/$/, "");
const uuid = "[0-9a-f-]{36}";
const reads = new RegExp(
  `^(prediction/(availability|questions|mine|created|events|questions/${uuid}(/mine)?)|accounts|users/me)$`,
);
const writes = new RegExp(
  `^(prediction/(questions|questions/${uuid}/(positions|report))|auth/(login|register|google|logout))$`,
);
type Tokens = {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresIn: number;
  user?: unknown;
};
const refreshes = new Map<
  string,
  { expires: number; pending: Promise<Tokens | null> }
>();
const cookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/api/predictions",
};
function setTokens(response: NextResponse, tokens: Tokens) {
  response.cookies.set("zettax_access", tokens.accessToken, {
    ...cookieOptions,
    maxAge: tokens.accessTokenExpiresIn,
  });
  response.cookies.set("zettax_refresh", tokens.refreshToken, {
    ...cookieOptions,
    maxAge: 30 * 86400,
  });
}
async function upstream(
  path: string,
  method: string,
  body?: unknown,
  token?: string,
  key?: string,
) {
  return fetch(`${base}/${path}`, {
    method,
    cache: "no-store",
    signal: AbortSignal.timeout(20000),
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(key ? { "Idempotency-Key": key } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
async function rotate(refresh: string): Promise<Tokens | null> {
  const now = Date.now();
  for (const [key, entry] of refreshes)
    if (entry.expires < now) refreshes.delete(key);
  const existing = refreshes.get(refresh);
  if (existing) return existing.pending;
  const pending = (async () => {
    const result = await upstream("auth/refresh", "POST", {
      refreshToken: refresh,
    });
    const json = await result.json();
    return result.ok ? (json.data as Tokens) : null;
  })();
  // Short single-flight grace for parallel browser requests using an old cookie.
  refreshes.set(refresh, { expires: now + 30000, pending });
  return pending;
}
async function handle(
  request: NextRequest,
  context: { params: Promise<{ path: string[] }> },
) {
  const path = (await context.params).path.join("/");
  const method = request.method;
  if (method === "POST") {
    if (
      request.headers.get("origin") !== request.nextUrl.origin ||
      request.headers.get("sec-fetch-site") === "cross-site"
    )
      return NextResponse.json(
        { message: "Invalid request origin." },
        { status: 403 },
      );
    if (!request.headers.get("content-type")?.startsWith("application/json"))
      return NextResponse.json({ message: "JSON required." }, { status: 415 });
  }
  if (path === "config" && method === "GET")
    return NextResponse.json(
      {
        data: {
          googleClientId: process.env.GOOGLE_WEB_CLIENT_ID || "",
          socketOrigin: new URL(base).origin,
        },
      },
      { headers: { "Cache-Control": "no-store" } },
    );
  if (!(method === "GET" ? reads : writes).test(path))
    return NextResponse.json({ message: "Not found." }, { status: 404 });
  try {
    let body: Record<string, unknown> | undefined;
    if (method === "POST") {
      const raw = await request.text();
      if (raw.length > 16000)
        return NextResponse.json(
          { message: "Request too large." },
          { status: 413 },
        );
      body = JSON.parse(raw);
      if (!body || typeof body !== "object" || Array.isArray(body))
        return NextResponse.json(
          { message: "Invalid request." },
          { status: 400 },
        );
    }
    const auth = /auth\/(login|register|google)$/.test(path);
    let device = request.cookies.get("zettax_device")?.value;
    if (auth) {
      device ||= randomUUID();
      body = {
        ...body,
        deviceFingerprint: device,
        deviceName: "Zettax website",
        devicePlatform: "web",
      };
    }
    const query = new URLSearchParams();
    for (const key of [
      "afterSequence",
      "cursor",
      "search",
      "source",
      "status",
      "sort",
    ]) {
      const value = request.nextUrl.searchParams.get(key);
      if (value) query.set(key, value);
    }
    const target = `${path}${query.size ? `?${query}` : ""}`;
    const idempotency = request.headers.get("idempotency-key") || undefined;
    let tokens: Tokens | null = null;
    let result = await upstream(
      target,
      method,
      body,
      request.cookies.get("zettax_access")?.value,
      idempotency,
    );
    const refresh = request.cookies.get("zettax_refresh")?.value;
    if (result.status === 401 && refresh && !auth) {
      tokens = await rotate(refresh);
      if (tokens)
        result = await upstream(
          target,
          method,
          body,
          tokens.accessToken,
          idempotency,
        );
    }
    const json = await result.json();
    if (auth && result.ok) {
      tokens = json.data;
      json.data = { user: tokens?.user };
    }
    const response = NextResponse.json(json, {
      status: result.status,
      headers: { "Cache-Control": "no-store" },
    });
    if (tokens) setTokens(response, tokens);
    if (auth && result.ok && device)
      response.cookies.set("zettax_device", device, {
        ...cookieOptions,
        maxAge: 365 * 86400,
      });
    if ((path === "auth/logout" && result.ok) || result.status === 401) {
      for (const name of ["zettax_access", "zettax_refresh"])
        response.cookies.set(name, "", { ...cookieOptions, maxAge: 0 });
    }
    return response;
  } catch {
    return NextResponse.json(
      { message: "The service could not be reached. Retry safely." },
      { status: 503 },
    );
  }
}
export const GET = handle;
export const POST = handle;
