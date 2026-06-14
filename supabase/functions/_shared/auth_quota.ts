import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2";

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

/// Resolves the calling user from the request's Authorization header.
export async function requireUser(
  admin: SupabaseClient,
  req: Request,
): Promise<User | null> {
  const auth = req.headers.get("Authorization") ?? "";
  const jwt = auth.replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data, error } = await admin.auth.getUser(jwt);
  if (error) return null;
  return data.user;
}

export async function isPremium(
  admin: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const { data } = await admin
    .from("profiles")
    .select("premium_until")
    .eq("id", userId)
    .maybeSingle();
  const until = data?.premium_until;
  return until != null && new Date(until) > new Date();
}

export const CHAT_DAILY_LIMIT = { free: 10, premium: 200 };
export const ANALYZE_MONTHLY_LIMIT = { free: 1, premium: 8 };

/// Atomically increments today's chat counter and returns whether the caller
/// is still within their daily limit (the increment that crosses the limit
/// is rejected).
export async function consumeChatQuota(
  admin: SupabaseClient,
  userId: string,
  premium: boolean,
): Promise<{ ok: boolean; used: number; limit: number }> {
  const limit = premium ? CHAT_DAILY_LIMIT.premium : CHAT_DAILY_LIMIT.free;
  const { data, error } = await admin.rpc("bump_ai_usage", {
    p_user_id: userId,
    p_chat: 1,
  });
  if (error) throw error;
  const used = data?.[0]?.chat_messages ?? 0;
  return { ok: used <= limit, used, limit };
}

export async function consumeAnalyzeQuota(
  admin: SupabaseClient,
  userId: string,
  premium: boolean,
): Promise<{ ok: boolean; used: number; limit: number }> {
  const limit = premium
    ? ANALYZE_MONTHLY_LIMIT.premium
    : ANALYZE_MONTHLY_LIMIT.free;
  const { data: runs, error } = await admin.rpc("monthly_analyze_runs", {
    p_user_id: userId,
  });
  if (error) throw error;
  if ((runs ?? 0) >= limit) return { ok: false, used: runs ?? 0, limit };
  const { error: bumpError } = await admin.rpc("bump_ai_usage", {
    p_user_id: userId,
    p_analyze: 1,
  });
  if (bumpError) throw bumpError;
  return { ok: true, used: (runs ?? 0) + 1, limit };
}

export async function logTokens(
  admin: SupabaseClient,
  userId: string,
  tokensIn: number,
  tokensOut: number,
): Promise<void> {
  // The query builder is a thenable without .catch — await and swallow here.
  const { error } = await admin.rpc("bump_ai_usage", {
    p_user_id: userId,
    p_tokens_in: tokensIn,
    p_tokens_out: tokensOut,
  });
  if (error) console.error("usage log failed", error);
}
