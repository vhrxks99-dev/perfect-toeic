-- 정산: 수납 / 환불 구분 칸 추가
-- 증상: 수납을 등록하면 "Could not find the 'kind' column of 'payments'" 로 실패.
--       화면은 수납/환불을 고르게 돼 있는데 표에 그 칸이 없어서 저장이 막혔다.
-- 금액은 항상 양수로 저장하고 kind 로 방향만 구분한다.
--   (마이너스를 직접 입력하게 하면 부호를 빠뜨리는 실수가 난다)
--   화면에서 집계할 때 환불 건은 빼서 계산한다.
-- 여러 번 실행해도 안전합니다.

alter table public.payments
  add column if not exists kind text not null default 'payment';

alter table public.payments drop constraint if exists payments_kind_chk;
alter table public.payments
  add constraint payments_kind_chk check (kind in ('payment','refund'));

create index if not exists idx_pay_paid_at on public.payments(paid_at);

select 'kind 칸' as 항목,
       case when exists (select 1 from information_schema.columns
                         where table_schema='public' and table_name='payments' and column_name='kind')
            then 'OK' else '없음 (문제)' end as 결과
union all
select 'kind 값 제약',
       case when exists (select 1 from pg_constraint
                         where conrelid='public.payments'::regclass and conname='payments_kind_chk')
            then 'OK' else '없음 (문제)' end
union all
select '기존 수납 건수(전부 payment 로 채워짐)', count(*)::text from public.payments;
