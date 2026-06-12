-- Phase 3: social (challenges, follows, leaderboard) and premium (trial).

-- ───────────────────────── challenges ─────────────────────────
-- Global catalogue, service-role managed. Progress is computed client-side
-- from the member's own reading data (streaks, finishes, genres).

create table public.challenges (
  id text primary key, -- slug
  icon text not null,
  title text not null,
  description text not null,
  kind text not null check (kind in ('streak', 'books_month', 'genres', 'club')),
  target int not null,
  hue_shift smallint not null default 0,
  sort int not null default 0
);

alter table public.challenges enable row level security;

create policy "challenges: readable" on public.challenges
  for select to authenticated
  using (true);
-- writes: service role only.

insert into public.challenges (id, icon, title, description, kind, target, hue_shift, sort) values
  ('streak-100', 'local_fire_department', '100-Day Streak', 'Read every day for 100 days', 'streak', 100, 30, 1),
  ('books-5-month', 'menu_book', '5 Books This Month', 'Finish 5 books this month', 'books_month', 5, 0, 2),
  ('genre-explorer', 'explore', 'Genre Explorer', 'Finish books in 3 different genres', 'genres', 3, 150, 3),
  ('club-sprint', 'groups', 'Book Club Sprint', 'Finish 1 book with your circle', 'club', 1, 210, 4);

create table public.challenge_members (
  challenge_id text not null references public.challenges (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

alter table public.challenge_members enable row level security;

create policy "challenge_members: select own" on public.challenge_members
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "challenge_members: join" on public.challenge_members
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "challenge_members: leave" on public.challenge_members
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ───────────────────────── follows ─────────────────────────

create table public.follows (
  user_id uuid not null references auth.users (id) on delete cascade,
  friend_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'accepted' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

alter table public.follows enable row level security;

create policy "follows: select own edges" on public.follows
  for select to authenticated
  using ((select auth.uid()) = user_id or (select auth.uid()) = friend_id);

create policy "follows: create own" on public.follows
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "follows: remove own" on public.follows
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ─────────────────────── leaderboard RPC ───────────────────────
-- Pages read this week (Monday start) for the caller and accepted friends.
-- SECURITY DEFINER on purpose: friends' raw reading_sessions stay private;
-- only the weekly aggregate for the caller's own friend set is exposed.
-- The auth.uid() scoping inside the body is the access control.

create function public.weekly_leaderboard()
returns table (
  user_id uuid,
  display_name text,
  pages bigint,
  is_me boolean
)
language sql
security definer
set search_path = ''
as $$
  with circle as (
    select auth.uid() as uid
    union
    select friend_id from public.follows
      where user_id = auth.uid() and status = 'accepted'
    union
    select user_id from public.follows
      where friend_id = auth.uid() and status = 'accepted'
  )
  select
    p.id as user_id,
    coalesce(p.display_name, 'Reader') as display_name,
    coalesce(sum(s.pages), 0)::bigint as pages,
    p.id = auth.uid() as is_me
  from circle c
  join public.profiles p on p.id = c.uid
  left join public.reading_sessions s
    on s.user_id = c.uid
    and s.deleted_at is null
    and s.session_date >= date_trunc('week', current_date)
  group by p.id, p.display_name
  order by pages desc;
$$;

-- Callable by signed-in users only (auth.uid() inside scopes the data).
revoke execute on function public.weekly_leaderboard() from public, anon;
grant execute on function public.weekly_leaderboard() to authenticated;

-- ───────────────────────── premium trial ─────────────────────────

alter table public.profiles
  add column trial_started_at timestamptz;
