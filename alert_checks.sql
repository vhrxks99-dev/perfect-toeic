-- ============================================================
--  선생님 알림 '확인함' 수동 체크 (2026-08-05)
--  Supabase SQL Editor 에 전체 붙여넣고 RUN (여러 번 실행해도 안전)
--
--  왜 필요한가:
--   '확인이 필요해요'의 다음수업 알림은 학생을 이름으로 짝짓는다.
--   구글 캘린더에서 온 수업은 회원 연결 없이 이름만 있어서
--   "김서영(비대면)" 과 회원 "김서영" 이 다른 사람처럼 취급될 수 있다.
--   그러면 다음 수업이 실제로 잡혀 있는데도 안 잡혔다고 뜬다.
--   → 선생님이 직접 '확인함' 으로 지울 수 있게 한다.
--
--  student_key 는 화면의 stuKey() 값을 그대로 쓴다.
--    회원이면 'id:<uuid>', 이름만 있으면 'nm:<정규화된 이름>'
--  day 는 알림을 만든 '지난 수업 날짜'.
--    → 다음 주에 수업이 또 끝나면 날짜가 달라져 알림이 다시 뜬다.
--      (한 번 확인했다고 영영 안 뜨는 사고를 막는다)
-- ============================================================

create table if not exists public.alert_checks (
  id          bigint generated always as identity primary key,
  teacher_id  uuid not null references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('next','hw')),
  student_key text not null,
  student_name text,
  day         date not null,
  created_at  timestamptz not null default now()
);

create unique index if not exists uq_alert_checks
  on public.alert_checks (teacher_id, kind, student_key, day);
create index if not exists idx_alert_checks_teacher
  on public.alert_checks (teacher_id, day desc);

alter table public.alert_checks enable row level security;

-- 본인 것만 보고/추가/지우기. 원장·매니저는 전체 조회 가능.
drop policy if exists alert_checks_select on public.alert_checks;
create policy alert_checks_select on public.alert_checks for select to authenticated
  using (teacher_id = auth.uid() or coalesce(public.my_role(),'') in ('master','manager'));

drop policy if exists alert_checks_insert on public.alert_checks;
create policy alert_checks_insert on public.alert_checks for insert to authenticated
  with check (teacher_id = auth.uid());

drop policy if exists alert_checks_delete on public.alert_checks;
create policy alert_checks_delete on public.alert_checks for delete to authenticated
  using (teacher_id = auth.uid() or coalesce(public.my_role(),'') in ('master','manager'));

grant select, insert, delete on public.alert_checks to authenticated;

-- 확인 — 표와 정책 3개가 보이면 성공
select 'alert_checks 표' as 항목, count(*)::text as 값
from information_schema.tables
where table_schema='public' and table_name='alert_checks'
union all
select '정책 개수 (3이어야 정상)', count(*)::text
from pg_policies where schemaname='public' and tablename='alert_checks';
