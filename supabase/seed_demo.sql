-- ───────────────────────────────────────────────────────────────────────────
-- BookDNA demo account seed.
--
-- Creates a fully-populated demo user (mohankrishnagr08@gmail.com) with every
-- piece of data the app surfaces: a 20-book library, ~100 reading sessions
-- (a live 23-day streak + 18-week heatmap history), notes, lends, a yearly
-- goal, a cached AI shelf analysis (drives the knowledge graph), two joined
-- challenges, and an active premium trial.
--
-- Idempotent: re-running refreshes all data and keeps streaks/heatmaps
-- relative to "today". Safe to apply to local (`supabase db reset` picks up
-- seed.sql automatically if you symlink/rename) or a cloud project.
--
-- Login:  mohankrishnagr08@gmail.com  /  bookdna-demo-2026
--
-- Book id scheme: '00000<hex(1000+n)>-0000-4000-8000-000000000000' so every
-- book has a distinct 8-char prefix (the AI analysis references those prefixes
-- in theme_edges, and the client graph resolves them by prefix match).
-- ───────────────────────────────────────────────────────────────────────────

-- 1. Auth user + email identity (password hashed with pgcrypto).
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000',
  'd3709999-0000-4000-8000-000000000001',
  'authenticated', 'authenticated',
  'mohankrishnagr08@gmail.com',
  extensions.crypt('bookdna-demo-2026', extensions.gen_salt('bf')),
  now(), now() - interval '400 days', now(),
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Mohan Krishna G R"}',
  false
)
on conflict (id) do nothing;

-- GoTrue's Go scanner 500s on login if these token columns are NULL rather
-- than empty strings (a well-known SQL-seeded-user gotcha) — blank them.
update auth.users set
  confirmation_token = '', recovery_token = '', email_change = '',
  email_change_token_new = '', email_change_token_current = '',
  phone_change = '', phone_change_token = '', reauthentication_token = ''
where id = 'd3709999-0000-4000-8000-000000000001';

insert into auth.identities (
  provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) values (
  'd3709999-0000-4000-8000-000000000001',
  'd3709999-0000-4000-8000-000000000001',
  '{"sub":"d3709999-0000-4000-8000-000000000001","email":"mohankrishnagr08@gmail.com","email_verified":true}',
  'email', now(), now(), now()
)
on conflict (provider, provider_id) do nothing;

-- 2. Wipe any prior demo data (keep the auth user + profile row).
delete from public.ai_analyses     where user_id = 'd3709999-0000-4000-8000-000000000001';
delete from public.challenge_members where user_id = 'd3709999-0000-4000-8000-000000000001';
delete from public.reading_sessions where user_id = 'd3709999-0000-4000-8000-000000000001';
delete from public.notes           where user_id = 'd3709999-0000-4000-8000-000000000001';
delete from public.lends           where user_id = 'd3709999-0000-4000-8000-000000000001';
delete from public.goals           where user_id = 'd3709999-0000-4000-8000-000000000001';
delete from public.books           where user_id = 'd3709999-0000-4000-8000-000000000001';

-- 3. Profile: public, on an active 7-day premium trial.
update public.profiles set
  display_name = 'Mohan Krishna G R',
  is_public = true,
  trial_started_at = now() - interval '1 day',
  premium_until = now() + interval '6 days'
where id = 'd3709999-0000-4000-8000-000000000001';

-- 4. Library (20 books).
with seed(n, title, author, genre, pages, yr, price, status, progress,
          current_page, rating, hue, isbn, publisher, descr, added_year, finished_days) as (
  values
  (1,'Designing Data-Intensive Applications','Martin Kleppmann','Technology',616,2017,3200.0,'reading',0.62,382,5,0,'9781449373320','O''Reilly Media','The big ideas behind reliable, scalable and maintainable systems.',2023,null::int),
  (2,'Superintelligence','Nick Bostrom','AI & Science',352,2014,1450.0,'read',1.0,352,4,150,'9780199678112','Oxford University Press','Paths, dangers and strategies for machine intelligence beyond our own.',2024,90),
  (3,'Zero to One','Peter Thiel','Business',224,2014,850.0,'read',1.0,224,5,60,'9780804139298','Crown Business','Notes on startups, and building companies that create new things.',2020,700),
  (4,'Deep Learning','Ian Goodfellow','AI & Science',800,2016,4100.0,'unread',0.0,0,null,150,'9780262035613','MIT Press','The foundational mathematics and methods of modern deep learning.',2024,null),
  (5,'Thinking, Fast and Slow','Daniel Kahneman','Psychology',499,2011,999.0,'read',1.0,499,5,210,'9780374533557','Farrar, Straus and Giroux','How two systems of thought shape judgment and decisions.',2021,420),
  (6,'The Hard Thing About Hard Things','Ben Horowitz','Business',304,2014,899.0,'read',1.0,304,4,60,'9780062273208','Harper Business','Building a business when there are no easy answers.',2022,130),
  (7,'Sapiens','Yuval Noah Harari','History',498,2011,599.0,'read',1.0,498,5,270,'9780062316097','Harper','A brief history of humankind, from forager bands to data religions.',2019,60),
  (8,'Deep Work','Cal Newport','Self Help',296,2016,650.0,'read',1.0,296,4,320,'9781455586691','Grand Central','Rules for focused success in a distracted world.',2019,45),
  (9,'The Lean Startup','Eric Ries','Business',336,2011,799.0,'read',1.0,336,4,60,'9780307887894','Crown Business','How relentless experimentation builds successful businesses.',2020,540),
  (10,'Clean Code','Robert C. Martin','Technology',464,2008,2800.0,'read',1.0,464,4,0,'9780132350884','Prentice Hall','A handbook of agile software craftsmanship.',2021,365),
  (11,'Life 3.0','Max Tegmark','AI & Science',384,2017,1100.0,'unread',0.0,0,null,150,'9781101946596','Knopf','Being human in the age of artificial intelligence.',2025,null),
  (12,'Atomic Habits','James Clear','Self Help',320,2018,699.0,'read',1.0,320,5,320,'9780735211292','Avery','Tiny changes, remarkable results.',2022,25),
  (13,'The Pragmatic Programmer','David Thomas','Technology',352,2019,3000.0,'reading',0.18,63,null,0,'9780135957059','Addison-Wesley','Your journey to mastery — 20th anniversary edition.',2026,null),
  (14,'AI 2041','Kai-Fu Lee','AI & Science',480,2021,1250.0,'unread',0.0,0,null,150,'9780593238295','Currency','Ten visions for our future with artificial intelligence.',2026,null),
  (15,'The Psychology of Money','Morgan Housel','Psychology',256,2020,450.0,'read',1.0,256,5,210,'9780857197689','Harriman House','Timeless lessons on wealth, greed and happiness.',2023,15),
  (16,'Hooked','Nir Eyal','Business',256,2014,750.0,'unread',0.0,0,null,60,'9781591847786','Portfolio','How to build habit-forming products.',2025,null),
  (17,'The Innovators','Walter Isaacson','Biography',560,2014,950.0,'unread',0.0,0,null,30,'9781476708690','Simon & Schuster','How hackers, geniuses and geeks created the digital revolution.',2024,null),
  (18,'Steve Jobs','Walter Isaacson','Biography',656,2011,899.0,'read',1.0,656,4,30,'9781451648539','Simon & Schuster','The exclusive biography.',2021,600),
  (19,'Probabilistic Machine Learning','Kevin P. Murphy','AI & Science',864,2022,5200.0,'unread',0.0,0,null,150,'9780262046824','MIT Press','The modern statistical view of machine learning.',2026,null),
  (20,'Show Your Work!','Austin Kleon','Self Help',224,2014,550.0,'read',1.0,224,3,320,'9780761178972','Workman','10 ways to share your creativity and get discovered.',2023,200)
)
insert into public.books (
  id, user_id, title, author, genre, pages, year, price, est_value, currency,
  status, progress, current_page, rating, hue_shift, isbn, publisher, language,
  description, cover_url, added_at, started_at, finished_at, updated_at
)
select
  ('00000' || to_hex(1000 + n) || '-0000-4000-8000-000000000000')::uuid,
  'd3709999-0000-4000-8000-000000000001',
  title, author, genre, pages, yr, price, round(price * 1.3, 2), 'INR',
  status, progress, current_page, rating, hue, isbn, publisher, 'English',
  descr, null,
  make_timestamptz(added_year, (n * 5) % 12 + 1, (n * 7) % 27 + 1, 9, 0, 0),
  case when status = 'unread' then null
       else now() - ((coalesce(finished_days, 30) + 40) || ' days')::interval end,
  case when finished_days is null then null
       else now() - (finished_days || ' days')::interval end,
  (extract(epoch from now()) * 1000)::bigint
from seed;

-- 5. Reading sessions: a live 23-day streak + 18-week heatmap history,
--    attributed to the two currently-reading books (1 and 13).
insert into public.reading_sessions (
  id, user_id, book_id, session_date, pages, minutes, created_at, updated_at
)
select
  ('00000000-0000-4000-9000-' || lpad(to_hex(g), 12, '0'))::uuid,
  'd3709999-0000-4000-8000-000000000001',
  case when g % 2 = 0
       then '000003e9-0000-4000-8000-000000000000'::uuid   -- book 1
       else '000003f5-0000-4000-8000-000000000000'::uuid   -- book 13
  end,
  (current_date - g)::date,
  pages, pages * 2,
  now() - (g || ' days')::interval,
  (extract(epoch from now()) * 1000)::bigint
from (
  select g,
    case when g <= 22
         then 10 + (g * 3) % 18
         else 6 + lvl * 7 + g % 5 end as pages
  from generate_series(0, 125) as g
  cross join lateral (
    select case
      when g <= 22 then 1                                   -- streak: always
      else (
        select case
          when v > 0.55 then 4 when v > 0.25 then 3
          when v > -0.1 then 2 when v > -0.5 then 1 else 0 end
        from (select sin((g / 7) * 3.7 + (g % 7) * 5.3)
                   * cos((g / 7) * 1.3 - (g % 7) * 2.1) as v) x
      )
    end as lvl
  ) l
  where g <= 22 or lvl > 0                                  -- skip empty days
) s;

-- 6. Notes on the active book.
insert into public.notes (id, user_id, book_id, body, page, created_at, updated_at)
values
  ('00000000-0000-4000-a000-000000000001','d3709999-0000-4000-8000-000000000001',
   '000003e9-0000-4000-8000-000000000000',
   'The hardest part of distributed systems isn''t the algorithms — it''s reasoning about partial failure.',
   287, now() - interval '3 days', (extract(epoch from now()) * 1000)::bigint),
  ('00000000-0000-4000-a000-000000000002','d3709999-0000-4000-8000-000000000001',
   '000003e9-0000-4000-8000-000000000000',
   '"Data outlives code." Design schemas for evolution.',
   132, now() - interval '18 days', (extract(epoch from now()) * 1000)::bigint);

-- 7. Lends (one overdue, one current).
insert into public.lends (id, user_id, book_id, book_title, to_name, lent_on, due_on, updated_at)
values
  ('00000000-0000-4000-b000-000000000001','d3709999-0000-4000-8000-000000000001',
   '000003eb-0000-4000-8000-000000000000','Zero to One','Arjun K',
   now() - interval '30 days', now() - interval '9 days',
   (extract(epoch from now()) * 1000)::bigint),
  ('00000000-0000-4000-b000-000000000002','d3709999-0000-4000-8000-000000000001',
   '000003f4-0000-4000-8000-000000000000','Atomic Habits','Sneha R',
   now() - interval '14 days', now() + interval '7 days',
   (extract(epoch from now()) * 1000)::bigint);

-- 8. Reading goal for the current year.
insert into public.goals (id, user_id, year, target, updated_at)
values ('00000000-0000-4000-c000-000000000001','d3709999-0000-4000-8000-000000000001',
        extract(year from current_date)::int, 12, (extract(epoch from now()) * 1000)::bigint);

-- 9. Cached AI shelf analysis (powers the AI screen + knowledge-graph bridges).
insert into public.ai_analyses (user_id, model, result)
values (
  'd3709999-0000-4000-8000-000000000001',
  'demo',
  '{
    "demo": true,
    "reading_profile": "A systems-and-AI shelf of 20 books moving from software craft toward applied machine intelligence, with a healthy unread frontier of future-facing titles.",
    "personality": {"archetype": "The Builder", "traits": ["Deep-diver", "Serial finisher", "Future-focused"]},
    "blind_spots": [
      {"area": "Robotics hardware", "why": "Your 2026 trajectory points here — you own zero books on it."},
      {"area": "Ethics of automation", "why": "You read what AI can do, not what it should."},
      {"area": "Fiction", "why": "Almost none on the shelf — narrative thinking is a muscle too."}
    ],
    "read_next": [
      {"book_id": "000003f6", "reason": "AI 2041 bridges your finished Bostrom/Tegmark cluster with applied futures."},
      {"book_id": "000003f3", "reason": "Life 3.0 continues your AI & Science momentum and is a quick read."},
      {"book_id": "000003fb", "reason": "Probabilistic ML deepens the technical core you have been building."}
    ],
    "theme_edges": [
      ["000003e9","000003ec"], ["000003e9","000003f5"], ["000003ea","000003f3"],
      ["000003ea","000003f6"], ["000003f3","000003f6"], ["000003ec","000003fb"],
      ["000003ef","000003ea"], ["000003eb","000003f1"], ["000003ed","000003f7"],
      ["000003f0","000003f4"], ["000003f9","000003fa"], ["000003ee","000003f8"]
    ]
  }'::jsonb
);

-- 10. Joined challenges.
insert into public.challenge_members (challenge_id, user_id)
values
  ('streak-100','d3709999-0000-4000-8000-000000000001'),
  ('books-5-month','d3709999-0000-4000-8000-000000000001')
on conflict do nothing;
