-- 수납에 부가세 칸 추가 (2026-08-13 원장 요청)
--
-- 왜: 카드로 받을 때 수업료와 별도로 부가세 10%를 따로 받는데 적을 곳이 없었다.
--     (2026-08-13 서원주 학생 — 6만 + 42만 결제 후 부가세 4만2천원을 따로 받음)
--
-- 🚨 부가세를 amount 에 합치면 안 된다. amount 는 **강사 배분의 기준**이라
--    합치는 순간 부가세까지 강사와 나눠 갖는 계산이 된다.
--    그래서 별도 칸에 넣고, 정산(payShare)은 amount 만 본다 → 저절로 빠진다.
--
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.

alter table public.payments add column if not exists vat integer;

comment on column public.payments.vat is
  '카드결제 시 따로 받은 부가세(원). 매출(amount)과 분리해서 적는다 — 강사 배분 기준에서 빼기 위함.';

-- payments 는 테이블 단위 권한이라 profiles 처럼 컬럼 grant 를 다시 줄 필요는 없지만,
-- 예전에 컬럼 단위로 좁혀 둔 적이 있으면 새 칸이 막히므로 한 번 더 확인해 준다.
do $$
begin
  if exists (
    select 1 from information_schema.column_privileges
     where table_schema='public' and table_name='payments' and grantee='authenticated'
  ) then
    execute 'grant update (vat), insert (vat) on public.payments to authenticated';
  end if;
exception when others then
  null;   -- 테이블 단위 grant 면 여기로 온다(정상)
end $$;

-- 확인용
-- select column_name, data_type from information_schema.columns
--  where table_schema='public' and table_name='payments' and column_name='vat';
