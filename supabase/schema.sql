create type public.user_role as enum ('patient', 'caregiver');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.user_role not null default 'patient',
  allergies text[] not null default '{}',
  created_at timestamptz not null default now()
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 8)),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table public.medications (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  strength text,
  dosage text not null,
  frequency text not null,
  frequency_interval integer not null default 1,
  frequency_unit text not null default 'day',
  supply_count integer,
  reminder_hour integer not null default 8,
  reminder_minute integer not null default 0,
  dose_history jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.dose_events (
  id uuid primary key default gen_random_uuid(),
  medication_id uuid not null references public.medications(id) on delete cascade,
  patient_id uuid not null references public.profiles(id) on delete cascade,
  taken_at timestamptz not null default now(),
  dose_index integer not null
);

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.medications enable row level security;
alter table public.dose_events enable row level security;

create or replace function public.is_group_member(target_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_members
    where group_id = target_group and user_id = auth.uid()
  );
$$;

create or replace function public.is_caregiver()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'caregiver'
  );
$$;

create policy "users read own profile" on public.profiles for select using (id = auth.uid());
create policy "users update own profile" on public.profiles for update using (id = auth.uid());
create policy "users insert own profile" on public.profiles for insert with check (id = auth.uid());

create policy "members read groups" on public.groups for select using (is_group_member(id) or created_by = auth.uid());
create policy "caregivers create groups" on public.groups for insert with check (created_by = auth.uid() and is_caregiver());
create policy "creators update groups" on public.groups for update using (created_by = auth.uid());
create policy "members read memberships" on public.group_members for select using (user_id = auth.uid() or is_group_member(group_id));
create policy "users join with invite flow" on public.group_members for insert with check (user_id = auth.uid());

create policy "patients and caregivers read medications" on public.medications for select using (
  patient_id = auth.uid() or exists (
    select 1 from public.group_members mine
    join public.group_members patient_member on patient_member.group_id = mine.group_id
    where mine.user_id = auth.uid() and patient_member.user_id = medications.patient_id
  )
);
create policy "patients create medications" on public.medications for insert with check (patient_id = auth.uid() or is_caregiver());
create policy "owners update medications" on public.medications for update using (patient_id = auth.uid() or is_caregiver());
create policy "owners delete medications" on public.medications for delete using (patient_id = auth.uid() or is_caregiver());

create policy "members read dose events" on public.dose_events for select using (patient_id = auth.uid() or is_caregiver());
create policy "patients create dose events" on public.dose_events for insert with check (patient_id = auth.uid());
