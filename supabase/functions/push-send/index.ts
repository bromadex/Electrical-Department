// Sends one notification to the person's phones and browsers through
// Firebase Cloud Messaging (API.md section 8).
//
// Called by the database (trigger notifications_push, through pg_net) with
// { "notification_id" } and the x-push-secret header. The secret is checked
// by fn_push_job, which also returns the message and the device tokens.
//
// Secrets (Supabase → Edge Functions → Secrets; CI sets them):
//   FIREBASE_SERVICE_ACCOUNT  the Firebase Admin SDK service account JSON
//   APP_URL                   optional, e.g. https://electrical-department-lake.vercel.app
//                             (browser notifications open the job there)

import { createClient } from "jsr:@supabase/supabase-js@2";

type Job = {
  id: string;
  type: string;
  title: string;
  body: string | null;
  link: string | null;
  tokens: { token: string; platform: "android" | "web" }[];
};

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const URGENT = new Set(["critical", "overdue", "assigned", "reassigned"]);

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

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Same mapping as the app's notificationPath: `jobcard:<id>` → `/jobs/<id>`, `servicerequest:<id>` → `/requests/<id>`, `chat:<id>` → `/chat/<id>`, and so on. */
function appPath(link: string | null): string | null {
  if (!link) return null;
  const [kind, id] = link.split(":", 2);
  if (!id) return null;
  if (kind === "jobcard") return `/jobs/${id}`;
  if (kind === "servicerequest") return `/requests/${id}`;
  if (kind === "asset") return `/assets/${id}`;
  if (kind === "chat") return `/chat/${id}`;
  if (kind === "call") return `/chat/${id}/call`;
  if (kind === "meeting") return `/meetings/${id}`;
  if (kind === "tool") return `/tools/${id}`;
  if (kind === "doc") return `/documents/${id}`;
  if (kind === "checklist") return `/checklists/${id}`;
  if (kind === "request") return "/requests";
  return null;
}

function base64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cachedToken: { value: string; expires: number } | null = null;

/** An OAuth access token for FCM, signed with the service account key. */
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expires - 60 > now) return cachedToken.value;

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${base64url(signature)}`,
    }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`Google sign-in failed: ${JSON.stringify(body)}`);
  cachedToken = { value: body.access_token, expires: now + (body.expires_in ?? 3600) };
  return cachedToken.value;
}

function message(job: Job, token: string, appUrl: string | null) {
  const path = appPath(job.link);
  const urgent = URGENT.has(job.type);
  const webLink = appUrl ? `${appUrl.replace(/\/$/, "")}/${path ? `#${path}` : ""}` : undefined;
  return {
    message: {
      token,
      notification: { title: job.title, body: job.body ?? "" },
      // url: where a browser notification opens (firebase-messaging-sw.js).
      data: { link: job.link ?? "", type: job.type, notification_id: job.id, url: webLink ?? "" },
      android: {
        priority: urgent ? "HIGH" : "NORMAL",
        notification: { tag: job.link ?? job.id },
      },
      webpush: {
        headers: { Urgency: urgent ? "high" : "normal" },
        notification: appUrl ? { icon: `${appUrl.replace(/\/$/, "")}/icons/Icon-192.png` } : {},
        ...(webLink ? { fcm_options: { link: webLink } } : {}),
      },
    },
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, { error: "INVALID: Use POST" });

  const secret = req.headers.get("x-push-secret") ?? "";
  let notificationId = "";
  try {
    notificationId = String((await req.json()).notification_id ?? "");
  } catch {
    return reply(400, { error: "INVALID: The request is not valid JSON" });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    projectKey("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS"),
    { auth: { persistSession: false } },
  );
  const { data, error } = await db.rpc("fn_push_job", { p_notification: notificationId, p_secret: secret });
  if (error) {
    const status = error.message.startsWith("NOT_ALLOWED") ? 403 : 400;
    return reply(status, { error: error.message });
  }
  const job = data as Job;
  if (job.tokens.length === 0) return reply(200, { sent: 0, dropped: 0 });

  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return reply(503, { error: "SERVER: FIREBASE_SERVICE_ACCOUNT is not set" });
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(raw);
  } catch {
    return reply(503, { error: "SERVER: FIREBASE_SERVICE_ACCOUNT is not valid JSON" });
  }

  try {
    const bearer = await accessToken(sa);
    const appUrl = Deno.env.get("APP_URL") ?? null;
    const dead: string[] = [];
    let sent = 0;
    await Promise.all(job.tokens.map(async ({ token }) => {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify(message(job, token, appUrl)),
      });
      if (res.ok) {
        sent++;
        return;
      }
      const body = await res.json().catch(() => ({}));
      const code = body?.error?.details?.find((d: { errorCode?: string }) => d.errorCode)?.errorCode;
      const badToken = code === "INVALID_ARGUMENT" && /registration token/i.test(body?.error?.message ?? "");
      if (res.status === 404 || code === "UNREGISTERED" || badToken) dead.push(token);
      else console.error(`FCM refused a message: ${res.status} ${JSON.stringify(body)}`);
    }));
    if (dead.length) await db.rpc("fn_push_drop_tokens", { p_secret: secret, p_tokens: dead });
    return reply(200, { sent, dropped: dead.length });
  } catch (e) {
    console.error(e);
    return reply(502, { error: "SERVER: Could not reach Firebase Cloud Messaging" });
  }
});
