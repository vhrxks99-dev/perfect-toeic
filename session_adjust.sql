-- 수업 횟수 수동 조정 (2026-08-08 원장 지시)
--
-- 원장 결정
--  · 스케줄 기준 자동 차감은 그대로 둔다. 손으로 넣는 건 '예외 보정'용이다.
--    (선생님 사정으로 취소된 수업 +1, 서비스로 1회 더 드림 +1, 옛날 기록 맞추기 등)
--  · 조정에는 반드시 날짜가 붙는다. 언제 왜 늘리고 줄였는지 남아야 하기 때문이다.
--  · 출석 기록은 그대로 둔다(선생님 평가의 출석률이 이걸 쓴다).
--
-- 남은 횟수 = 산 횟수 + 손으로 조정한 합 - 잡힌 수업 수
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) 조정 장부
create table if not exists public.session_adjustments (
  id           bigint generated always as identity primary key,
  student_id   uuid references auth.users(id) on delete set null,
  student_name text,
  delta        int  not null,
  happened_on  date not null default ((now() at time zone 'Asia/Seoul')::date),
  reason       text,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- 0회 조정은 의미가 없고, 자릿수 실수(+100회)를 막는다
alter table public.session_adjustments drop constraint if exists session_adjustments_delta_check;
alter table public.session_adjustments add constraint session_adjustments_delta_check
  check (delta <> 0 and delta between -100 and 100);

create index if not exists session_adjustments_student_idx
  on public.session_adjustments(student_id, happened_on desc);

alter table public.session_adjustments enable row level security;

-- 2) 권한 — 원장·매니저는 전체, 선생님은 본인 담당 학생만, 학생은 본인 것 보기만
--    my_role() 은 비로그인일 때 NULL 이라 coalesce 로 감싼다(안 그러면 비교가 NULL 이 된다)
drop policy if exists adj_sel on public.session_adjustments;
create policy adj_sel on public.session_adjustments for select to authenticated
  using (
    student_id = auth.uid()
    or coalesce(public.my_role(),'') in ('master','manager')
    or (coalesce(public.my_role(),'') = 'admin' and public.is_my_student(student_id))
  );

drop policy if exists adj_ins on public.session_adjustments;
create policy adj_ins on public.session_adjustments for insert to authenticated
  with check (
    coalesce(public.my_role(),'') in ('master','manager')
    or (coalesce(public.my_role(),'') = 'admin' and public.is_my_student(student_id))
  );

drop policy if exists adj_del on public.session_adjustments;
create policy adj_del on public.session_adjustments for delete to authenticated
  using (
    coalesce(public.my_role(),'') in ('master','manager')
    or (coalesce(public.my_role(),'') = 'admin' and public.is_my_student(student_id))
  );

-- 고치는 건 막는다. 장부는 남기고 지우고 다시 넣는 쪽이 이력이 정확하다.
drop policy if exists adj_upd on public.session_adjustments;

grant select, insert, delete on public.session_adjustments to authenticated;

-- 3) 남은 횟수에 조정분을 더한다
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
                      and coalesce(status,'confirmed') = 'confirmed'
                      and coalesce(source,'web') <> 'gcal'), 0);
$$;

revoke all on function public.sessions_left(uuid) from public, anon;
grant execute on function public.sessions_left(uuid) to authenticated;

-- 4) 조정으로 남은 횟수가 1회가 되어도 결제 안내가 걸리게 한다
drop trigger if exists trg_payment_due_adj on public.session_adjustments;
create trigger trg_payment_due_adj
  after insert on public.session_adjustments
  for each row
  when (new.student_id is not null)
  execute function public.enqueue_payment_due();

-- 확인용 — 정책 3개(adj_sel/adj_ins/adj_del)가 나와야 한다
select policyname as 정책, cmd as 동작
from pg_policies
where schemaname = 'public' and tablename = 'session_adjustments'
order by policyname;
