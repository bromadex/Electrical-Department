// The callee's phone says "my phone is ringing" (#calls). Android's
// incoming-call screen sends { notification_id } as soon as it shows,
// also from the background when the app is closed, where nobody is signed
// in. The call alert's id reached only the callee's phone, so it is the
// proof; fn_call_rang (service role only) marks the call as ringing, and
// the caller's screen changes from "Calling…" to "Ringing…".

import { createClient } from "jsr:@supabase/supabase-js@2";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
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

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, { error: "INVALID: Use POST" });
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const id = typeof body.notification_id === "string" ? body.notification_id : "";
  if (!uuid.test(id)) return reply(400, { error: "INVALID: Unknown call" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS"),
    { auth: { persistSession: false } },
  );
  const { data, error } = await admin.rpc("fn_call_rang", { p_notification: id });
  if (error) return reply(500, { error: `FAILED: ${error.message}` });
  return reply(200, { ringing: data === true });
});
