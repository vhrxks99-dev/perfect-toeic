-- 강사 배분율 / 원천징수 (2026-08-03)
-- Supabase 접속 → 왼쪽 SQL Editor → 아래 전체를 붙여넣고 Run.
-- 한 번만 실행하면 됩니다. 다시 돌려도 사고는 나지 않습니다.
--
-- 규칙: 강사 몫 = 담당 학생 매출 x 배분율(기본 50%)
--       실지급액 = 강사 몫 - 원천징수 3.3%

-- ─────────────────────────────────────────────
-- 1) 강사별 배분율 (%). 기본 50
-- ─────────────────────────────────────────────
alter table public.profiles
  add column if not exists pay_rate numeric(5,2) not null default 50;

-- ─────────────────────────────────────────────
-- 2) 결제 시점의 담당 강사·배분율·원천징수율을 payments 행에 그대로 박아 둔다.
--    나중에 담당 강사를 바꾸거나 배분율을 조정해도
--    이미 지급이 끝난 지난 달 금액이 뒤늦게 달라지지 않게 하기 위함이다.
-- ─────────────────────────────────────────────
alter table public.payments
  add column if not exists teacher_id    uuid references auth.users(id) on delete set null,
  add column if not exists teacher_name  text,
  add column if not exists pay_rate      numeric(5,2),
  add column if not exists withhold_rate numeric(5,2);
-- 부가세(VAT)는 학원이 부담한다. 강사 지급액 계산에는 들어가지 않으므로 칸을 두지 않는다.

create index if not exists payments_teacher_month_idx
  on public.payments (teacher_id, month);

-- ─────────────────────────────────────────────
-- 3) 배분율은 본인이 못 바꾼다. 원장님만 이 함수로 변경.
-- ─────────────────────────────────────────────
create or replace function public.set_pay_rate(target uuid, rate numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.my_role() is distinct from 'master' then
    raise exception '배분율은 원장님만 변경할 수 있습니다.';
  end if;
  if rate is null or rate < 0 or rate > 100 then
    raise exception '배분율은 0에서 100 사이여야 합니다.';
  end if;
  update public.profiles set pay_rate = rate where id = target;
end;
$$;

revoke all on function public.set_pay_rate(uuid, numeric) from public;
grant execute on function public.set_pay_rate(uuid, numeric) to authenticated;

-- ─────────────────────────────────────────────
-- 4) 혹시 다른 경로로 직접 UPDATE 하더라도 배분율은 원장님만 바꿀 수 있게 한 번 더 막는다.
--    (강사가 자기 배분율을 스스로 올리는 것을 방지)
-- ─────────────────────────────────────────────
create or replace function public.guard_pay_rate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.pay_rate is distinct from old.pay_rate
     and public.my_role() is distinct from 'master' then
    raise exception '배분율은 원장님만 변경할 수 있습니다.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_pay_rate on public.profiles;
create trigger trg_guard_pay_rate
  before update on public.profiles
  for each row execute function public.guard_pay_rate();

-- ─────────────────────────────────────────────
-- 5) 확인용 — 실행 후 이 줄만 따로 돌려 보면 강사별 배분율이 보입니다.
-- ─────────────────────────────────────────────
-- select name, role, pay_rate from public.profiles where role in ('admin','master') order by name;
