-- =====================================================================
--  진단고사 문항별 소요 시간 저장 (2026-08-05)
--  Supabase > SQL Editor 에 전체 붙여넣고 [Run]
--
--  total_sec : 전체 소요 시간(초)
--  timed_out : 제한시간(20분)을 다 써서 자동 제출됐는지
--  times     : 문항별 기록 JSON
--              [{"n":1,"c":"문법","s":7,"t":10}, ...]
--              n=문항번호 · c=유형 · s=걸린초 · t=목표초
-- =====================================================================

alter table public.diagnostics add column if not exists total_sec int;
alter table public.diagnostics add column if not exists timed_out boolean default false;
alter table public.diagnostics add column if not exists times     jsonb;

-- diagnostics 는 칸별이 아니라 표 전체로 권한을 준 상태라
-- 새 칸도 자동으로 포함됩니다. (profiles 처럼 따로 grant 할 필요 없음)
-- 아래 줄은 혹시 모를 경우를 대비한 재확인용 — 실행해도 무해합니다.
grant insert on public.diagnostics to anon, authenticated;
grant select, delete on public.diagnostics to authenticated;

-- 확인 — 세 칸이 보이면 성공
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'diagnostics'
  and column_name in ('total_sec', 'timed_out', 'times')
order by column_name;
