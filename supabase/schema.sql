-- M0: sync round-trip probe table. Full mirrored schema (spec §9) lands in M1.
create table if not exists sync_probe (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  device_id text not null,
  created_at timestamptz not null default now()
);

-- Single-user project: RLS on, permissive policy for authenticated + anon key.
-- Tighten to authenticated-only once auth is wired in M1.
alter table sync_probe enable row level security;
create policy "personal_all" on sync_probe for all using (true) with check (true);
