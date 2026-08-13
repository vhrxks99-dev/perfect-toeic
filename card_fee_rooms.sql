-- 카드 수수료 + 학생이 강의장 이름 보기 (2026-08-13 원장 지시)
--
-- 1) 카드 수수료 2.5% 일괄, **강사가 전부 부담**(원장 B 선택).
--    계산 순서: 강사 몫 = 금액 × 배분율 − 카드수수료, 그다음 원천징수.
--    요율은 등록 시점 값을 행에 박아 둔다(배분율·원천징수와 같은 이유 —
--    나중에 요율이 바뀌어도 지난 달 정산이 흔들리면 안 된다).
--    ⚠️ 부가세(vat)는 수수료 계산에서 뺀다. 학원이 나라에 내는 돈이라
--       그 카드 수수료까지 강사가 물 이유가 없다.
--
-- 2) 학생 '내 학습' 수업내역의 메모 칸을 강의장으로 바꿨다.
--    학생이 rooms 를 못 읽으면 방 이름이 안 보이므로 읽기만 열어 준다.
--    (강의장 이름·정원은 민감한 정보가 아니다. 쓰기는 그대로 원장·매니저만.)
--
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.

-- 1) 카드 수수료율 스냅샷 칸
alter table public.payments add column if not exists card_fee_rate numeric;

comment on column public.payments.card_fee_rate is
  '이 결제에 적용한 카드 수수료율(%). 카드 결제일 때만 채운다. 강사 몫에서 뺀다(원장 확정 2026-08-13).';

-- 이미 들어가 있는 카드 결제분에도 2.5% 를 채워 준다(안 채우면 화면 계산과 어긋난다).
update public.payments
   set card_fee_rate = 2.5
 where card_fee_rate is null
   and method is not null
   and (method = '카드' or method like '%카드%');

-- 2) 학생도 강의장 이름을 읽을 수 있게
drop policy if exists rooms_read_all on public.rooms;
create policy rooms_read_all on public.rooms for select to authenticated using (true);

-- 확인용
-- select method, card_fee_rate, count(*) from public.payments group by 1,2 order by 1;
-- select polname from pg_policies where tablename='rooms';
