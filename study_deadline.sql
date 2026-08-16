-- 주말 스터디 규칙 2가지 추가 (2026-08-16 원장 지시)
--
-- 원장 지시 그대로
--  "참석불참도 전날 밤 10시까지로 마감하도록 하고 스터디 당일에는 참불 변경 불가능하도록 바꿔줘"
--  "웹페이지 스터디 2명이 참석하면 그날 스터디는 안 하는 거로 넘어가야 해. 사람이 없어서 불가능해.
--   회차는 그대로 매기면 되고"
--  "참석인원이 2명뿐이라 스터디가 안 열리면 웹페이지에서 학생들이 자발적으로 확인해야 해.
--   그러니 스터디 참여인원 부족으로 안 열릴 경우 따로 표시 웹페이지에 해줘야 해"
--  마감 대상은 원장 확정 = **학생만**. 선생님·원장은 당일에도 대신 고칠 수 있다('가' 선택).
--
-- 🚨 인원 부족으로 안 여는 날을 study_off 에 넣으면 안 된다.
--    회차는 study_off 를 뺀 날만 세기 때문에(studyRound / STUDY_ANCHOR) 넣는 순간 회차가 밀린다.
--    원장 지시가 "회차는 그대로"이므로 표시용 상태로만 계산한다.
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) 마감 시각 계산 — 스터디 전날 22:00 (서울)
create or replace function public.study_deadline(p_day date)
returns timestamptz
language sql
immutable
as $$
  select ((p_day - 1)::timestamp + time '22:00') at time zone 'Asia/Seoul';
$$;

comment on function public.study_deadline(date) is
  '주말 스터디 참·불 마감 = 전날 밤 10시(서울). 학생에게만 적용된다(원장 지시 2026-08-16).';

-- 2) 학생이 마감 뒤에 참·불을 못 바꾸게 막는다
--    화면에서만 막으면 브라우저로 그냥 뚫린다 — 표에 직접 쓰는 경로라 트리거로 막아야 한다.
--    선생님·매니저·원장은 그대로 통과(당일 착오를 고칠 사람이 있어야 한다).
create or replace function public.guard_study_signup_deadline()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(public.my_role(), '');
  v_day  date := coalesce(new.study_date, old.study_date);
begin
  if v_role in ('admin', 'manager', 'master') then
    return coalesce(new, old);
  end if;
  if now() > public.study_deadline(v_day) then
    raise exception '참석 여부는 스터디 전날 밤 10시까지만 바꿀 수 있어요. 담당 선생님께 말씀해 주세요.';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_study_signup_deadline on public.study_signups;
create trigger trg_study_signup_deadline
  before insert or update or delete on public.study_signups
  for each row execute function public.guard_study_signup_deadline();

-- 3) 화면이 쓸 값을 study_weekend 에 추가한다
--    deadline : 마감 시각
--    locked   : 마감이 지났나 (학생 버튼 잠금용)
--    closed   : 마감이 지났는데 참석이 2명 이하 → 그날 안 연다
--    ⚠️ 기존에 있던 값(day/off/reason/rooms/n/no/todo/mine)은 그대로 둔다. 화면이 다 쓰고 있다.
create or replace function public.study_weekend(p_date date)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with d as (
    -- 월요일을 주의 시작으로 본다. 토 = +5, 일 = +6
    select (p_date - ((extract(isodow from p_date)::int) - 1))::date as mon
  ),
  days as (
    select (mon + 5)::date as day from d
    union all
    select (mon + 6)::date from d
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'day',  day,
           'off',  exists(select 1 from public.study_off o where o.off_date = day),
           'reason', (select o.reason from public.study_off o where o.off_date = day),
           'rooms', coalesce((select jsonb_agg(r.room_id order by r.room_id)
                              from public.study_rooms r where r.study_date = day), '[]'::jsonb),
           -- n = 참석, no = 불참, todo = 아직 안 찍은 사람(자격자 중)
           'n',    (select count(*) from public.study_signups s where s.study_date = day and s.going),
           'no',   (select count(*) from public.study_signups s where s.study_date = day and not s.going),
           'todo', greatest(0,
                     (select count(*) from public.profiles p where p.role='student' and p.study
                        and coalesce(p.status,'active') <> 'ended')
                   - (select count(*) from public.study_signups s where s.study_date = day)),
           -- mine: 'yes' / 'no' / null(아직 안 찍음)
           'mine', (select case when s.going then 'yes' else 'no' end
                      from public.study_signups s
                     where s.study_date = day and s.student_id = auth.uid()),
           -- 아래 셋이 2026-08-16 에 새로 들어간 것
           'deadline', public.study_deadline(day),
           'locked',   now() > public.study_deadline(day),
           'closed',   now() > public.study_deadline(day)
                       and (select count(*) from public.study_signups s
                             where s.study_date = day and s.going) <= 2
         ) order by day), '[]'::jsonb)
  from days;
$$;
revoke all on function public.study_weekend(date) from public, anon;
grant execute on function public.study_weekend(date) to authenticated;

-- 4) 확인 — 다가오는 토·일의 마감·인원 상태
select x->>'day' as 날짜,
       (x->>'n')::int as 참석,
       (x->>'no')::int as 불참,
       (x->>'todo')::int as 미정,
       (x->>'off')::boolean as 쉬는날,
       (x->>'locked')::boolean as 마감됨,
       (x->>'closed')::boolean as 인원부족,
       to_char((x->>'deadline')::timestamptz at time zone 'Asia/Seoul','MM-DD HH24:MI') as 마감시각
  from jsonb_array_elements(public.study_weekend(current_date)) x
union all
select x->>'day', (x->>'n')::int, (x->>'no')::int, (x->>'todo')::int,
       (x->>'off')::boolean, (x->>'locked')::boolean, (x->>'closed')::boolean,
       to_char((x->>'deadline')::timestamptz at time zone 'Asia/Seoul','MM-DD HH24:MI')
  from jsonb_array_elements(public.study_weekend(current_date + 7)) x
order by 1;
