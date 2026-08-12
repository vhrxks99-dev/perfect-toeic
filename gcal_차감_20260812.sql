-- 구글 캘린더 수업도 횟수를 차감한다 (2026-08-12 원장 지시)
--
-- 원장 지시 그대로
--  · "지금 수업 횟수 잡혀있는 애들도 이제 횟수 차감해주면 돼. 구글캘린더 포함이야."
--  · "지금 이 순간 이후로 처리해주면 돼."
--  · "8월12일 오후 2시 이전은 구글캘린더 무시하면 돼. 통통통에서 횟수 차감된 상태로 들어온 횟수야."
--  → 기준 시각 = 2026-08-12 14:00 (KST). 그 전에 시작한 구글 수업은 안 센다.
--
-- 왜 이름 맞추기가 필요한가
--  구글 캘린더에서 들어온 수업은 student_id 가 비어 있고 이름만 있다(1,956건 전부).
--  회원과 연결이 안 되면 누구 횟수를 깎을지 알 수 없어 차감이 통째로 안 걸린다.
--  그래서 이름으로 회원을 찾아 student_id 를 채워 준다.
--
-- 이름 맞추는 규칙 (원장 확인 = 뒷 2글자도 맞춤)
--  · 괄호와 공백을 뗀다: "김서영 (비대면)" -> "김서영"
--  · 전체 이름이 딱 한 명과 맞으면 그 사람
--  · 아니면 뒷 2글자가 딱 한 명과 맞으면 그 사람: "보은" -> 임보은, "상현" -> 박상현
--  · 후보가 둘 이상이면(동명이인) 연결하지 않는다 — 엉뚱한 학생 횟수를 깎느니 안 깎는 게 낫다
--  · 수강 종료한 학생은 후보에서 뺀다
--  ⚠️ 그래서 '예린'처럼 두 명(방예린·조예린)이 걸리는 이름은 차감이 안 된다.
--     캘린더에 성까지 적어 주시면 자동으로 걸린다.
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) 이름으로 회원 찾기
create or replace function public.match_student_by_name(p_name text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  with n as (
    select trim(regexp_replace(
             regexp_replace(coalesce(p_name,''), '\(.*\)', '', 'g'),
             '[[:space:]]', '', 'g')) as q
  ),
  p as (
    select id,
           regexp_replace(name, '[[:space:]]', '', 'g')          as norm,
           right(regexp_replace(name, '[[:space:]]', '', 'g'), 2) as tail2
      from public.profiles
     where role = 'student' and coalesce(status,'') <> 'ended'
  )
  select case
    when (select q from n) = '' then null
    when (select count(*) from p, n where p.norm  = n.q) = 1
      then (select p.id     from p, n where p.norm  = n.q)
    when (select count(*) from p, n where p.tail2 = n.q) = 1
      then (select p.id     from p, n where p.tail2 = n.q)
  end;
$$;

revoke all on function public.match_student_by_name(text) from public, anon;
grant execute on function public.match_student_by_name(text) to authenticated;

-- 2) 앞으로 들어오는 구글 수업은 자동으로 회원과 연결한다
--    기준 시각 이전 행은 건드리지 않는다(통통통에서 이미 차감된 몫이라 또 깎으면 안 된다).
create or replace function public.gcal_fill_student()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.source,'web') = 'gcal'
     and new.student_id is null
     and new.starts_at > timestamptz '2026-08-12 14:00:00+09' then
    new.student_id := public.match_student_by_name(new.student_name);
  end if;
  return new;
end;
$$;

-- 이름이 'f' 라서 trg_room_conflict('r') 보다 먼저 돈다 — 방 검사가 학생을 알고 돌게 된다.
drop trigger if exists trg_gcal_fill_student on public.schedules;
create trigger trg_gcal_fill_student
  before insert or update on public.schedules
  for each row execute function public.gcal_fill_student();

-- 3) 이미 들어와 있는 '기준 시각 이후' 구글 수업을 회원과 연결한다
update public.schedules s
   set student_id = public.match_student_by_name(s.student_name)
 where coalesce(s.source,'web') = 'gcal'
   and s.student_id is null
   and s.starts_at > timestamptz '2026-08-12 14:00:00+09'
   and public.match_student_by_name(s.student_name) is not null;

-- 4) 남은 횟수 계산에 구글 수업을 넣는다
--    빼는 것: 승인 대기(pending)·휴강(canceled) / 사전 OT / 기준 시각 이전의 구글 수업
--    사전 OT 는 is_ot 칸이 정답이지만 구글에는 제목에 (신규) 를 붙여 넣고 계셔서 그것도 OT 로 본다.
--    ⚠️ 화면 짝은 index.html 의 countsAsUsed() 다. 한쪽만 고치면 숫자가 어긋난다.
create or replace function public.sessions_left(p_student uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select sum(sessions) from public.payments
                    where student_id = p_student and sessions is not null), 0)
       + coalesce((select sum(delta) from public.session_adjustments
                    where student_id = p_student), 0)
       - coalesce((select count(*) from public.schedules
                    where student_id = p_student
                      and coalesce(status,'confirmed') in ('confirmed','noshow')
                      and coalesce(is_ot,false) = false
                      and coalesce(student_name,'') || ' ' || coalesce(subject,'')
                          !~ '\(\s*신규\s*\)'
                      and (coalesce(source,'web') <> 'gcal'
                           or starts_at > timestamptz '2026-08-12 14:00:00+09')), 0);
$$;

revoke all on function public.sessions_left(uuid) from public, anon;
grant execute on function public.sessions_left(uuid) to authenticated;

-- 확인용
select
  (select count(*) from public.schedules
    where coalesce(source,'web')='gcal' and student_id is not null)         as 연결된구글수업,
  (select count(*) from public.schedules
    where coalesce(source,'web')='gcal' and student_id is null
      and starts_at > timestamptz '2026-08-12 14:00:00+09')                 as 연결못한구글수업,
  (select count(*) from public.profiles
    where role='student' and coalesce(status,'')<>'ended'
      and public.sessions_left(id) < 0)                                     as 마이너스학생;
