-- 구글 캘린더 연동 끊기 (2026-08-16 원장 지시)
--
-- 원장 지시 그대로
--  "오늘까지 구글캘린더 연동된 건 그대로 웹페이지 캘린더에 저장해두고 이제 구글캘린더 연동 끊어줘"
--  (2026-08-06 에 드렸던 A/B 안 중 A 를 고르셨습니다.)
--
-- 무엇이 바뀌나
--  · 이미 들어온 수업은 **하나도 안 지웁니다.** schedules 에 그대로 남아 달력에 계속 보입니다.
--  · 앞으로 구글 캘린더에서 수업을 만들거나 고쳐도 **웹에 안 들어옵니다.**
--  · 웹에서 잡은 수업도 구글로 안 나갑니다.
--  · 그러니 이제부터 수업은 **웹 달력에서** 잡으셔야 합니다.
--
-- 되돌리려면 맨 아래 주석 두 줄을 실행하면 됩니다(설정은 지우지 않았습니다).
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) 5분마다 구글에서 가져오던 작업을 멈춘다
select cron.unschedule('gcal-sync-5min')
 where exists (select 1 from cron.job where jobname = 'gcal-sync-5min');

-- 2) 웹 -> 구글로 내보내던 대기열도 멈춘다
--    (안 멈추면 gcal_outbox 에 아무도 안 읽는 줄이 계속 쌓인다)
drop trigger if exists trg_gcal_enqueue on public.schedules;

-- 3) 아직 안 나간 대기열 정리
delete from public.gcal_outbox where done_at is null;

-- 4) 확인
select 'cron 남은 작업' as k, string_agg(jobname, ', ' order by jobname) as v from cron.job
union all
select '구글 연동 트리거',
       coalesce(string_agg(t.tgname, ', ' order by t.tgname), '없음')
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where c.relname = 'schedules' and not t.tgisinternal and t.tgname = 'trg_gcal_enqueue'
union all
select '남아 있는 구글 수업', count(*)::text from public.schedules where source = 'gcal';

-- 되돌리기 (필요할 때만)
-- select cron.schedule('gcal-sync-5min', '*/5 * * * *', $cron$ ... $cron$);
--   -> 원래 명령은 gcal_sync.sql 에 있습니다. 되살릴 일이 생기면 말씀해주세요.
-- 트리거 되살리기: create trigger trg_gcal_enqueue ... (gcal_sync.sql 참고)
