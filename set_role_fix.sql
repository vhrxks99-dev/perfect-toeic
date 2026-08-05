-- set_role 보안 재작성 (2026-08-05)
-- 문제: 로그아웃(anon) 상태로 set_role 을 호출해도 거부되지 않았다.
--       security definer 함수에서 my_role() 은 비로그인 시 NULL 이라
--       `if my_role() not in ('master')` 가 거짓이 되어 검사를 지나친다.
-- 조치: anon 실행권한 회수 + coalesce(my_role(),'') + 원장님 전용 +
--       마지막 원장님 강등 방지.

do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%role%'
  loop
    execute format('alter table public.profiles drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('student','admin','manager','master'));

drop function if exists public.set_role(uuid, text);

create function public.set_role(target uuid, new_role text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid  uuid := auth.uid();
  v_role text := coalesce(public.my_role(), '');
  v_target_role text;
  v_master_cnt  int;
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if v_role <> 'master' then
    raise exception '권한 변경은 원장님만 할 수 있습니다.';
  end if;
  if new_role not in ('student','admin','manager','master') then
    raise exception '알 수 없는 권한입니다: %', new_role;
  end if;

  select role into v_target_role from public.profiles where id = target;
  if v_target_role is null then
    raise exception '대상 회원을 찾을 수 없습니다.';
  end if;
  if v_target_role = new_role then
    return;
  end if;

  if v_target_role = 'master' and new_role <> 'master' then
    select count(*) into v_master_cnt from public.profiles where role = 'master';
    if v_master_cnt <= 1 then
      raise exception '원장님 계정이 하나뿐입니다. 다른 원장님을 먼저 지정한 뒤 바꿔주세요.';
    end if;
  end if;

  update public.profiles set role = new_role where id = target;
end;
$fn$;

revoke all on function public.set_role(uuid, text) from public, anon;
grant execute on function public.set_role(uuid, text) to authenticated;

select p.proname as 함수명,
       case when p.prosrc like '%coalesce(public.my_role()%' then '새버전' else '옛버전' end as 버전,
       has_function_privilege('anon', p.oid, 'execute') as anon실행가능
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'set_role';
