// A pass into a chat's call (LiveKit). The app sends { "conversation_id" }
// with the user's sign-in; the database (fn_start_call) checks they are in
// that chat, names the room and tells the others a call started. This
// function then signs a LiveKit access token with the project's API secret,
// which never leaves the server, and returns { url, token, room, title,
// call_id }. The app then sends fn_call_heartbeat / fn_leave_call.
//
// Secrets (Supabase → Edge Functions → Secrets): LIVEKIT_URL,
// LIVEKIT_API_KEY, LIVEKIT_API_SECRET. Errors are { "error": "CODE: message" }.

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** How long a pass is good for; a call keeps going after it expires. */
const ttlSeconds = 2 * 60 * 60;

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// The legacy variable if present, else the default of the newer JSON one.
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

/** HS256 JWT, as LiveKit expects. */
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "INVALID: Use POST" });

  // Accept the address however it was pasted: trimmed, wss:// for https://.
  const livekitUrl = (Deno.env.get("LIVEKIT_URL") ?? "").trim()
    .replace(/^https:\/\//, "wss://").replace(/^http:\/\//, "ws://").replace(/\/+$/, "");
  const apiKey = (Deno.env.get("LIVEKIT_API_KEY") ?? "").trim();
  const apiSecret = (Deno.env.get("LIVEKIT_API_SECRET") ?? "").trim();
  if (!livekitUrl || !apiKey || !apiSecret) {
    return reply(503, { error: "UNAVAILABLE: Calls are not set up yet" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "INVALID: The request is not valid JSON" });
  }

  // { "check": true }: asks LiveKit whether the key and secret are accepted
  // at LIVEKIT_URL. Shows nothing secret (the key name is in every pass).
  if (body.check === true) {
    const now = Math.floor(Date.now() / 1000);
    const probe = await sign({ iss: apiKey, sub: "setup-check", nbf: now - 10, exp: now + 60, video: { roomList: true } }, apiSecret);
    const host = livekitUrl.replace(/^wss:\/\//, "https://").replace(/^ws:\/\//, "http://");
    let status = 0;
    let answer = "";
    try {
      const res = await fetch(`${host}/twirp/livekit.RoomService/ListRooms`, {
        method: "POST",
        headers: { Authorization: `Bearer ${probe}`, "Content-Type": "application/json" },
        body: "{}",
      });
      status = res.status;
      answer = (await res.text()).slice(0, 200);
    } catch (e) {
      answer = String(e).slice(0, 200);
    }
    return reply(200, {
      livekit_host: new URL(host).host,
      api_key: apiKey,
      secret_length: apiSecret.length,
      livekit_status: status,
      livekit_answer: answer,
    });
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) return reply(401, { error: "NOT_ALLOWED: Sign in first" });

  const conversationId = typeof body.conversation_id === "string" ? body.conversation_id : "";
  if (!uuid.test(conversationId)) return reply(400, { error: "INVALID: Unknown chat" });

  // The caller's own sign-in: the database decides whether they may join.
  const caller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS"),
    { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } },
  );
  const { data, error } = await caller.rpc("fn_start_call", {
    p_conversation: conversationId,
    p_video: body.video === true,
  });
  if (error) {
    const message = error.message || "NOT_FOUND: Chat not found";
    const status = message.startsWith("NOT_ALLOWED") ? 403 : message.startsWith("NOT_FOUND") ? 404 : 400;
    return reply(status, { error: message });
  }
  const call = data as { room: string; identity: string; name: string; title: string; call_id: string };

  const now = Math.floor(Date.now() / 1000);
  const token = await sign({
    iss: apiKey,
    sub: call.identity,
    name: call.name,
    nbf: now - 10,
    exp: now + ttlSeconds,
    video: {
      room: call.room,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    },
  }, apiSecret);

  return reply(200, { url: livekitUrl, token, room: call.room, title: call.title, call_id: call.call_id });
});
