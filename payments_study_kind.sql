-- 수납 종류에 '스터디' 를 추가한다 (원장 지시 2026-09-03)
--
-- 주말 스터디 비용(3만원)을 받아도 수납탭에 넣을 칸이 없었다.
-- 종류가 수납 / 사전 OT / 환불 세 가지뿐이라 CHECK 제약이 막고 있었다.
--   new row for relation "payments" violates check constraint "payments_kind_chk"
--
-- 스터디는 수업 횟수와 무관하다. 회차 계산은 payment·ot 만 세므로
-- 'study' 를 더해도 남은 횟수에는 영향이 없다.
--
-- Supabase → SQL Editor 에 붙여넣고 Run 을 누르면 된다. 되돌리려면 맨 아래 주석 참고.

alter table payments drop constraint if exists payments_kind_chk;

alter table payments add constraint payments_kind_chk
  check (kind in ('payment', 'ot', 'refund', 'study'));

-- 확인용 — 지금 들어 있는 종류를 세어 본다
-- select kind, count(*) from payments group by kind order by count(*) desc;

-- 되돌리기 (스터디로 넣은 수납이 하나도 없을 때만 된다)
-- alter table payments drop constraint if exists payments_kind_chk;
-- alter table payments add constraint payments_kind_chk
--   check (kind in ('payment', 'ot', 'refund'));
