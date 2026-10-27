// Live captions for meetings (#15). During a meeting each person's app sends
// a short piece of their own voice: { meeting_id, spoken_at, audio (base64),
// mime }, with their sign-in. It is turned into text with Groq's Whisper
// (free plan) and saved as a caption with their name (fn_add_caption, which
// checks they are in the chat and the meeting is on). No audio is kept.
//
// Secret: TRANSCRIBE_API_KEY (a Groq key; GROQ_API_KEY also works).
// Optional: TRANSCRIBE_URL, TRANSCRIBE_MODEL. Errors are { "error": "CODE: message" }.

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// What Whisper tends to "hear" in silence or noise.
const noise = new Set([
  "thank you", "thank you.", "thanks for watching!", "thanks for watching", "you", ".",
  "bye.", "bye", "okay.", "so", "uh", "um", "hmm", "[music]", "[silence]", "...",
]);

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

function fromBase64(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function transcribe(key: string, audio: Uint8Array, mime: string): Promise<string> {
  const url = Deno.env.get("TRANSCRIBE_URL") ?? "https://api.groq.com/openai/v1/audio/transcriptions";
  const ext = mime.includes("webm") ? "webm" : mime.includes("ogg") ? "ogg" : mime.includes("wav") ? "wav" : "m4a";
  const models = Deno.env.get("TRANSCRIBE_MODEL")
    ? [Deno.env.get("TRANSCRIBE_MODEL")!]
    : ["whisper-large-v3-turbo", "whisper-large-v3"];
  let last = "";
  for (const model of models) {
    const form = new FormData();
    form.append("file", new Blob([audio.buffer as ArrayBuffer], { type: mime }), `voice.${ext}`);
    form.append("model", model);
    form.append("response_format", "json");
    form.append("temperature", "0");
    const res = await fetch(url, { method: "POST", headers: { Authorization: `Bearer ${key}` }, body: form });
    const text = await res.text();
    if (res.ok) return String((JSON.parse(text) as { text?: string }).text ?? "").trim();
    last = `${res.status}: ${text.slice(0, 200)}`;
    // A retired model: try the next one; anything else is final.
    if (res.status !== 404 && !/model/i.test(text)) break;
  }
  throw new Error(`FAILED: Transcription ${last}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "INVALID: Use POST" });
  const key = Deno.env.get("TRANSCRIBE_API_KEY") ?? Deno.env.get("GROQ_API_KEY");
  if (!key) return reply(503, { error: "UNAVAILABLE: Live captions are not set up yet" });
  const authorization = req.headers.get("Authorization");
  if (!authorization) return reply(401, { error: "NOT_ALLOWED: Sign in first" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "INVALID: The request is not valid JSON" });
  }
  const meetingId = typeof body.meeting_id === "string" ? body.meeting_id : "";
  const audio = typeof body.audio === "string" ? body.audio : "";
  const mime = typeof body.mime === "string" ? body.mime : "audio/webm";
  const spokenAt = typeof body.spoken_at === "string" ? body.spoken_at : new Date().toISOString();
  if (!uuid.test(meetingId) || !audio) return reply(400, { error: "INVALID: Send meeting_id and audio" });
  if (audio.length > 2_000_000) return reply(400, { error: "INVALID: Send pieces under a minute" });

  let text: string;
  try {
    text = await transcribe(key, fromBase64(audio), mime);
  } catch (e) {
    return reply(502, { error: (e as Error).message });
  }
  const clean = text.replace(/\s+/g, " ").trim();
  if (clean.replace(/[^\p{L}]/gu, "").length < 2 || noise.has(clean.toLowerCase())) {
    return reply(200, { text: "" });
  }

  const caller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS"),
    { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } },
  );
  const { error } = await caller.rpc("fn_add_caption", {
    p_meeting: meetingId,
    p_spoken_at: spokenAt,
    p_body: clean,
  });
  if (error) {
    const status = error.message.startsWith("NOT_FOUND") ? 404 : 400;
    return reply(status, { error: error.message });
  }
  return reply(200, { text: clean });
});
