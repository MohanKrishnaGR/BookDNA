-- Phase 2: AI usage quotas and persisted shelf analyses.
-- Both tables are written ONLY by Edge Functions (service role);
-- clients get read-only access to their own rows.

create table public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  chat_messages int not null default 0,
  analyze_runs int not null default 0,
  tokens_in bigint not null default 0,
  tokens_out bigint not null default 0,
  primary key (user_id, day)
);

alter table public.ai_usage enable row level security;

create policy "ai_usage: select own" on public.ai_usage
  for select to authenticated
  using ((select auth.uid()) = user_id);
-- no insert/update/delete policies: service role only.

create table public.ai_analyses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  model text not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.ai_analyses enable row level security;

create policy "ai_analyses: select own" on public.ai_analyses
  for select to authenticated
  using ((select auth.uid()) = user_id);

create index ai_analyses_user_created_idx
  on public.ai_analyses (user_id, created_at desc);

-- Atomic quota bump, called by Edge Functions via service role.
-- Returns the post-increment counters so the caller can enforce limits
-- (check-then-increment without a read-modify-write race).
create function public.bump_ai_usage(
  p_user_id uuid,
  p_chat int default 0,
  p_analyze int default 0,
  p_tokens_in bigint default 0,
  p_tokens_out bigint default 0
)
returns table (chat_messages int, analyze_runs int)
language sql
set search_path = ''
as $$
  insert into public.ai_usage as u
    (user_id, day, chat_messages, analyze_runs, tokens_in, tokens_out)
  values
    (p_user_id, current_date, p_chat, p_analyze, p_tokens_in, p_tokens_out)
  on conflict (user_id, day) do update set
    chat_messages = u.chat_messages + excluded.chat_messages,
    analyze_runs  = u.analyze_runs + excluded.analyze_runs,
    tokens_in     = u.tokens_in + excluded.tokens_in,
    tokens_out    = u.tokens_out + excluded.tokens_out
  returning u.chat_messages, u.analyze_runs;
$$;

-- Service-role-only API surface.
revoke execute on function public.bump_ai_usage(uuid, int, int, bigint, bigint)
  from public, anon, authenticated;

-- Monthly analyze count helper (analyze quota is per month, not per day).
create function public.monthly_analyze_runs(p_user_id uuid)
returns int
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(analyze_runs), 0)::int
  from public.ai_usage
  where user_id = p_user_id
    and day >= date_trunc('month', current_date);
$$;

revoke execute on function public.monthly_analyze_runs(uuid)
  from public, anon, authenticated;
