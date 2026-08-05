-- 배분율·정산 비공개 처리 (2026-08-05)
-- 문제 1: profiles.pay_rate 를 선생님(admin)도 읽을 수 있었다.
--         회원 목록을 통째로 받아오므로 화면에서 가려도 값은 손에 들어온다.
-- 문제 2: payments 정책 pay_admin 이 admin 에게 전체 권한을 줘서,
--         선생님이 그 달 결제 전부(다른 강사 실지급액·배분율 포함)를 볼 수 있었다.
-- 조치  : 배분율을 teacher_rates 표로 분리해 행 단위 보안으로 '본인 것만' 을 표현.
--         payments 는 선생님이 본인 담당 건만 조회하도록 좁힘.
-- 여러 번 실행해도 안전합니다.

create table if not exists public.teacher_rates (
  teacher_id uuid primary key references auth.users(id) on delete cascade,
  pay_rate   numeric not null default 50 check (pay_rate >= 0 and pay_rate <= 100),
  updated_at timestamptz not null default now()
);

do $mig$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='profiles' and column_name='pay_rate') then
    insert into public.teacher_rates (teacher_id, pay_rate)
    select id, coalesce(pay_rate, 50) from public.profiles
    where role in ('admin','master','manager')
    on conflict (teacher_id) do nothing;
  end if;
end
$mig$;

alter table public.teacher_rates enable row level security;

drop policy if exists tr_select on public.teacher_rates;
create policy tr_select on public.teacher_rates for select to authenticated
  using (coalesce(public.my_role(),'') in ('master','manager') or teacher_id = auth.uid());

grant select on public.teacher_rates to authenticated;

drop trigger if exists trg_guard_pay_rate on public.profiles;
drop function if exists public.guard_pay_rate();
alter table public.profiles drop column if exists pay_rate;

drop function if exists public.set_pay_rate(uuid, numeric);

create function public.set_pay_rate(target uuid, rate numeric)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_role text := coalesce(public.my_role(), '');
  v_target_role text;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if v_role <> 'master' then raise exception '배분율은 원장님만 변경할 수 있습니다.'; end if;
  if rate is null or rate < 0 or rate > 100 then raise exception '배분율은 0에서 100 사이여야 합니다.'; end if;

  select role into v_target_role from public.profiles where id = target;
  if v_target_role is null then raise exception '대상 회원을 찾을 수 없습니다.'; end if;
  if v_target_role not in ('admin','master','manager') then
    raise exception '강사·원장 계정에만 배분율을 지정할 수 있습니다.';
  end if;

  insert into public.teacher_rates (teacher_id, pay_rate, updated_at)
  values (target, rate, now())
  on conflict (teacher_id) do update set pay_rate = excluded.pay_rate, updated_at = now();
end;
$fn$;

revoke all on function public.set_pay_rate(uuid, numeric) from public, anon;
grant execute on function public.set_pay_rate(uuid, numeric) to authenticated;

drop policy if exists "pay_admin" on public.payments;
drop policy if exists pay_ops_all on public.payments;
drop policy if exists pay_teacher_read on public.payments;

create policy pay_ops_all on public.payments for all to authenticated
  using      (coalesce(public.my_role(),'') in ('master','manager'))
  with check (coalesce(public.my_role(),'') in ('master','manager'));

create policy pay_teacher_read on public.payments for select to authenticated
  using (coalesce(public.my_role(),'') = 'admin' and teacher_id = auth.uid());

select 'profiles.pay_rate 제거됨' as 항목,
       case when not exists (select 1 from information_schema.columns
                             where table_schema='public' and table_name='profiles' and column_name='pay_rate')
            then 'OK' else '아직 남음' end as 결과
union all
select 'teacher_rates 행 수', count(*)::text from public.teacher_rates
union all
select 'payments 정책 수 (3이어야 정상)', count(*)::text
from pg_policies where schemaname='public' and tablename='payments'
union all
select 'set_pay_rate anon 실행',
       case when has_function_privilege('anon','public.set_pay_rate(uuid,numeric)','execute')
            then '아직 가능 (문제)' else '차단됨 OK' end;
