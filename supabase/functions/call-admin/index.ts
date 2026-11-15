// The chair's controls in a chat's call (LiveKit server API). The app sends
// { conversation_id, action, identity? } with the user's sign-in:
//   mute       mute one person's microphone (identity)
//   mute_all   mute everyone else's microphone
//   lower      lower one person's raised hand (identity), or everyone's
//   remove     remove one person from the call (identity)
//   end        end the call for everyone
//   check      only answer whether the caller chairs ({ ok, chair })
// Muted and removed people get a "chair" data message so the app can say
// why ("The chair muted you"); they can unmute themselves, as on Zoom.
//
// Who chairs: in a meeting that is on in the chat (15 minutes before its
// start to an hour after its end), its chair or someone with
// meetings.manage at its site; otherwise, in a group chat, whoever started
// the live call or a chat owner. Direct calls have no chair. Everything is
// read with the caller's own sign-in, so row security applies.
//
// Secrets: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET (as livekit-token).
// Replies { ok, changed } or { "error": "CODE: message" }.

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const actions = new Set(["mute", "mute_all", "lower", "remove", "end", "check"]);

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

type Track = { sid: string; type?: string | number; source?: string | number; muted?: boolean };
type LkParticipant = { identity: string; tracks?: Track[]; attributes?: Record<string, string> };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "INVALID: Use POST" });

  const livekitUrl = (Deno.env.get("LIVEKIT_URL") ?? "").trim()
    .replace(/^wss:\/\//, "https://").replace(/^ws:\/\//, "http://").replace(/\/+$/, "");
  const apiKey = (Deno.env.get("LIVEKIT_API_KEY") ?? "").trim();
  const apiSecret = (Deno.env.get("LIVEKIT_API_SECRET") ?? "").trim();
  if (!livekitUrl || !apiKey || !apiSecret) {
    return reply(503, { error: "UNAVAILABLE: Calls are not set up yet" });
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) return reply(401, { error: "NOT_ALLOWED: Sign in first" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "INVALID: The request is not valid JSON" });
  }
  const conversationId = typeof body.conversation_id === "string" ? body.conversation_id : "";
  const action = typeof body.action === "string" ? body.action : "";
  const identity = typeof body.identity === "string" ? body.identity : "";
  if (!uuid.test(conversationId)) return reply(400, { error: "INVALID: Unknown chat" });
  if (!actions.has(action)) return reply(400, { error: "INVALID: Unknown action" });
  const person = /^(guest-)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if ((action === "mute" || action === "remove") && !person.test(identity)) {
    return reply(400, { error: "INVALID: Say who" });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS"),
    { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } },
  );
  const { data: who } = await db.auth.getUser();
  const me = who?.user?.id;
  if (!me) return reply(401, { error: "NOT_ALLOWED: Sign in first" });

  // ---- Is the caller the chair?
  const { data: chat } = await db.from("conversations").select("id, kind")
    .eq("id", conversationId).maybeSingle();
  if (!chat) return reply(404, { error: "NOT_FOUND: Chat not found" });
  if (chat.kind === "direct") {
    if (action === "check") return reply(200, { ok: true, chair: false });
    return reply(403, { error: "NOT_ALLOWED: A direct call has no chair" });
  }
  let chair = false;
  const now = Date.now();
  const { data: meetings } = await db.from("meetings")
    .select("chair_id, site_id, starts_at, duration_min")
    .eq("conversation_id", conversationId).eq("status", "scheduled")
    .gte("starts_at", new Date(now - 24 * 3600 * 1000).toISOString())
    .lte("starts_at", new Date(now + 15 * 60 * 1000).toISOString())
    .order("starts_at", { ascending: false });
  const meeting = (meetings ?? []).find((m) => {
    const start = Date.parse(m.starts_at);
    return now >= start - 15 * 60_000 && now <= start + (m.duration_min + 60) * 60_000;
  });
  if (meeting) {
    chair = meeting.chair_id === me;
    if (!chair) {
      const { data: perms } = await db.rpc("my_permissions");
      chair = ((perms ?? []) as { code: string; site_id: string | null }[]).some((p) =>
        p.code === "meetings.manage" && (p.site_id === null || p.site_id === meeting.site_id)
      );
    }
  } else {
    const { data: live } = await db.from("calls").select("id")
      .eq("conversation_id", conversationId).is("ended_at", null).eq("started_by", me).limit(1);
    chair = (live ?? []).length > 0;
    if (!chair) {
      const { data: member } = await db.from("conversation_members").select("role")
        .eq("conversation_id", conversationId).eq("user_id", me).maybeSingle();
      chair = member?.role === "owner";
    }
  }
  if (action === "check") return reply(200, { ok: true, chair });
  if (!chair) return reply(403, { error: "NOT_ALLOWED: Only the chair can do that" });

  // ---- LiveKit.
  const room = `chat-${conversationId}`;
  const t = Math.floor(now / 1000);
  const token = await sign({
    iss: apiKey,
    sub: `chair-${me}`,
    nbf: t - 10,
    exp: t + 120,
    video: { room, roomAdmin: true, roomList: true },
  }, apiSecret);
  const lk = async (method: string, payload: Record<string, unknown>) => {
    const res = await fetch(`${livekitUrl}/twirp/livekit.RoomService/${method}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${res.status}: ${text.slice(0, 160)}`);
    return text ? JSON.parse(text) : {};
  };
  const tell = (to: string[], what: string) =>
    lk("SendData", {
      room,
      data: btoa(JSON.stringify({ a: what })),
      kind: 0, // reliable
      destination_identities: to,
      topic: "chair",
    }).catch(() => {});
  const isMic = (k: Track) =>
    k.source === "MICROPHONE" || k.source === 2 || (k.type === "AUDIO" || k.type === 0);

  try {
    let changed = 0;
    if (action === "end") {
      await tell([], "ended");
      await lk("DeleteRoom", { room });
      changed = 1;
    } else if (action === "remove") {
      await tell([identity], "removed");
      await lk("RemoveParticipant", { room, identity });
      changed = 1;
    } else {
      const { participants } = await lk("ListParticipants", { room }) as {
        participants?: LkParticipant[];
      };
      const people = (participants ?? []).filter((p) =>
        action === "mute_all" ? p.identity !== me
        : action === "lower" ? (!identity || p.identity === identity)
        : p.identity === identity
      );
      for (const p of people) {
        if (action === "lower") {
          if ((p.attributes?.hand ?? "0") === "0") continue;
          await lk("UpdateParticipant", { room, identity: p.identity, attributes: { hand: "0" } });
          changed++;
          continue;
        }
        const mics = (p.tracks ?? []).filter((k) => isMic(k) && !k.muted);
        for (const k of mics) {
          await lk("MutePublishedTrack", { room, identity: p.identity, track_sid: k.sid, muted: true });
        }
        if (mics.length > 0) {
          changed++;
          await tell([p.identity], "muted");
        }
      }
    }
    return reply(200, { ok: true, changed });
  } catch (e) {
    const msg = String(e);
    if (msg.includes(" 404")) return reply(404, { error: "NOT_FOUND: The call has ended" });
    return reply(502, { error: `UNAVAILABLE: The call server did not accept that (${msg.slice(0, 120)})` });
  }
});
