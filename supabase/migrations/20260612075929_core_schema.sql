-- BookDNA core schema (Phase 1 sync targets).
-- Mirrors the client Drift schema; every synced table carries:
--   updated_at  bigint      client LWW clock (epoch ms) — conflict resolution
--   deleted_at  timestamptz soft-delete tombstone
--   server_updated_at timestamptz  server watermark — pull cursor (trigger-set)

-- ───────────────────────── profiles ─────────────────────────

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_url text,
  is_public boolean not null default false,
  premium_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at bigint not null default 0,
  server_updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: read own or public" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id or is_public);

create policy "profiles: insert own" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "profiles: update own" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Auto-create a profile row for each new auth user.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', 'Reader'));
  return new;
end;
$$;

-- Trigger-only function: not a public API surface.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────── server watermark trigger ───────────────────

create function public.touch_server_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.server_updated_at = now();
  return new;
end;
$$;

revoke execute on function public.touch_server_updated_at() from public, anon, authenticated;

-- ───────────────────────── books ─────────────────────────

create table public.books (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  author text not null default '',
  genre text not null default 'Other',
  pages int not null default 0,
  year int,
  price numeric(10, 2),
  est_value numeric(10, 2),
  currency text not null default 'INR',
  status text not null default 'unread'
    check (status in ('reading', 'read', 'unread')),
  progress real not null default 0,
  current_page int not null default 0,
  rating smallint check (rating between 1 and 5),
  hue_shift smallint not null default 0,
  isbn text,
  publisher text,
  language text not null default 'English',
  description text,
  cover_url text,
  added_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at bigint not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- ───────────────────────── notes ─────────────────────────

create table public.notes (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  book_id uuid not null references public.books (id) on delete cascade,
  body text not null,
  page int,
  created_at timestamptz not null default now(),
  updated_at bigint not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- ──────────────────── reading_sessions ────────────────────

create table public.reading_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  book_id uuid not null references public.books (id) on delete cascade,
  session_date date not null,
  pages int not null,
  minutes int not null,
  created_at timestamptz not null default now(),
  updated_at bigint not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- ───────────────────────── lends ─────────────────────────

create table public.lends (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  book_id uuid references public.books (id) on delete set null,
  book_title text not null,
  to_name text not null,
  lent_on timestamptz not null,
  due_on timestamptz,
  returned_on timestamptz,
  updated_at bigint not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- ───────────────────────── goals ─────────────────────────

create table public.goals (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  year int not null,
  target int not null,
  updated_at bigint not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (user_id, year)
);

-- ─────────────── RLS + triggers + indexes (per table) ───────────────

do $$
declare
  t text;
begin
  foreach t in array array['books', 'notes', 'reading_sessions', 'lends', 'goals']
  loop
    execute format('alter table public.%I enable row level security', t);

    execute format($p$
      create policy "%1$s: select own" on public.%1$I
        for select to authenticated
        using ((select auth.uid()) = user_id)
    $p$, t);

    execute format($p$
      create policy "%1$s: insert own" on public.%1$I
        for insert to authenticated
        with check ((select auth.uid()) = user_id)
    $p$, t);

    execute format($p$
      create policy "%1$s: update own" on public.%1$I
        for update to authenticated
        using ((select auth.uid()) = user_id)
        with check ((select auth.uid()) = user_id)
    $p$, t);

    execute format($p$
      create policy "%1$s: delete own" on public.%1$I
        for delete to authenticated
        using ((select auth.uid()) = user_id)
    $p$, t);

    -- Pull cursor: every push bumps the server watermark.
    execute format($g$
      create trigger touch_%1$s_server_updated_at
        before insert or update on public.%1$I
        for each row execute function public.touch_server_updated_at()
    $g$, t);

    execute format(
      'create index %1$s_user_watermark_idx on public.%1$I (user_id, server_updated_at)',
      t);
  end loop;
end;
$$;

create trigger touch_profiles_server_updated_at
  before insert or update on public.profiles
  for each row execute function public.touch_server_updated_at();

create index books_user_status_idx on public.books (user_id, status);
create index books_user_isbn_idx on public.books (user_id, isbn);
create index reading_sessions_user_date_idx
  on public.reading_sessions (user_id, session_date desc);
create index notes_book_idx on public.notes (book_id);
