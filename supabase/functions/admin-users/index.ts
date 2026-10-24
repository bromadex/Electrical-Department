// Account management for system administrators (API.md, "Users").
//
// The app cannot create sign-ins or set passwords itself: that needs the
// service role key, which must never leave the server. This function holds
// it, checks that the caller holds admin.users at all sites, and then does
// only one of two things:
//
//   { "action": "create", "email", "password", "full_name" }  -> { "id" }
//   { "action": "reset_password", "user_id", "password" }      -> { "ok": true }
//
// Profiles and roles are then set in the app through fn_set_user_profile and
// fn_set_user_roles, under the usual database rules. Errors use the same
// "CODE: message" form as the database functions, as { "error": "..." }.

import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const email = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

class Refusal extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function text(body: Record<string, unknown>, key: string): string {
  const v = body[key];
  return typeof v === "string" ? v.trim() : "";
}

// A project key: the legacy variable if present, else the default entry of
// the newer JSON variable (projects that turned legacy keys off).
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

function checkPassword(password: unknown): string {
  if (typeof password !== "string" || password.length < 8) {
    throw new Refusal(400, "INVALID", "The password needs at least 8 characters");
  }
  if (password.length > 72) {
    throw new Refusal(400, "INVALID", "The password can have at most 72 characters");
  }
  return password;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") {
    return reply(405, { error: "INVALID: Use POST" });
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = projectKey("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS");
  const serviceKey = projectKey("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS");

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization) {
      throw new Refusal(401, "NOT_ALLOWED", "Sign in first");
    }

    // Who is calling, judged by the database's own permission rules.
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: perms, error: permError } = await caller.rpc("my_permissions");
    if (permError) throw new Refusal(401, "NOT_ALLOWED", "Sign in first");
    const isAdmin = (perms as { code: string; site_id: string | null }[]).some(
      (p) => p.code === "admin.users" && p.site_id === null,
    );
    if (!isAdmin) {
      throw new Refusal(403, "NOT_ALLOWED", "Only a system administrator can manage accounts");
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      throw new Refusal(400, "INVALID", "The request is not valid JSON");
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    switch (body.action) {
      case "create": {
        const address = text(body, "email").toLowerCase();
        const fullName = text(body, "full_name");
        if (!email.test(address)) throw new Refusal(400, "INVALID", "Enter a valid email");
        if (fullName.length < 2 || fullName.length > 120) {
          throw new Refusal(400, "INVALID", "The name needs 2 to 120 characters");
        }
        const password = checkPassword(body.password);
        const { data, error } = await admin.auth.admin.createUser({
          email: address,
          password,
          email_confirm: true,
          user_metadata: { full_name: fullName },
        });
        if (error) {
          if (error.status === 422 || /already/i.test(error.message)) {
            throw new Refusal(409, "CONFLICT", "An account with this email already exists");
          }
          throw new Refusal(400, "INVALID", error.message);
        }
        return reply(200, { id: data.user.id });
      }

      case "reset_password": {
        const userId = text(body, "user_id");
        if (!uuid.test(userId)) throw new Refusal(400, "INVALID", "Unknown user");
        const password = checkPassword(body.password);
        const { error } = await admin.auth.admin.updateUserById(userId, { password });
        if (error) {
          if (error.status === 404) throw new Refusal(404, "NOT_FOUND", "User not found");
          throw new Refusal(400, "INVALID", error.message);
        }
        return reply(200, { ok: true });
      }

      default:
        throw new Refusal(400, "INVALID", "Unknown action");
    }
  } catch (e) {
    if (e instanceof Refusal) return reply(e.status, { error: `${e.code}: ${e.message}` });
    console.error(e);
    return reply(500, { error: "SERVER: The account service failed; try again" });
  }
});
