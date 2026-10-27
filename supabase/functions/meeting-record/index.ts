// Records a meeting's audio (#15). The chair sends { meeting_id, action:
// "start" | "stop" } with their sign-in. "start" asks LiveKit Egress to
// record the chat's call (audio only, OGG) straight into the private
// meeting-audio bucket through Supabase Storage's S3 endpoint; "stop" ends
// it. The database (fn_meeting_recording) checks the caller is the chair
// and keeps the state. Errors are { "error": "CODE: message" }.
//
// Secrets: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET (as for calls)
// and MEETING_S3_ENDPOINT (https://<project>.storage.supabase.co/storage/v1/s3),
// MEETING_S3_REGION, MEETING_S3_ACCESS_KEY, MEETING_S3_SECRET_KEY
// (Supabase → Storage → S3 connection → new access key).

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

/** Calls a LiveKit Egress method (Twirp JSON) with a room-record pass. */
async function egress(method: string, body: Record<string, unknown>) {
  const host = (Deno.env.get("LIVEKIT_URL") ?? "").trim()
    .replace(/^wss:\/\//, "https://").replace(/^ws:\/\//, "http://").replace(/\/+$/, "");
  const apiKey = (Deno.env.get("LIVEKIT_API_KEY") ?? "").trim();
  const now = Math.floor(Date.now() / 1000);
  const token = await sign(
    { iss: apiKey, sub: "meeting-record", nbf: now - 10, exp: now + 300, video: { roomRecord: true } },
    (Deno.env.get("LIVEKIT_API_SECRET") ?? "").trim(),
  );
  const res = await fetch(`${host}/twirp/livekit.Egress/${method}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`LiveKit ${res.status}: ${text.slice(0, 300)}`);
  return JSON.parse(text) as Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "INVALID: Use POST" });

  const s3 = {
    endpoint: (Deno.env.get("MEETING_S3_ENDPOINT") ?? "").trim(),
    region: (Deno.env.get("MEETING_S3_REGION") ?? "").trim(),
    access_key: (Deno.env.get("MEETING_S3_ACCESS_KEY") ?? "").trim(),
    secret: (Deno.env.get("MEETING_S3_SECRET_KEY") ?? "").trim(),
  };
  // { "check": true }: which settings are present, and whether LiveKit
  // accepts a recording pass. Shows nothing secret.
  const peek = await req.clone().json().catch(() => ({})) as Record<string, unknown>;
  if (peek.check === true) {
    let livekit = "not tried";
    try {
      await egress("ListEgress", {});
      livekit = "ok";
    } catch (e) {
      livekit = String((e as Error).message).slice(0, 200);
    }
    return reply(200, {
      endpoint: s3.endpoint || null,
      region: s3.region || null,
      access_key_length: s3.access_key.length,
      secret_key_length: s3.secret.length,
      livekit_egress: livekit,
    });
  }
  if (!Deno.env.get("LIVEKIT_URL") || !s3.endpoint || !s3.access_key || !s3.secret) {
    return reply(503, { error: "UNAVAILABLE: Recording is not set up yet" });
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) return reply(401, { error: "NOT_ALLOWED: Sign in first" });
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "INVALID: The request is not valid JSON" });
  }
  const meetingId = typeof body.meeting_id === "string" ? body.meeting_id : "";
  const action = body.action;
  if (!uuid.test(meetingId) || (action !== "start" && action !== "stop")) {
    return reply(400, { error: "INVALID: Send meeting_id and action start or stop" });
  }

  const caller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS"),
    { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } },
  );
  const { data: meeting, error } = await caller.from("meetings")
    .select("id, conversation_id, recording_status, egress_id")
    .eq("id", meetingId).maybeSingle();
  if (error || !meeting) return reply(404, { error: "NOT_FOUND: Meeting not found" });

  // The database decides whether this person may record.
  const save = async (status: string, egressId: string | null, path: string | null, err: string | null) => {
    const { error } = await caller.rpc("fn_meeting_recording", {
      p_meeting: meetingId,
      p_status: status,
      p_egress: egressId,
      p_audio_path: path,
      p_error: err,
    });
    if (error) throw error;
  };

  try {
    if (action === "start") {
      if (meeting.recording_status === "recording") return reply(200, { status: "recording" });
      // Permission first, so nobody else can start a recording.
      await save("none", null, null, null);
      const path = `${meetingId}/audio-${Date.now()}.ogg`;
      const started = await egress("StartRoomCompositeEgress", {
        room_name: `chat-${meeting.conversation_id}`,
        audio_only: true,
        file_outputs: [{
          file_type: "OGG",
          filepath: path,
          s3: { ...s3, bucket: "meeting-audio", force_path_style: true },
        }],
      });
      await save("recording", String(started.egress_id ?? started.egressId ?? ""), path, null);
      return reply(200, { status: "recording" });
    }
    if (meeting.egress_id) {
      try {
        await egress("StopEgress", { egress_id: meeting.egress_id });
      } catch (_) {
        // Already stopped (everyone left): carry on.
      }
    }
    await save("processing", null, null, null);
    return reply(200, { status: "processing" });
  } catch (e) {
    const message = (e as { message?: string }).message ?? String(e);
    if (message.startsWith("NOT_ALLOWED") || message.startsWith("NOT_FOUND")) {
      return reply(403, { error: message });
    }
    try {
      await save("failed", null, null, message);
    } catch (_) { /* keep the first error */ }
    return reply(502, { error: `FAILED: ${message}` });
  }
});
