// Drafts a meeting's minutes (#15). The chair sends { meeting_id, notes? }
// with their sign-in. With a recording, the audio is transcribed (Whisper,
// an OpenAI-compatible endpoint such as Groq); with only typed notes, the
// notes are used. Claude then writes the minutes as JSON: a summary,
// decisions and action items with an owner and due date. They are saved as
// a draft (fn_save_minutes, chair only) for the chair to edit and approve.
//
// Secrets: ANTHROPIC_API_KEY. For recordings also TRANSCRIBE_API_KEY, and
// optionally TRANSCRIBE_URL (default Groq) and TRANSCRIBE_MODEL.
// Errors are { "error": "CODE: message" }.

import { createClient } from "jsr:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk@1.3.0";

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

const minutesSchema = {
  type: "object",
  properties: {
    summary: { type: "string" },
    decisions: { type: "array", items: { type: "string" } },
    actions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          text: { type: "string" },
          owner_name: { type: "string" },
          due: { type: "string" },
        },
        required: ["text", "owner_name", "due"],
        additionalProperties: false,
      },
    },
  },
  required: ["summary", "decisions", "actions"],
  additionalProperties: false,
};

type Minutes = {
  summary: string;
  decisions: string[];
  actions: { text: string; owner_name: string; due: string }[];
};

async function transcribe(audio: Blob, name: string): Promise<string> {
  const key = Deno.env.get("TRANSCRIBE_API_KEY");
  if (!key) throw new Error("UNAVAILABLE: Transcription is not set up yet");
  const form = new FormData();
  form.append("file", audio, name);
  form.append("model", Deno.env.get("TRANSCRIBE_MODEL") ?? "whisper-large-v3");
  form.append("response_format", "json");
  const res = await fetch(
    Deno.env.get("TRANSCRIBE_URL") ?? "https://api.groq.com/openai/v1/audio/transcriptions",
    { method: "POST", headers: { Authorization: `Bearer ${key}` }, body: form },
  );
  const text = await res.text();
  if (!res.ok) throw new Error(`FAILED: Transcription ${res.status}: ${text.slice(0, 200)}`);
  return String((JSON.parse(text) as { text?: string }).text ?? "").trim();
}

async function draft(
  title: string,
  agenda: string | null,
  when: string,
  people: string[],
  source: string,
): Promise<Minutes> {
  const client = new Anthropic();
  const response = await client.beta.messages.create({
    model: "claude-opus-5-5",
    max_tokens: 16000,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    output_config: {
      effort: "medium",
      format: { type: "json_schema", schema: minutesSchema },
    },
    system:
      "You write the minutes of an electrical department's work meeting at a mine. " +
      "Be brief and factual, in plain English. The summary is 2 to 6 sentences. " +
      "Decisions are what was agreed. Actions are concrete tasks; owner_name is one of " +
      "the people listed when the transcript makes the owner clear, otherwise an empty " +
      "string; due is a date as YYYY-MM-DD when one was said, otherwise an empty string. " +
      "Never invent decisions, owners or dates that the source does not support.",
    messages: [{
      role: "user",
      content:
        `Meeting: ${title}\nWhen: ${when}\n` +
        (agenda ? `Agenda:\n${agenda}\n` : "") +
        `People in the chat: ${people.join(", ") || "unknown"}\n\n` +
        `Transcript or notes:\n${source}`,
    }],
  } as unknown as Anthropic.Beta.MessageCreateParamsNonStreaming);

  if (response.stop_reason === "refusal") {
    throw new Error("FAILED: The minutes could not be drafted for this meeting");
  }
  const text = response.content
    .filter((b) => b.type === "text")
    .map((b) => (b as { text: string }).text)
    .join("");
  return JSON.parse(text) as Minutes;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "INVALID: Use POST" });
  if (!Deno.env.get("ANTHROPIC_API_KEY")) {
    return reply(503, { error: "UNAVAILABLE: AI minutes are not set up yet" });
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
  const notes = typeof body.notes === "string" ? body.notes.trim() : "";
  if (!uuid.test(meetingId)) return reply(400, { error: "INVALID: Unknown meeting" });

  const caller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS"),
    { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } },
  );
  const { data: m } = await caller.from("meetings")
    .select("id, conversation_id, title, agenda, starts_at, audio_path, transcript, minutes_status")
    .eq("id", meetingId).maybeSingle();
  if (!m) return reply(404, { error: "NOT_FOUND: Meeting not found" });
  if (m.minutes_status === "approved") {
    return reply(400, { error: "INVALID: These minutes are already approved" });
  }

  try {
    // 1. What was said: the recording, else the typed notes.
    let transcript: string | null = m.transcript;
    if (!transcript && m.audio_path && !notes) {
      const service = createClient(
        Deno.env.get("SUPABASE_URL")!,
        projectKey("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS"),
        { auth: { persistSession: false } },
      );
      const { data: audio, error } = await service.storage.from("meeting-audio").download(m.audio_path);
      if (error || !audio) {
        return reply(409, { error: "NOT_READY: The recording is still being saved. Try again in a minute." });
      }
      transcript = await transcribe(audio, m.audio_path.split("/").pop() ?? "audio.ogg");
    }
    const source = notes || transcript || "";
    if (source.length < 20) {
      return reply(400, { error: "INVALID: Record the meeting or type some notes first" });
    }

    // 2. Who could own actions: the chat's members.
    const { data: members } = await caller.from("conversation_members")
      .select("user_id").eq("conversation_id", m.conversation_id).eq("is_archived", false);
    const ids = (members ?? []).map((r) => r.user_id as string);
    const { data: profiles } = ids.length
      ? await caller.from("profiles").select("id, full_name").in("id", ids)
      : { data: [] };
    const people = (profiles ?? []).filter((p) => p.full_name) as { id: string; full_name: string }[];

    // 3. Claude drafts; owners are matched back to people by name.
    const when = new Date(m.starts_at).toLocaleString("en-GB", { timeZone: "Africa/Harare" });
    const minutes = await draft(m.title, m.agenda, when, people.map((p) => p.full_name), source);
    const match = (name: string) => {
      const n = name.trim().toLowerCase();
      if (!n) return null;
      return people.find((p) => p.full_name.toLowerCase() === n) ??
        people.find((p) => p.full_name.toLowerCase().split(" ")[0] === n.split(" ")[0]) ?? null;
    };
    const saved = {
      summary: minutes.summary,
      decisions: minutes.decisions,
      actions: minutes.actions.map((a) => ({
        text: a.text,
        owner_id: match(a.owner_name)?.id ?? null,
        owner_name: match(a.owner_name)?.full_name ?? (a.owner_name || null),
        due: /^\d{4}-\d{2}-\d{2}$/.test(a.due) ? a.due : null,
      })),
    };
    const { error } = await caller.rpc("fn_save_minutes", {
      p_meeting: meetingId,
      p_transcript: transcript && !m.transcript ? transcript : null,
      p_minutes: saved,
    });
    if (error) return reply(403, { error: error.message });
    if (m.audio_path) {
      await caller.rpc("fn_meeting_recording", {
        p_meeting: meetingId, p_status: "ready", p_egress: null, p_audio_path: null, p_error: null,
      });
    }
    return reply(200, { minutes: saved });
  } catch (e) {
    const message = (e as { message?: string }).message ?? String(e);
    const status = message.startsWith("UNAVAILABLE") ? 503 : 502;
    return reply(status, { error: message.match(/^[A-Z_]+: /) ? message : `FAILED: ${message}` });
  }
});
