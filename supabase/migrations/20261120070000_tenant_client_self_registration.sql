-- Tenant-scoped client self-registration and approval workflow.
-- This migration is committed to feature/wasla-v6; it is not applied to production here.

alter table public.profiles
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists company_name text;

create sequence if not exists public.client_legacy_id_seq
  as bigint
  start with 2000000000000
  increment by 1
  no minvalue
  no maxvalue
  cache 1;

create table if not exists public.organization_client_registration_links (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  token_hash text not null,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.organization_client_registration_links enable row level security;
revoke all on table public.organization_client_registration_links from public, anon, authenticated;

create or replace function public.create_client_registration_link()
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  org_id uuid;
  raw_token text;
begin
  if (select auth.uid()) is null
     or not private.has_organization_role(array['owner','admin']) then
    raise exception 'غير مصرح: يجب أن تكون مديراً في المؤسسة الحالية.';
  end if;

  org_id := (select private.current_organization_id());
  if org_id is null then
    raise exception 'تعذر تحديد المؤسسة الحالية.';
  end if;

  raw_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.organization_client_registration_links
    (organization_id, token_hash, is_active, created_by, created_at, updated_at)
  values
    (org_id,
     encode(extensions.digest(convert_to(raw_token, 'UTF8'), 'sha256'), 'hex'),
     true,
     (select auth.uid()),
     now(),
     now())
  on conflict (organization_id) do update
    set token_hash = excluded.token_hash,
        is_active = true,
        created_by = excluded.created_by,
        updated_at = now();

  return raw_token;
end;
$function$;

revoke all on function public.create_client_registration_link() from public, anon;
grant execute on function public.create_client_registration_link() to authenticated;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requested text;
  org_id uuid := null;
  registration_token text;
begin
  requested := case
    when new.raw_user_meta_data ->> 'requested_role' = 'employee' then 'employee'
    else 'user'
  end;

  -- Platform-created administrator invitations are assigned to their tenant by
  -- the trusted create-organization Edge Function immediately after invitation.
  if requested = 'user'
     and coalesce(new.raw_user_meta_data ->> 'requested_role', '') <> 'admin' then
    registration_token := nullif(new.raw_user_meta_data ->> 'client_registration_token', '');
    if registration_token is null then
      raise exception 'يجب استخدام رابط التسجيل الخاص بالشركة لإنشاء حساب عميل.';
    end if;

    select l.organization_id
      into org_id
    from public.organization_client_registration_links l
    join public.organizations o
      on o.id = l.organization_id
     and o.status = 'active'
    where l.is_active = true
      and l.token_hash = encode(
        extensions.digest(convert_to(registration_token, 'UTF8'), 'sha256'),
        'hex'
      )
    limit 1;

    if org_id is null then
      raise exception 'رابط تسجيل العميل غير صالح أو تم إيقافه. اطلب رابطاً جديداً من الشركة.';
    end if;
  end if;

  insert into public.profiles
    (id, full_name, email, phone, company_name, role, requested_role, approval_status, organization_id)
  values
    (
      new.id,
      left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 100),
      lower(new.email),
      left(coalesce(new.raw_user_meta_data ->> 'phone', ''), 40),
      left(coalesce(new.raw_user_meta_data ->> 'company_name', ''), 120),
      'pending',
      requested,
      'pending',
      org_id
    )
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        phone = excluded.phone,
        company_name = excluded.company_name,
        requested_role = excluded.requested_role,
        approval_status = 'pending',
        role = 'pending',
        organization_id = excluded.organization_id;

  return new;
end;
$function$;

create or replace function private.approve_signup(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_role text;
  org_id uuid;
  client_name text;
  client_email text;
  client_phone text;
  client_company text;
  client_id bigint;
  client_contact text;
  client_notes text;
  workspace_payload jsonb;
  client_record jsonb;
begin
  if (select auth.uid()) is null
     or not private.has_organization_role(array['owner','admin']) then
    raise exception 'غير مصرح: يجب أن تكون مديراً في المؤسسة الحالية.';
  end if;

  org_id := (select private.current_organization_id());

  select requested_role, full_name, email, phone, company_name
    into target_role, client_name, client_email, client_phone, client_company
  from public.profiles
  where id = p_user_id
    and organization_id = org_id
    and approval_status = 'pending'
    and role = 'pending'
  for update;

  if target_role is null then
    raise exception 'الحساب غير موجود في مؤسستك أو تمت معالجته مسبقاً.';
  end if;

  if target_role = 'user' then
    insert into public.workspace_data (id, organization_id, payload, updated_by)
    values (1, org_id, '{"clients":[],"finance":[],"contents":[],"projects":[]}'::jsonb, (select auth.uid()))
    on conflict (organization_id, id) do nothing;

    select payload into workspace_payload
    from public.workspace_data
    where organization_id = org_id and id = 1
    for update;

    if exists (
      select 1 from public.client_accounts
      where auth_user_id = p_user_id
    ) then
      raise exception 'هذا الحساب مرتبط بالفعل بملف عميل. راجع الربط الحالي قبل اعتماد طلب جديد.';
    end if;

    client_id := nextval('public.client_legacy_id_seq');
    client_contact := concat_ws(' · ',
      nullif(btrim(client_phone), ''),
      nullif(btrim(client_email), '')
    );
    client_notes := case
      when nullif(btrim(client_company), '') is null then 'تم إنشاء ملف العميل تلقائياً بعد موافقة طلب التسجيل.'
      else 'الشركة: ' || btrim(client_company) || E'\n' || 'تم إنشاء الملف تلقائياً بعد موافقة طلب التسجيل.'
    end;

    client_record := jsonb_build_object(
      'id', client_id,
      'name', coalesce(nullif(btrim(client_name), ''), 'عميل جديد'),
      'type', coalesce(nullif(btrim(client_company), ''), 'عميل'),
      'contact', coalesce(client_contact, ''),
      'status', 'عميل نشط',
      'notes', client_notes
    );

    update public.workspace_data
    set payload = jsonb_set(
          coalesce(workspace_payload, '{}'::jsonb),
          '{clients}',
          coalesce(workspace_payload -> 'clients', '[]'::jsonb) || jsonb_build_array(client_record),
          true
        ),
        updated_at = now(),
        updated_by = (select auth.uid())
    where organization_id = org_id and id = 1;

    insert into public.organization_members (organization_id, user_id, role, status)
    values (org_id, p_user_id, 'client', 'active')
    on conflict (organization_id, user_id) do update
      set role = 'client', status = 'active';

    insert into public.client_accounts (auth_user_id, legacy_client_id, organization_id)
    values (p_user_id, client_id, org_id);
  elsif target_role = 'employee' then
    -- Employee accounts retain the existing approval behavior; employee membership
    -- continues to be managed through the tenant's invite workflow.
    null;
  else
    raise exception 'نوع الحساب المطلوب غير مدعوم.';
  end if;

  update public.profiles
  set role = target_role,
      approval_status = 'approved',
      updated_at = now()
  where id = p_user_id
    and organization_id = org_id;
end;
$function$;

create or replace function private.reject_signup(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  org_id uuid;
begin
  if (select auth.uid()) is null
     or not private.has_organization_role(array['owner','admin']) then
    raise exception 'غير مصرح: يجب أن تكون مديراً في المؤسسة الحالية.';
  end if;

  org_id := (select private.current_organization_id());

  update public.profiles
  set approval_status = 'rejected',
      updated_at = now()
  where id = p_user_id
    and organization_id = org_id
    and approval_status = 'pending'
    and role = 'pending';

  if not found then
    raise exception 'الطلب غير موجود في مؤسستك أو تمت معالجته مسبقاً.';
  end if;
end;
$function$;

create or replace function public.reject_signup(p_user_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.reject_signup(p_user_id);
$function$;

revoke all on function public.reject_signup(uuid) from public, anon;
grant execute on function public.reject_signup(uuid) to authenticated;
