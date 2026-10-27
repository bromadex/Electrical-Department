// Drafts a meeting's minutes (#15). The chair sends { meeting_id, notes? }
// with their sign-in. The source is the typed notes, else the meeting's
// live captions (fn_meeting_transcript). An AI model writes the minutes as
// JSON: a summary, decisions and action items with an owner and due date.
// They are saved as a draft (fn_save_minutes, chair only) for the chair to
// edit and approve.
//
// Model: Groq's free models with TRANSCRIBE_API_KEY (or GROQ_API_KEY); if
// ANTHROPIC_API_KEY is set, Claude is used instead. MINUTES_MODEL picks a
// Groq model. Errors are { "error": "CODE: message" }.

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

/** Groq's OpenAI-compatible API (GROQ_BASE_URL overrides it for tests). */
const groqBase = () => (Deno.env.get("GROQ_BASE_URL") ?? "https://api.groq.com/openai/v1").replace(/\/+$/, "");

/** A free Groq chat model that is still offered, best first. */
async function groqModel(key: string): Promise<string> {
  const chosen = Deno.env.get("MINUTES_MODEL");
  if (chosen) return chosen;
  const preferred = ["openai/gpt-oss-120b", "llama-3.3-70b-versatile", "openai/gpt-oss-20b", "llama-3.1-8b-instant"];
  try {
    const res = await fetch(`${groqBase()}/models`, {
      headers: { Authorization: `Bearer ${key}` },
    });
    const ids = new Set(((await res.json()).data ?? []).map((m: { id: string }) => m.id));
    return preferred.find((m) => ids.has(m)) ?? preferred[0];
  } catch {
    return preferred[0];
  }
}

const instructions =
  "You write the minutes of an electrical department's work meeting at a mine. " +
  "Be brief and factual, in plain English. The summary is 2 to 6 sentences. " +
  "Decisions are what was agreed. Actions are concrete tasks; owner_name is one of " +
  "the people listed when the source makes the owner clear, otherwise an empty " +
  "string; due is a date as YYYY-MM-DD when one was said, otherwise an empty string. " +
  "Never invent decisions, owners or dates that the source does not support.";

/** Free: Groq, JSON mode. */
async function groqDraft(key: string, prompt: string): Promise<Minutes> {
  const res = await fetch(`${groqBase()}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: await groqModel(key),
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: instructions +
            ' Answer with JSON only: {"summary": string, "decisions": [string], ' +
            '"actions": [{"text": string, "owner_name": string, "due": string}]}.',
        },
        { role: "user", content: prompt },
      ],
    }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`FAILED: Drafting ${res.status}: ${text.slice(0, 200)}`);
  const content = JSON.parse(text).choices?.[0]?.message?.content ?? "{}";
  const j = JSON.parse(content) as Partial<Minutes>;
  return {
    summary: String(j.summary ?? ""),
    decisions: Array.isArray(j.decisions) ? j.decisions.map(String) : [],
    actions: Array.isArray(j.actions)
      ? j.actions.map((a) => ({
        text: String(a?.text ?? ""),
        owner_name: String(a?.owner_name ?? ""),
        due: String(a?.due ?? ""),
      })).filter((a) => a.text)
      : [],
  };
}

/** Claude, when ANTHROPIC_API_KEY is set. */
async function claudeDraft(prompt: string): Promise<Minutes> {
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
    system: instructions,
    messages: [{ role: "user", content: prompt }],
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
  const groq = Deno.env.get("TRANSCRIBE_API_KEY") ?? Deno.env.get("GROQ_API_KEY");
  const claude = Deno.env.get("ANTHROPIC_API_KEY");

  // { "check": true }: whether the keys are accepted and which model drafts
  // (lists models; costs nothing). Shows nothing secret.
  const peek = await req.clone().json().catch(() => ({})) as Record<string, unknown>;
  if (peek.check === true) {
    let groqStatus = "missing";
    if (groq) {
      const res = await fetch(`${groqBase()}/models`, {
        headers: { Authorization: `Bearer ${groq}` },
      }).catch(() => null);
      groqStatus = res?.ok ? "ok" : `${res?.status ?? "unreachable"}`;
    }
    return reply(200, {
      groq: groqStatus,
      drafts_with: claude ? "claude-opus-5-5" : groq ? await groqModel(groq) : "nothing",
    });
  }
  if (!groq && !claude) {
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
    .select("id, conversation_id, title, agenda, starts_at, minutes_status")
    .eq("id", meetingId).maybeSingle();
  if (!m) return reply(404, { error: "NOT_FOUND: Meeting not found" });
  if (m.minutes_status === "approved") {
    return reply(400, { error: "INVALID: These minutes are already approved" });
  }

  try {
    // 1. What was said: typed notes, else the live captions.
    const { data: transcript } = await caller.rpc("fn_meeting_transcript", { p_meeting: meetingId });
    const source = notes || (typeof transcript === "string" ? transcript : "");
    if (source.length < 20) {
      return reply(400, { error: "INVALID: Hold the meeting with captions on, or type some notes first" });
    }

    // 2. Who could own actions: the chat's members.
    const { data: members } = await caller.from("conversation_members")
      .select("user_id").eq("conversation_id", m.conversation_id).eq("is_archived", false);
    const ids = (members ?? []).map((r) => r.user_id as string);
    const { data: profiles } = ids.length
      ? await caller.from("profiles").select("id, full_name").in("id", ids)
      : { data: [] };
    const people = (profiles ?? []).filter((p) => p.full_name) as { id: string; full_name: string }[];

    // 3. Draft; owners are matched back to people by name.
    const when = new Date(m.starts_at).toLocaleString("en-GB", { timeZone: "Africa/Harare" });
    const prompt = `Meeting: ${m.title}\nWhen: ${when}\n` +
      (m.agenda ? `Agenda:\n${m.agenda}\n` : "") +
      `People in the chat: ${people.map((p) => p.full_name).join(", ") || "unknown"}\n\n` +
      `${notes ? "Notes" : "Transcript"}:\n${source}`;
    const minutes = claude ? await claudeDraft(prompt) : await groqDraft(groq!, prompt);
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
      p_transcript: notes ? null : source,
      p_minutes: saved,
    });
    if (error) return reply(403, { error: error.message });
    return reply(200, { minutes: saved });
  } catch (e) {
    const message = (e as { message?: string }).message ?? String(e);
    const status = message.startsWith("UNAVAILABLE") ? 503 : 502;
    return reply(status, { error: message.match(/^[A-Z_]+: /) ? message : `FAILED: ${message}` });
  }
});
