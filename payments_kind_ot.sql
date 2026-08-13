-- 수납 구분에 '사전 OT' 허용 (2026-08-13 원장 지적 "OT 받을 때 1회로 한 줄이 어딨어?")
--
-- 배경: 수업 횟수권은 8회부터라 1회짜리 OT 선결제를 화면에서 넣을 수가 없었다.
--       구분에 '사전 OT' 를 만들었는데, DB 제약이 payment / refund 만 받아서 저장이 막혔다.
--
-- OT 는 매출·강사 배분에서 일반 수납과 똑같이 잡힌다(마이너스는 환불뿐).
-- 다만 화면에서 '8회부터' 규칙을 면제받고 배지가 붙는다.
--
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.

alter table public.payments drop constraint if exists payments_kind_chk;
alter table public.payments add constraint payments_kind_chk
  check (kind in ('payment','refund','ot'));

-- 확인용
-- select kind, count(*) from public.payments group by kind order by kind;
