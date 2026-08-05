-- =====================================================================
--  학생별 수강 상태(수강 중/수강 종료) + 수업 형태(대면/비대면)
--  Supabase > SQL Editor 에 이 파일 전체를 붙여넣고 [Run] 하세요.
--  (여러 번 실행해도 안전합니다)
--
--  왜 필요한가:
--   1. 관리 페이지의 "🔔 확인이 필요해요" 알림은 최근에 끝난 수업의 학생 중
--      다음 수업이 안 잡힌 학생을 띄운다. 그런데 수강을 마친 학생은 다음 수업을
--      잡을 필요가 없으므로 계속 뜨면 방해만 된다.
--      → 회원 관리에서 학생을 '수강 종료'로 표시하면 알림에서 빠진다.
--   2. 학생마다 대면 수업인지 비대면 수업인지 한눈에 구분이 필요하다.
--   3. 학생별 현재 점수 / 목표 점수 / 목표 기간을 담당 선생님이 적어 둔다.
--   4. 선생님별 평가 지표(출석률·재등록률·퇴원률)를 뽑으려면
--      "왜 그만뒀는지"(수료인지 중도 퇴원인지)와 상담 기록이 있어야 한다.
-- =====================================================================

-- ─────────────────────────────────────────────
-- 1) profiles 에 칸 추가
--    status      : 수강 상태 (기본값 = 수강 중)
--    lesson_mode : 수업 형태 (비워두면 '미지정')
--    goal_period : 목표 기간 (자유 입력 — "2026년 10월까지", "3개월" 등)
--    end_reason  : 종료 사유 (graduated=수료 / quit=중도 퇴원 / etc=기타)
--    ended_at    : 종료로 바꾼 시점 (월별 퇴원률 집계용)
--    ※ 현재 점수(current_score) / 목표 점수(goal_score)는 이미 있는 칸이다.
-- ─────────────────────────────────────────────
alter table public.profiles
  add column if not exists status text not null default 'active';

alter table public.profiles
  drop constraint if exists profiles_status_chk;
alter table public.profiles
  add constraint profiles_status_chk check (status in ('active','ended'));

alter table public.profiles
  add column if not exists lesson_mode text;

alter table public.profiles
  drop constraint if exists profiles_lesson_mode_chk;
alter table public.profiles
  add constraint profiles_lesson_mode_chk check (lesson_mode in ('offline','online'));

alter table public.profiles
  add column if not exists goal_period text;

alter table public.profiles
  add column if not exists end_reason text;

alter table public.profiles
  drop constraint if exists profiles_end_reason_chk;
alter table public.profiles
  add constraint profiles_end_reason_chk check (end_reason in ('graduated','quit','etc'));

alter table public.profiles
  add column if not exists ended_at timestamptz;

-- ─────────────────────────────────────────────
-- 2) 상태 변경 함수
--    회원 프로필의 일반 수정 권한은 원장님(master)에게만 있다.
--    수강 종료 표시는 실제로 수업을 하는 선생님(admin)도 해야 하므로
--    이 함수로만 열어 준다. (이름·연락처 등 다른 칸은 못 건드림)
--    '수강 중'으로 되돌리면 종료 사유·종료 시점은 지워진다.
-- ─────────────────────────────────────────────
drop function if exists public.set_student_status(uuid, text);

create or replace function public.set_student_status(target uuid, new_status text, reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v text := nullif(btrim(coalesce(reason,'')), '');
begin
  if public.my_role() not in ('admin','master') then
    raise exception '수강 상태는 선생님·원장님만 변경할 수 있습니다.';
  end if;
  if new_status not in ('active','ended') then
    raise exception '알 수 없는 상태입니다: %', new_status;
  end if;
  if v is not null and v not in ('graduated','quit','etc') then
    raise exception '알 수 없는 종료 사유입니다: %', reason;
  end if;

  if new_status = 'ended' then
    update public.profiles set
      status     = 'ended',
      end_reason = coalesce(v, 'etc'),
      ended_at   = coalesce(ended_at, now())
    where id = target;
  else
    update public.profiles set
      status     = 'active',
      end_reason = null,
      ended_at   = null
    where id = target;
  end if;
end;
$$;

revoke all on function public.set_student_status(uuid, text, text) from public;
grant execute on function public.set_student_status(uuid, text, text) to authenticated;

-- ─────────────────────────────────────────────
-- 3) 수업 형태 변경 함수 (같은 이유로 선생님도 바꿀 수 있게)
--    빈 값(null)은 '미지정'을 뜻한다.
-- ─────────────────────────────────────────────
create or replace function public.set_lesson_mode(target uuid, new_mode text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v text := nullif(btrim(coalesce(new_mode,'')), '');
begin
  if public.my_role() not in ('admin','master') then
    raise exception '수업 형태는 선생님·원장님만 변경할 수 있습니다.';
  end if;
  if v is not null and v not in ('offline','online') then
    raise exception '알 수 없는 수업 형태입니다: %', new_mode;
  end if;
  update public.profiles set lesson_mode = v where id = target;
end;
$$;

revoke all on function public.set_lesson_mode(uuid, text) from public;
grant execute on function public.set_lesson_mode(uuid, text) to authenticated;

-- ─────────────────────────────────────────────
-- 4) 점수·목표 변경 함수 (담당 선생님이 직접 적을 수 있게)
--    빈 칸으로 두면 지워진다.
-- ─────────────────────────────────────────────
create or replace function public.set_student_goal(target uuid, cur text, goal text, period text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.my_role() not in ('admin','master') then
    raise exception '점수·목표는 선생님·원장님만 변경할 수 있습니다.';
  end if;
  update public.profiles set
    current_score = nullif(btrim(coalesce(cur,'')), ''),
    goal_score    = nullif(btrim(coalesce(goal,'')), ''),
    goal_period   = nullif(btrim(coalesce(period,'')), '')
  where id = target;
end;
$$;

revoke all on function public.set_student_goal(uuid, text, text, text) from public;
grant execute on function public.set_student_goal(uuid, text, text, text) to authenticated;

-- ─────────────────────────────────────────────
-- 5) 상담 장부
--    "상담받은 사람 중 몇 명이 실제로 등록했나"(등록 전환율)를 보려면
--    상담 자체를 남겨 둬야 한다. 회원가입 전이라 profiles 에는 없는 사람이다.
--    result: pending=결과 대기 / registered=등록함 / lost=등록 안 함
-- ─────────────────────────────────────────────
create table if not exists public.consults (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  consulted_on  date not null default current_date,
  name          text not null,
  phone         text,
  channel       text,                       -- 유입 경로 (네이버/지인소개/방문 등)
  teacher_id    uuid,                       -- 상담한 선생님
  teacher_name  text,
  memo          text,
  result        text not null default 'pending',
  decided_on    date,                       -- 등록/포기가 확정된 날
  student_id    uuid                        -- 등록했다면 연결된 회원
);

alter table public.consults
  drop constraint if exists consults_result_chk;
alter table public.consults
  add constraint consults_result_chk check (result in ('pending','registered','lost'));

create index if not exists idx_consults_date on public.consults(consulted_on);

alter table public.consults enable row level security;
drop policy if exists consults_all on public.consults;
create policy consults_all on public.consults for all to authenticated
  using (public.my_role() in ('master','manager','admin'))
  with check (public.my_role() in ('master','manager','admin'));
grant select, insert, update, delete on public.consults to authenticated;

-- ─────────────────────────────────────────────
-- 6) 확인용 — 실행 후 이 줄만 따로 돌려 보면 학생별 상태가 보입니다.
-- ─────────────────────────────────────────────
-- select name, status, end_reason, lesson_mode, current_score, goal_score, goal_period
--   from public.profiles where role = 'student' order by name;
