-- Handl — initial schema
-- Run this in the Supabase SQL editor (or `supabase db push`) on a fresh project.

-- ─── Tables ────────────────────────────────────────────────────────────────

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- user_id references profiles (not auth.users) so PostgREST can embed
-- display names: select("user_id, profile:profiles(display_name)")
create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  category text not null default 'other',
  phone text not null default '',
  whatsapp boolean not null default true,
  notes text not null default '',
  address text not null default '',
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ─── Triggers ──────────────────────────────────────────────────────────────

-- Create a profile row for every new auth user, taking the display name from
-- the sign-up metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger services_set_updated_at
  before update on public.services
  for each row execute function public.set_updated_at();

-- ─── Helper functions (SECURITY DEFINER, bypass RLS to avoid recursion) ────

create or replace function public.is_member(hid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.household_members
    where household_id = hid and user_id = auth.uid()
  );
$$;

create or replace function public.shares_household_with(target uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1
    from public.household_members mine
    join public.household_members theirs
      on theirs.household_id = mine.household_id
    where mine.user_id = auth.uid() and theirs.user_id = target
  );
$$;

-- ─── Row Level Security ────────────────────────────────────────────────────

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.services enable row level security;

-- profiles: self + household co-members can read; only self can update.
-- Inserts happen only through the definer trigger.
create policy "profiles visible to self and co-members"
on public.profiles for select to authenticated
using (id = auth.uid() or public.shares_household_with(id));

create policy "update own profile"
on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());

-- households: members read and rename. Creation only via RPC; no deletes in v1.
create policy "members view their households"
on public.households for select to authenticated
using (public.is_member(id));

create policy "members rename their households"
on public.households for update to authenticated
using (public.is_member(id)) with check (public.is_member(id));

-- household_members: members see membership; anyone can remove themselves.
-- Inserts only via RPCs.
create policy "members view membership"
on public.household_members for select to authenticated
using (public.is_member(household_id));

create policy "leave household"
on public.household_members for delete to authenticated
using (user_id = auth.uid());

-- services: full CRUD for household members.
create policy "members view services"
on public.services for select to authenticated
using (public.is_member(household_id));

create policy "members add services"
on public.services for insert to authenticated
with check (public.is_member(household_id));

create policy "members edit services"
on public.services for update to authenticated
using (public.is_member(household_id)) with check (public.is_member(household_id));

create policy "members delete services"
on public.services for delete to authenticated
using (public.is_member(household_id));

-- ─── RPCs (the app's household bootstrap API) ──────────────────────────────

-- 6 chars from an alphabet without 0/O/1/I; retries until unique.
create or replace function public.generate_invite_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.households where invite_code = code);
  end loop;
  return code;
end;
$$;

create or replace function public.create_household(p_name text)
returns setof public.households
language plpgsql
security definer set search_path = public
as $$
declare
  new_household public.households;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  -- Retry loop absorbs the (vanishingly rare) TOCTOU race where two
  -- concurrent creates draw the same code between the uniqueness check
  -- inside generate_invite_code() and this insert.
  loop
    begin
      insert into public.households (name, invite_code, created_by)
      values (coalesce(nullif(trim(p_name), ''), 'Home'), public.generate_invite_code(), auth.uid())
      returning * into new_household;
      exit;
    exception when unique_violation then
      null; -- draw a new code and try again
    end;
  end loop;

  insert into public.household_members (household_id, user_id)
  values (new_household.id, auth.uid());

  return next new_household;
end;
$$;

create or replace function public.join_household(p_code text)
returns setof public.households
language plpgsql
security definer set search_path = public
as $$
declare
  target public.households;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  select * into target from public.households
  where upper(invite_code) = upper(trim(p_code));
  if not found then
    return; -- empty set: the app shows "no household with that code"
  end if;
  insert into public.household_members (household_id, user_id)
  values (target.id, auth.uid())
  on conflict do nothing;
  return next target;
end;
$$;

-- The household the app should show (first joined). Empty set = none.
create or replace function public.my_household()
returns setof public.households
language sql
security definer set search_path = public
stable
as $$
  select h.*
  from public.households h
  join public.household_members m on m.household_id = h.id
  where m.user_id = auth.uid()
  order by m.joined_at
  limit 1;
$$;

-- ─── Grants ────────────────────────────────────────────────────────────────

-- Supabase's default privileges auto-grant EXECUTE on every public function
-- to anon AND authenticated; revoke from all three and stop future functions
-- from being auto-exposed, then re-grant only the intended surface.
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated;

-- Policy helpers run as the querying role, so authenticated needs these two.
grant execute on function public.is_member(uuid) to authenticated;
grant execute on function public.shares_household_with(uuid) to authenticated;
grant execute on function public.create_household(text) to authenticated;
grant execute on function public.join_household(text) to authenticated;
grant execute on function public.my_household() to authenticated;

-- Column-level write grants (RLS is row-level only). Without these, any
-- member could PATCH invite_code/created_by on households, or spoof
-- created_by on services.
revoke update on table public.households from authenticated;
grant update (name) on table public.households to authenticated;

revoke insert, update on table public.services from authenticated;
grant insert (household_id, name, category, phone, whatsapp, notes, address),
      update (name, category, phone, whatsapp, notes, address)
  on table public.services to authenticated;
