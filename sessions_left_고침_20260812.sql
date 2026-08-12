-- 남은 횟수 계산식 복구 (2026-08-12)
--
-- 무슨 일이 있었나
--  ot_schedule.sql(2026-08-12) 이 sessions_left 를 다시 만들면서 두 가지를 빠뜨렸다.
--   (1) session_adjustments(손보정 장부) 를 더하는 줄이 통째로 사라졌다
--       -> 손으로 넣은 보정과 통통통 이관분이 서버 계산에서 전부 무시된다.
--   (2) lesson_result.sql 이 넣었던 결석/휴강 규칙이 옛날 판으로 되돌아갔다
--       -> 결석(noshow)이 차감이 안 되고, 휴강(canceled)은 거꾸로 차감된다.
--  화면(index.html 의 remainOf/countsAsUsed)은 셋을 다 반영하고 있어서
--  화면 숫자와 서버 숫자가 서로 달랐다.
--
-- 올바른 식 = 산 횟수 + 손보정 합 - 쓴 수업 수
--  쓴 수업 = 회원으로 등록된 학생 + 확정(출석)이거나 결석 + 구글발 아님 + 사전 OT 아님
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

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
                      and coalesce(source,'web') <> 'gcal'
                      and coalesce(is_ot,false) = false), 0);
$$;

revoke all on function public.sessions_left(uuid) from public, anon;
grant execute on function public.sessions_left(uuid) to authenticated;

-- 확인용 — 네 칸이 모두 true 여야 한다
select
  (d like '%session_adjustments%') as 손보정반영,
  (d like '%noshow%')              as 결석차감,
  (d like '%is_ot%')               as OT제외,
  (d like '%payments%')            as 결제반영
from (select pg_get_functiondef(p.oid) as d
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'sessions_left') t;
