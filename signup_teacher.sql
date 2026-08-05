-- 회원가입 시 담당강사 '희망' 선택 (2026-08-05)
-- 정책: 학생이 고른 것은 희망일 뿐이고, 실제 담당강사는 원장님이 확정한다.
--       담당강사는 정산 배분의 기준이라 학생이 직접 정하게 두지 않는다.
-- 필요한 이유
--  1) 가입 화면은 비로그인 상태다. profiles 조회 정책상 비로그인은
--     강사 목록을 읽을 수 없으므로 '이름만' 돌려주는 함수가 필요하다.
--  2) 희망 강사는 전용 함수로만 기록한다. 남의 값을 건드리는 통로가 되면 안 된다.
-- 여러 번 실행해도 안전합니다.

alter table public.profiles
  add column if not exists wish_teacher_id uuid references auth.users(id) on delete set null;

drop function if exists public.teacher_list();

create function public.teacher_list()
returns table(id uuid, name text)
language sql
security definer
stable
set search_path = public
as $fn$
  select p.id, p.name
  from public.profiles p
  where p.role in ('admin','master')
  order by p.name
$fn$;

revoke all on function public.teacher_list() from public;
grant execute on function public.teacher_list() to anon, authenticated;

drop function if exists public.claim_teacher(uuid);
drop function if exists public.wish_teacher(uuid);

create function public.wish_teacher(tid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_cur  uuid;
  v_tid_role text;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;

  select role, teacher_id into v_role, v_cur from public.profiles where id = v_uid;
  if v_role is null then raise exception '프로필이 아직 만들어지지 않았습니다.'; end if;
  if v_role <> 'student' then raise exception '학생만 희망 강사를 고를 수 있습니다.'; end if;
  if v_cur is not null then
    raise exception '이미 담당강사가 정해져 있습니다. 변경은 학원에 문의해주세요.';
  end if;

  if tid is null then
    update public.profiles set wish_teacher_id = null where id = v_uid;
    return;
  end if;

  select role into v_tid_role from public.profiles where id = tid;
  if coalesce(v_tid_role,'') not in ('admin','master') then
    raise exception '선택할 수 없는 강사입니다.';
  end if;

  update public.profiles set wish_teacher_id = tid where id = v_uid;
end;
$fn$;

revoke all on function public.wish_teacher(uuid) from public, anon;
grant execute on function public.wish_teacher(uuid) to authenticated;

select 'wish_teacher_id 칸' as 항목,
       case when exists (select 1 from information_schema.columns
                         where table_schema='public' and table_name='profiles' and column_name='wish_teacher_id')
            then 'OK' else '없음 (문제)' end as 결과
union all
select 'teacher_list 강사 수', count(*)::text from public.teacher_list()
union all
select 'wish_teacher anon 실행',
       case when has_function_privilege('anon','public.wish_teacher(uuid)','execute')
            then '가능 (문제)' else '차단됨 OK' end
union all
select 'teacher_list anon 실행',
       case when has_function_privilege('anon','public.teacher_list()','execute')
            then '가능 OK (가입 화면에 필요)' else '차단됨 (문제)' end;
