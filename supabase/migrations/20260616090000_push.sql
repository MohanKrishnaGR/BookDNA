-- BookDNA Phase 2 — server push via FCM.
-- Device token registry + a reassignment RPC + profile push flags, plus the
-- extensions the notify-sweep cron needs. Mirrors core_schema.sql conventions:
-- per-user "manage own" RLS (like books) and security-definer functions with
-- `set search_path = ''` (like handle_new_user).
--
-- Idempotent (applied via the Supabase Management API query endpoint, which does
-- not use the migrations ledger): safe to re-run.

-- ─────────────────────── extensions ───────────────────────
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ─────────────────────── device_tokens ───────────────────────

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null,
  platform text not null default 'fcm' check (platform in ('fcm', 'apns')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id);
-- The sweep and the reassignment delete both look tokens up by value.
create index if not exists device_tokens_token_idx
  on public.device_tokens (token);

alter table public.device_tokens enable row level security;

-- "Manage own" — mirrors the books policies. Drop-then-create keeps it re-runnable.
do $$
begin
  drop policy if exists "device_tokens: select own" on public.device_tokens;
  drop policy if exists "device_tokens: insert own" on public.device_tokens;
  drop policy if exists "device_tokens: update own" on public.device_tokens;
  drop policy if exists "device_tokens: delete own" on public.device_tokens;

  create policy "device_tokens: select own" on public.device_tokens
    for select to authenticated
    using ((select auth.uid()) = user_id);

  create policy "device_tokens: insert own" on public.device_tokens
    for insert to authenticated
    with check ((select auth.uid()) = user_id);

  create policy "device_tokens: update own" on public.device_tokens
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

  create policy "device_tokens: delete own" on public.device_tokens
    for delete to authenticated
    using ((select auth.uid()) = user_id);
end;
$$;

-- ─────────────────── register_device_token RPC ───────────────────
-- Reassigns a token to the calling user: a physical device maps to exactly one
-- FCM token, so claiming it for the current account (and dropping any other
-- account's stale row) prevents cross-account delivery after an account switch.
-- Security definer so it can delete rows owned by a *different* user; the only
-- row it writes is the caller's.
create or replace function public.register_device_token(
  p_token text,
  p_platform text default 'fcm'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or p_token is null or length(p_token) = 0 then
    return;
  end if;

  delete from public.device_tokens
    where token = p_token and user_id <> auth.uid();

  insert into public.device_tokens (user_id, token, platform)
  values (auth.uid(), p_token, coalesce(p_platform, 'fcm'))
  on conflict (user_id, token)
    do update set last_seen_at = now();
end;
$$;

-- Callable by signed-in clients only.
revoke execute on function public.register_device_token(text, text)
  from public, anon;
grant execute on function public.register_device_token(text, text)
  to authenticated;

-- ─────────────────── profiles: push flags ───────────────────
-- Server-side opt-out + a 7-day throttle stamp for re-engagement sends.
alter table public.profiles
  add column if not exists push_enabled boolean not null default true;
alter table public.profiles
  add column if not exists last_reengagement_at timestamptz;

-- ─────────────────────────── cron ───────────────────────────
-- The daily sweep is scheduled separately at deploy time (it embeds the
-- CRON_SECRET, which must NOT live in the repo). See the deploy step:
--   select cron.schedule('notify-sweep', '0 18 * * *', $job$
--     select net.http_post(
--       url := 'https://wrtrzmsvkdrvqhozxnsw.functions.supabase.co/notify-sweep',
--       headers := jsonb_build_object(
--         'X-Cron-Secret', '<CRON_SECRET>', 'Content-Type', 'application/json'),
--       body := '{}'::jsonb) $job$);
