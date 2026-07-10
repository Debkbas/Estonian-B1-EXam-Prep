-- Rada sync schema (spec §9). Single-user project.
-- M0: sync_probe · M1: progress_entries + activity_log

create table if not exists sync_probe (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  device_id text not null,
  created_at timestamptz not null default now()
);

create table if not exists progress_entries (
  id text primary key,
  target_type text not null,
  target_id text not null,
  status text not null default 'todo',
  completed_at timestamptz,
  self_score int,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  device_id text not null default 'unknown',
  deleted boolean not null default false
);

create table if not exists activity_log (
  id text primary key,
  date timestamptz not null,
  minutes int not null,
  kind text not null,
  detail_json text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  device_id text not null default 'unknown',
  deleted boolean not null default false
);

-- RLS: permissive for now (personal project, anon key kept private).
-- Tighten to authenticated-only when auth is wired.
alter table sync_probe enable row level security;
alter table progress_entries enable row level security;
alter table activity_log enable row level security;

do $$ begin
  create policy "personal_all" on sync_probe for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "personal_all" on progress_entries for all using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "personal_all" on activity_log for all using (true) with check (true);
exception when duplicate_object then null; end $$;
