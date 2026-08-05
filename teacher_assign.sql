-- ============================================================
--  담당강사 배정 규칙 + 학생용 담당강사 조회 (2026-08-05)
--  Supabase SQL Editor 에 전체 붙여넣고 RUN (여러 번 실행해도 안전)
--
--  1) set_teacher  — 담당강사 배정
--       원장·매니저 : 자유롭게
--       선생님(admin): 담당이 '미배정'인 학생을 '본인'에게만
--                      (남의 학생 가로채기·남에게 떠넘기기 불가)
--       그 외/비로그인: 거부
--  2) my_teacher   — 학생이 자기 담당강사 이름을 볼 수 있게
--       profiles 조회 정책상 학생은 남의 프로필을 못 읽으므로
--       security definer 함수로 '이름만' 돌려준다.
--
--  ⚠️ 중요: security definer 함수에서 my_role() 은 비로그인 시 NULL 이다.
--     `if my_role() not in (...)` 로 쓰면 NULL not in → NULL → IF가 거짓 →
--     검사를 그냥 통과해 버린다. 반드시 coalesce(my_role(),'') 로 쓸 것.
-- ============================================================

-- ── 1) 담당강사 배정 ─────────────────────────────────────────
create or replace function public.set_teacher(target uuid, tid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_role text := coalesce(public.my_role(), '');   -- 비로그인 = '' (NULL 아님)
  v_target_role text;
  v_cur_teacher uuid;
  v_tid_role    text;
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select role, teacher_id into v_target_role, v_cur_teacher
    from public.profiles where id = target;
  if v_target_role is null then
    raise exception '대상 회원을 찾을 수 없습니다.';
  end if;

  -- 담당강사로 지정하려는 사람은 반드시 선생님·원장이어야 한다
  if tid is not null then
    select role into v_tid_role from public.profiles where id = tid;
    if coalesce(v_tid_role,'') not in ('admin','master','manager') then
      raise exception '담당강사로 지정할 수 없는 계정입니다.';
    end if;
  end if;

  if v_role in ('master','manager') then
    update public.profiles set teacher_id = tid where id = target;
    return;
  end if;

  if v_role = 'admin' then
    if v_target_role <> 'student' then
      raise exception '학생만 담당 배정할 수 있습니다.';
    end if;
    if v_cur_teacher is not null then
      raise exception '이미 담당강사가 있는 학생입니다. 변경은 원장님께 요청해주세요.';
    end if;
    if tid is distinct from v_uid then
      raise exception '본인을 담당강사로 지정할 때만 가능합니다.';
    end if;
    update public.profiles set teacher_id = tid where id = target;
    return;
  end if;

  raise exception '담당강사를 지정할 권한이 없습니다.';
end;
$$;

revoke all on function public.set_teacher(uuid, uuid) from public, anon;
grant execute on function public.set_teacher(uuid, uuid) to authenticated;

-- ── 2) 학생이 보는 내 담당강사 ───────────────────────────────
create or replace function public.my_teacher()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_tid uuid;
  v_name text;
begin
  if v_uid is null then return jsonb_build_object('error','login'); end if;
  select teacher_id into v_tid from public.profiles where id = v_uid;
  if v_tid is null then return jsonb_build_object('assigned', false); end if;
  select name into v_name from public.profiles where id = v_tid;
  return jsonb_build_object('assigned', true, 'id', v_tid, 'name', coalesce(v_name,'-'));
end;
$$;

revoke all on function public.my_teacher() from public, anon;
grant execute on function public.my_teacher() to authenticated;

-- ── 3) 확인 ─────────────────────────────────────────────────
-- 두 함수 모두 'NULL 방어 됨' 이어야 정상
select proname as 함수,
       case when prosrc like '%coalesce(public.my_role()%' or proname = 'my_teacher'
            then 'OK'
            else '확인 필요' end as 상태,
       pg_get_function_identity_arguments(oid) as 인자
from pg_proc
where proname in ('set_teacher','my_teacher')
order by proname;
