-- =====================================================================
--  강의장 건물 구분 + 학생 주차 필요 표시
--  Supabase > SQL Editor 에 이 파일 전체를 붙여넣고 [Run] 하세요.
--  (여러 번 실행해도 안전합니다)
--
--  왜 필요한가:
--   학원 A방·B방은 붙어 있고, 완토 스터디룸은 걸어서 5분 거리의 다른 건물이다.
--   그리고 주차가 필요한 학생은 별관으로 가야 한다.
--   지금은 구글 캘린더에서 온 수업에 강의장이 아예 없어서, 웹에서 배정할 때
--   이 두 가지를 컴퓨터가 알아야 자동 배정과 경고가 가능하다.
-- =====================================================================

-- ─────────────────────────────────────────────
-- 1) 강의장에 '건물' 칸 추가
-- ─────────────────────────────────────────────
alter table public.rooms
  add column if not exists building text not null default '본원';

-- 지금 있는 강의장 3개를 건물로 나눠 둔다.
-- (이름에 '스터디'가 들어간 곳 = 완토 스터디룸 = 별관)
update public.rooms set building = '별관' where name like '%스터디%';
update public.rooms set building = '본원' where name not like '%스터디%';

-- ─────────────────────────────────────────────
-- 2) 학생에게 '주차 필요' 표시 칸 추가
-- ─────────────────────────────────────────────
alter table public.profiles
  add column if not exists parking boolean not null default false;

-- ─────────────────────────────────────────────
-- 3) 주차 표시 변경 함수
--    회원 프로필의 일반 수정은 원장님만 가능하므로,
--    선생님도 담당 학생의 주차 여부를 바꿀 수 있게 이 함수로만 연다.
--    ※ coalesce 필수 — 비로그인 상태면 my_role()이 NULL이고
--      'NULL not in (...)' 은 참도 거짓도 아니라서 검사를 그냥 통과해 버린다.
-- ─────────────────────────────────────────────
create or replace function public.set_student_parking(target uuid, on_off boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(public.my_role(),'') not in ('admin','master') then
    raise exception '주차 표시는 선생님·원장님만 변경할 수 있습니다.';
  end if;
  update public.profiles set parking = coalesce(on_off, false) where id = target;
end;
$$;

revoke all on function public.set_student_parking(uuid, boolean) from public;
grant execute on function public.set_student_parking(uuid, boolean) to authenticated;

-- ─────────────────────────────────────────────
-- 4) 강사에게 '별관 양보' 표시 칸 추가
--    김태완·이창희 원장님처럼, 시간이 겹쳐 본원 방이 모자랄 때
--    먼저 별관으로 옮겨 주는 강사를 표시해 둔다.
--    (강사에게만 의미가 있고 학생에게는 쓰지 않는다)
-- ─────────────────────────────────────────────
alter table public.profiles
  add column if not exists room_yield boolean not null default false;

create or replace function public.set_room_yield(target uuid, on_off boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(public.my_role(),'') not in ('admin','master') then
    raise exception '강의장 양보 표시는 선생님·원장님만 변경할 수 있습니다.';
  end if;
  update public.profiles set room_yield = coalesce(on_off, false) where id = target;
end;
$$;

revoke all on function public.set_room_yield(uuid, boolean) from public;
grant execute on function public.set_room_yield(uuid, boolean) to authenticated;

-- ─────────────────────────────────────────────
-- 5) 확인용
-- ─────────────────────────────────────────────
select name, building, capacity from public.rooms order by building desc, name;
