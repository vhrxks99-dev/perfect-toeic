-- 회원 탈퇴 (2026-08-05)
-- 지금까지 관리 페이지의 '삭제'는 profiles 행만 지웠다. 로그인 계정 자체는
-- 남아 있어서 그 사람이 다시 로그인할 수 있었다. 이제 계정까지 지운다.
--
-- 지워지는 것 : 로그인 계정 + 회원 프로필(+ 강사 배분율, 알림 확인 기록)
-- 남는 것     : 정산·수업 기록. payments/schedules 는 회원 연결만 끊기고
--               student_name 이 글자로 저장돼 있어 장부가 보존된다.
--               출석·숙제·진단·상담 기록도 그대로 남는다.
-- 여러 번 실행해도 안전합니다.

drop function if exists public.delete_my_account();

create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid  uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;

  select role into v_role from public.profiles where id = v_uid;
  if v_role is null then raise exception '회원 정보를 찾을 수 없습니다.'; end if;

  -- 강사·원장 계정은 정산 배분과 얽혀 있어 본인이 바로 지우지 못하게 한다.
  if v_role <> 'student' then
    raise exception '강사·원장 계정은 원장님께 요청해주세요.';
  end if;

  delete from auth.users where id = v_uid;
end;
$fn$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

drop function if exists public.delete_member(uuid);

create function public.delete_member(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_role text := coalesce(public.my_role(), '');
  v_target_role text;
  v_master_cnt int;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if v_role <> 'master' then raise exception '회원 탈퇴 처리는 원장님만 할 수 있습니다.'; end if;
  if target = auth.uid() then raise exception '본인 계정은 여기서 탈퇴시킬 수 없습니다.'; end if;

  select role into v_target_role from public.profiles where id = target;
  if v_target_role is null then raise exception '대상 회원을 찾을 수 없습니다.'; end if;

  if v_target_role = 'master' then
    select count(*) into v_master_cnt from public.profiles where role = 'master';
    if v_master_cnt <= 1 then
      raise exception '원장님 계정이 하나뿐이라 지울 수 없습니다.';
    end if;
  end if;

  delete from auth.users where id = target;
end;
$fn$;

revoke all on function public.delete_member(uuid) from public, anon;
grant execute on function public.delete_member(uuid) to authenticated;

select 'delete_my_account anon 실행' as 항목,
       case when has_function_privilege('anon','public.delete_my_account()','execute')
            then '가능 (문제)' else '차단됨 OK' end as 결과
union all
select 'delete_member anon 실행',
       case when has_function_privilege('anon','public.delete_member(uuid)','execute')
            then '가능 (문제)' else '차단됨 OK' end
union all
select 'payments 학생연결 (SET NULL 이어야 장부 보존)',
       coalesce((select rc.delete_rule
                 from information_schema.referential_constraints rc
                 join information_schema.key_column_usage k
                   on k.constraint_name = rc.constraint_name
                 where k.table_schema='public' and k.table_name='payments'
                   and k.column_name='student_id' limit 1), '연결 없음');
