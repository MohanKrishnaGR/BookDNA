// Premium entitlement endpoint.
//   {action: "trial"}    → grants the one-time 7-day free trial
//   {action: "status"}   → returns the caller's current entitlement
//   {action: "play"}     → Play Billing receipt verification (501 until a
//                          Play Console service account is configured)
// profiles.premium_until is writable only by this function (service role).

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { adminClient, requireUser } from "../_shared/auth_quota.ts";

const TRIAL_DAYS = 7;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const admin = adminClient();
    const user = await requireUser(admin, req);
    if (!user) return jsonResponse({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const action = body?.action as string | undefined;

    const { data: profile, error } = await admin
      .from("profiles")
      .select("premium_until, trial_started_at")
      .eq("id", user.id)
      .maybeSingle();
    if (error) throw error;

    switch (action) {
      case "status": {
        return jsonResponse({
          premium_until: profile?.premium_until,
          trial_used: profile?.trial_started_at != null,
        });
      }

      case "trial": {
        if (profile?.trial_started_at != null) {
          return jsonResponse(
            {
              error: "trial_used",
              message: "Your free trial has already been used.",
              premium_until: profile?.premium_until,
            },
            409,
          );
        }
        const until = new Date(
          Date.now() + TRIAL_DAYS * 24 * 60 * 60 * 1000,
        ).toISOString();
        const { error: updateError } = await admin
          .from("profiles")
          .update({ trial_started_at: new Date().toISOString(), premium_until: until })
          .eq("id", user.id);
        if (updateError) throw updateError;
        return jsonResponse({ premium_until: until, trial_used: true });
      }

      case "play": {
        // Requires a Google Play Developer API service account + published
        // products (bookdna_monthly_199 / bookdna_yearly_1499). Until then,
        // be explicit rather than pretending to verify.
        return jsonResponse(
          {
            error: "not_configured",
            message:
              "Store purchases aren't enabled yet — the 7-day free trial is available.",
          },
          501,
        );
      }

      default:
        return jsonResponse({ error: "invalid_action" }, 400);
    }
  } catch (e) {
    console.error(e);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});
