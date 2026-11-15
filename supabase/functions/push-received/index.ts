// A push reached a phone. The app sends { notification_id } as soon as the
// alert arrives, also from the background when the app is closed, where
// nobody is signed in. The alert's id reached only that person's phone, so
// it is the proof; fn_push_received (service role only) acts on it:
//   * a call alert marks the call ringing ("Calling…" becomes "Ringing…");
//   * a chat alert marks that chat's messages delivered (two grey ticks).

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
  if (!uuid.test(id)) return reply(400, { error: "INVALID: Unknown alert" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS"),
    { auth: { persistSession: false } },
  );
  const { data, error } = await admin.rpc("fn_push_received", { p_notification: id });
  if (error) return reply(500, { error: `FAILED: ${error.message}` });
  return reply(200, { ok: data === true });
});
