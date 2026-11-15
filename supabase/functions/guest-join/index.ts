// Join a call by link, for outsiders without an account (migration 0048).
// No sign-in (verify_jwt = false); the link's token and the guest's own
// secret are the proof.
//   { token, name }          → asks to join: { guest_id, secret, title }
//   { guest_id, secret }     → { status: waiting | denied | ended } or,
//                              once someone in the call admits them,
//                              { status: "admitted", url, token, title }
// The LiveKit pass is for that chat's call only and ends with the link
// (two hours at most). Guests show as "<name> (guest)".
//
// Secrets: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function projectKey(legacy: string, current: string): string {
  const v = Deno.env.get(legacy);
  if (v) return v;
  try {
    const keys = JSON.parse(Deno.env.get(current) ?? "{}") as Record<string, string>;
    return keys.default ?? Object.values(keys)[0] ?? "";
  } catch {
    return "";
  }
}

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sign(payload: Record<string, unknown>, secret: string): Promise<string> {
  const head = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = base64url(JSON.stringify(payload));
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${base64url(new Uint8Array(mac))}`;
}

async function sha256(text: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "INVALID: Use POST" });

  const livekitUrl = (Deno.env.get("LIVEKIT_URL") ?? "").trim()
    .replace(/^https:\/\//, "wss://").replace(/^http:\/\//, "ws://").replace(/\/+$/, "");
  const apiKey = (Deno.env.get("LIVEKIT_API_KEY") ?? "").trim();
  const apiSecret = (Deno.env.get("LIVEKIT_API_SECRET") ?? "").trim();
  if (!livekitUrl || !apiKey || !apiSecret) {
    return reply(503, { error: "UNAVAILABLE: Calls are not set up yet" });
  }

  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS"),
    { auth: { persistSession: false } },
  );
  const message = (e: { message?: string } | null) =>
    (e?.message ?? "FAILED: Something went wrong").replace(/^.*?([A-Z_]+: )/, "$1");

  // 1. Ask to join.
  if (typeof body.token === "string") {
    const token = body.token.trim();
    const name = typeof body.name === "string" ? body.name.trim() : "";
    if (!/^[0-9a-f]{64}$/.test(token)) return reply(404, { error: "NOT_FOUND: Unknown link" });
    const secret = base64url(crypto.getRandomValues(new Uint8Array(24)));
    const { data, error } = await admin.rpc("fn_guest_request", {
      p_token: token,
      p_name: name.slice(0, 60),
      p_secret_hash: await sha256(secret),
    });
    if (error) {
      const m = message(error);
      return reply(m.startsWith("NOT_FOUND") ? 404 : 400, { error: m });
    }
    const d = data as { guest_id: string; title: string; expires_at: string };
    return reply(200, { guest_id: d.guest_id, secret, title: d.title, expires_at: d.expires_at });
  }

  // 2. Waiting: has someone let them in?
  const guestId = typeof body.guest_id === "string" ? body.guest_id : "";
  const secret = typeof body.secret === "string" ? body.secret : "";
  if (!uuid.test(guestId) || !secret) return reply(400, { error: "INVALID: Send token or guest_id" });
  const { data, error } = await admin.rpc("fn_guest_status", {
    p_guest: guestId,
    p_secret_hash: await sha256(secret),
  });
  if (error) return reply(500, { error: message(error) });
  if (!data) return reply(404, { error: "NOT_FOUND: Unknown guest" });
  const g = data as {
    status: string;
    conversation_id: string;
    name: string;
    expires_at: string;
    title: string;
  };
  if (g.status !== "admitted") return reply(200, { status: g.status, title: g.title });

  const now = Math.floor(Date.now() / 1000);
  const ends = Math.min(Math.floor(Date.parse(g.expires_at) / 1000), now + 2 * 3600);
  const pass = await sign({
    iss: apiKey,
    sub: `guest-${guestId}`,
    name: `${g.name} (guest)`,
    nbf: now - 10,
    exp: ends,
    video: {
      room: `chat-${g.conversation_id}`,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      canUpdateOwnMetadata: true,
    },
  }, apiSecret);
  return reply(200, { status: "admitted", url: livekitUrl, token: pass, title: g.title });
});
