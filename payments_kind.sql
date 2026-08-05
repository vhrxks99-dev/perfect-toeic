-- =====================================================================
--  정산: 수납 / 환불 구분 추가
--  Supabase > SQL Editor 에 이 파일 전체를 붙여넣고 [Run] 하세요.
--  (여러 번 실행해도 안전합니다)
--
--  하는 일:
--   지금까지는 정산에 '들어온 돈'만 적을 수 있었다. 환불을 적을 칸이 없어서
--   총매출이 실제보다 크게 잡혔다. 이제 등록할 때 수납/환불을 고를 수 있다.
--
--   금액은 항상 양수로 저장하고, kind 로 방향만 구분한다.
--   (마이너스를 직접 입력하게 하면 실수로 부호를 빠뜨리기 쉬움)
--   화면에서 집계할 때 환불 건은 빼서 계산한다.
-- =====================================================================

alter table public.payments
  add column if not exists kind text not null default 'payment';

alter table public.payments
  drop constraint if exists payments_kind_chk;
alter table public.payments
  add constraint payments_kind_chk check (kind in ('payment','refund'));

-- 기간별 집계는 결제일(paid_at)로 하므로 인덱스를 하나 만들어 둔다.
create index if not exists idx_pay_paid_at on public.payments(paid_at);

-- ─────────────────────────────────────────────
-- 확인용 — 실행 후 이 줄만 따로 돌려 보면 수납/환불 건수가 보입니다.
-- ─────────────────────────────────────────────
-- select kind, count(*), sum(amount) from public.payments group by kind;
