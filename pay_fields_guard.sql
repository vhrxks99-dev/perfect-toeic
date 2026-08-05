-- 배분율·원천징수는 원장님만 조정 (2026-08-05)
-- 화면에서 칸을 잠그는 것만으로는 부족하다. 서버에서도 막는다.
--
-- 규칙
--  원장(master)  : 자유롭게 입력·수정
--  그 외(매니저 등): 값을 보내도 무시하고 시스템 값으로 덮어쓴다.
--                   배분율 = 그 강사의 teacher_rates 값(없으면 50)
--                   원천징수 = 3.3
--                   이미 등록된 건의 요율만 바꾸려 하면 거부한다.
--                   단, 담당 강사를 바꾸는 경우에는 새 강사의 요율로 다시 채운다.
-- 강사(admin)는 애초에 수납 등록·수정 권한이 없다(payments 정책).
-- 여러 번 실행해도 안전합니다.

create or replace function public.guard_pay_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_role text := coalesce(public.my_role(), '');
  v_rate numeric;
begin
  if v_role = 'master' then
    return new;
  end if;

  if TG_OP = 'INSERT' then
    if new.teacher_id is null then
      new.pay_rate := null;
      new.withhold_rate := null;
    else
      select pay_rate into v_rate from public.teacher_rates where teacher_id = new.teacher_id;
      new.pay_rate := coalesce(v_rate, 50);
      new.withhold_rate := 3.3;
    end if;
    return new;
  end if;

  if TG_OP = 'UPDATE' then
    if new.teacher_id is distinct from old.teacher_id then
      if new.teacher_id is null then
        new.pay_rate := null;
        new.withhold_rate := null;
      else
        select pay_rate into v_rate from public.teacher_rates where teacher_id = new.teacher_id;
        new.pay_rate := coalesce(v_rate, 50);
        new.withhold_rate := 3.3;
      end if;
      return new;
    end if;
    if new.pay_rate is distinct from old.pay_rate
       or new.withhold_rate is distinct from old.withhold_rate then
      raise exception '배분율·원천징수는 원장님만 변경할 수 있습니다.';
    end if;
    return new;
  end if;

  return new;
end;
$fn$;

drop trigger if exists trg_guard_pay_fields on public.payments;
create trigger trg_guard_pay_fields
  before insert or update on public.payments
  for each row execute function public.guard_pay_fields();

select '트리거 설치' as 항목,
       case when exists (select 1 from pg_trigger
                         where tgrelid='public.payments'::regclass
                           and tgname='trg_guard_pay_fields')
            then 'OK' else '없음 (문제)' end as 결과
union all
select 'NULL 함정 차단(coalesce)',
       case when prosrc like '%coalesce(public.my_role()%' then 'OK' else '확인 필요' end
from pg_proc where proname = 'guard_pay_fields';
