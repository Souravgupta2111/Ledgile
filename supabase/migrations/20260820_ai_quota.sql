-- Per-account AI quota. Edge Function uses the service role; clients cannot write this table.
create table if not exists public.ai_quota (
  user_id uuid primary key references auth.users (id) on delete cascade,
  free_used integer not null default 0,
  voice_month text,
  voice_used integer not null default 0,
  camera_month text,
  camera_used integer not null default 0,
  is_pro boolean not null default false,
  pro_expires_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.ai_quota enable row level security;
