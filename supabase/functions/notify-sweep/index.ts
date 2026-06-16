// notify-sweep — server-decided push notifications (Phase 2).
//
// Invoked by the pg_cron job (daily, via net.http_post). Computes who should be
// nudged while the app is closed and sends FCM v1 messages:
//   • re-engagement — readers with a device token who haven't logged a session
//     in 7 days (throttled to once per 7 days via profiles.last_reengagement_at)
//   • Wrapped ready  — on the 1st of the month (or body {"kind":"wrapped"}),
//     every opted-in reader with a token
//
// Self-contained (inline CORS + admin client + FCM helper) so it deploys as a
// single file via the Management API, matching the isbn-lookup precedent.
// Deployed with verify_jwt=false; auth is the shared X-Cron-Secret header.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const DAY_MS = 24 * 60 * 60 * 1000;

interface PushTarget {
  userId: string;
  tokens: { id: string; token: string }[];
}

const COPY = {
  reengagement: {
    title: "Your books miss you 📚",
    body: "Pick up where you left off — even a few pages tonight keeps the streak alive.",
    route: "/home",
  },
  wrapped: {
    title: "Your reading Wrapped is ready ✨",
    body: "See the month in books — your stats, themes and highlights.",
    route: "/wrapped",
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  // Shared-secret guard. Enforced only once CRON_SECRET is configured so the
  // endpoint is harmless (and testable) before the console step.
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && req.headers.get("X-Cron-Secret") !== cronSecret) {
    return json({ error: "unauthorized" }, 401);
  }

  // No FCM credentials yet → nothing can be sent. Stay a no-op so the cron is
  // harmless before FCM_SERVICE_ACCOUNT is set (mirrors ai-chat demo mode).
  const fcmRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!fcmRaw) return json({ skipped: true, reason: "no_fcm_secret" });

  try {
    const body = await req.json().catch(() => ({} as { kind?: string }));
    const now = new Date();
    const wrappedDue = body?.kind === "wrapped" || now.getUTCDate() === 1;

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // Every registered device, grouped by user.
    const { data: tokenRows, error: tokenErr } = await admin
      .from("device_tokens")
      .select("id, user_id, token");
    if (tokenErr) throw tokenErr;

    const byUser = new Map<string, PushTarget>();
    for (const r of tokenRows ?? []) {
      const t = byUser.get(r.user_id) ??
        { userId: r.user_id, tokens: [] };
      t.tokens.push({ id: r.id, token: r.token });
      byUser.set(r.user_id, t);
    }
    const userIds = [...byUser.keys()];
    if (userIds.length === 0) {
      return json({ reengagement: 0, wrapped: 0, pruned: 0 });
    }

    // Opted-in profiles only.
    const { data: profiles, error: profErr } = await admin
      .from("profiles")
      .select("id, push_enabled, last_reengagement_at")
      .in("id", userIds)
      .eq("push_enabled", true);
    if (profErr) throw profErr;

    const optedIn = new Set((profiles ?? []).map((p) => p.id));

    // ── re-engagement cohort ──────────────────────────────────────
    const cutoff = new Date(now.getTime() - 7 * DAY_MS);
    const cutoffDate = cutoff.toISOString().slice(0, 10); // YYYY-MM-DD

    const candidates = (profiles ?? []).filter((p) =>
      p.last_reengagement_at == null ||
      new Date(p.last_reengagement_at) < cutoff
    ).map((p) => p.id);

    let lapsed: string[] = [];
    if (candidates.length > 0) {
      // Users with a recent session are "active" — exclude them.
      const { data: recent, error: sessErr } = await admin
        .from("reading_sessions")
        .select("user_id")
        .gte("session_date", cutoffDate)
        .in("user_id", candidates);
      if (sessErr) throw sessErr;
      const active = new Set((recent ?? []).map((r) => r.user_id));
      lapsed = candidates.filter((id) => !active.has(id));
    }

    const token = await fcmAccessToken(fcmRaw);
    const projectId = JSON.parse(fcmRaw).project_id as string;
    let pruned = 0;

    const sendTo = async (target: PushTarget, copy: typeof COPY.reengagement) => {
      let delivered = false;
      for (const tok of target.tokens) {
        const ok = await sendFcm(token, projectId, tok.token, copy);
        if (ok === "ok") delivered = true;
        else if (ok === "stale") {
          await admin.from("device_tokens").delete().eq("id", tok.id);
          pruned++;
        }
      }
      return delivered;
    };

    // ── send re-engagement ──
    let reengagement = 0;
    for (const userId of lapsed) {
      const target = byUser.get(userId);
      if (!target) continue;
      if (await sendTo(target, COPY.reengagement)) {
        reengagement++;
        await admin
          .from("profiles")
          .update({ last_reengagement_at: now.toISOString() })
          .eq("id", userId);
      }
    }

    // ── send Wrapped (independent of lapsed state) ──
    let wrapped = 0;
    if (wrappedDue) {
      for (const userId of optedIn) {
        const target = byUser.get(userId);
        if (!target) continue;
        if (await sendTo(target, COPY.wrapped)) wrapped++;
      }
    }

    return json({ reengagement, wrapped, pruned });
  } catch (e) {
    console.error("notify-sweep", e);
    return json({ error: "internal_error" }, 500);
  }
});

// ─────────────────────── FCM v1 helpers ───────────────────────

/// Exchanges the service-account for a short-lived OAuth access token scoped to
/// Cloud Messaging. Built once per invocation.
async function fcmAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson) as {
    client_email: string;
    private_key: string;
    token_uri?: string;
  };
  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const iat = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat,
    exp: iat + 3600,
  };
  const header = { alg: "RS256", typ: "JWT" };
  const signingInput = `${b64url(JSON.stringify(header))}.${
    b64url(JSON.stringify(claim))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${b64urlBytes(new Uint8Array(sig))}`;

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`oauth token exchange failed: ${res.status}`);
  }
  const j = await res.json();
  return j.access_token as string;
}

/// Returns "ok" on delivery, "stale" if the token is unregistered (prune it),
/// "fail" for transient/other errors (left for the next sweep).
async function sendFcm(
  accessToken: string,
  projectId: string,
  token: string,
  copy: { title: string; body: string; route: string },
): Promise<"ok" | "stale" | "fail"> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: copy.title, body: copy.body },
          data: { route: copy.route },
          android: { priority: "high" },
        },
      }),
    },
  );
  if (res.ok) return "ok";
  const detail = await res.text().catch(() => "");
  if (res.status === 404 || detail.includes("UNREGISTERED")) return "stale";
  console.error("fcm send failed", res.status, detail);
  return "fail";
}

function b64url(s: string): string {
  return b64urlBytes(new TextEncoder().encode(s));
}

function b64urlBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const der = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
  return der;
}
