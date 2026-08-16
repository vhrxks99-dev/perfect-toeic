-- 사전 OT 결제가 '수강권 1회'로 잡히던 문제 (2026-08-16 원장 지적, 실행 완료)
--
-- 원장 지시 그대로
--  "장지혜는 방금 문의가 들어와서 사전 OT 하기 위해 6만원 받은 후 사전 오티 버튼도 클릭했어.
--   그런데 수업횟수에서 1회 남았다는 이유로 재등록 결제 알림톡 발송되려 해. 이건 맞지 않아.
--   왜냐면 8회 수업 후 7회가 종료 후에 1회 남았을 때 발송이 되야지."
--
-- 무엇이 문제였나
--  · 사전 OT 를 받으면 수납에 kind='ot', 횟수 1회로 등록한다(화면이 1회를 요구한다).
--  · 그런데 OT '수업' 은 is_ot=true 라서 차감 대상이 아니다.
--  · 그래서 **OT만 하고 아직 등록은 안 한 학생**은 산 횟수 +1, 쓴 횟수 0 이 되어
--    남은 횟수가 영원히 1회로 남았고, 결제 안내가 그 1회를 보고 재등록 알림톡을 쐈다.
--  · 실제로 2026-08-16 11:43 에 장지혜 학생에게 잘못 나갔다(원장님이 11:50 에 수습).
--
-- 🚨 처음에 'OT 결제는 무조건 안 센다'로 고쳤다가 되돌렸다 — 그러면 안 된다.
--    원장님은 **등록한 학생의 잔액을 '7회'로** 넣으신다(OT 6만 + 잔액 42만 = 48만 = 8회권).
--    즉 등록한 학생에게는 OT 1회가 8회 중 1회로 들어간다.
--    무조건 빼면 김한섭·박성준·서원주의 남은 횟수가 1회씩 줄어든다(실제로 한 번 그렇게 만들었다).
--
-- 최종 규칙
--    **정규 수강권 결제(kind <> 'ot' 이고 횟수 > 0)가 아직 없는 학생의 OT 결제만 횟수로 안 센다.**
--      · OT만 한 사람   -> 0회  (재등록 안내가 안 나간다)
--      · 등록까지 한 사람 -> OT 1 + 잔액 7 = 8회 (종전 그대로)
--    수납·매출·강사 정산에서는 OT 도 그대로 잡힌다 — payments 행은 손대지 않는다.
--
-- 고치는 함수는 둘이다. 하나만 고치면 화면 숫자와 알림이 어긋난다.
--  · sessions_left       : 화면 '남은 횟수' · 학생 예약 제한
--  · sessions_left_done  : 결제 안내 판단(끝난 수업만 뺀 값)
--  화면(index.html) 의 loadAttendance·renderLearn 도 같은 규칙으로 고쳐 뒀다.
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) 남은 횟수 (화면 · 예약 제한)
create or replace function public.sessions_left(p_student uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select sum(sessions) from public.payments
                    where student_id = p_student and sessions is not null
                      and (coalesce(kind,'payment') <> 'ot'
                           or exists (select 1 from public.payments q
                                       where q.student_id = p_student
                                         and coalesce(q.kind,'payment') <> 'ot'
                                         and coalesce(q.sessions,0) > 0))), 0)
       + coalesce((select sum(delta) from public.session_adjustments
                    where student_id = p_student), 0)
       - coalesce((select count(*) from public.schedules
                    where student_id = p_student
                      and coalesce(status,'confirmed') in ('confirmed','noshow')
                      and coalesce(is_ot,false) = false
                      and coalesce(student_name,'') || ' ' || coalesce(subject,'')
                          !~ '\(\s*신규\s*\)'
                      and (coalesce(source,'web') <> 'gcal'
                           or starts_at > timestamptz '2026-08-12 14:00:00+09')), 0);
$$;

-- 2) 결제 안내 판단용 남은 횟수 (끝난 수업만 뺀다)
create or replace function public.sessions_left_done(p_student uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select sum(sessions) from public.payments
                    where student_id = p_student and sessions is not null
                      and (coalesce(kind,'payment') <> 'ot'
                           or exists (select 1 from public.payments q
                                       where q.student_id = p_student
                                         and coalesce(q.kind,'payment') <> 'ot'
                                         and coalesce(q.sessions,0) > 0))), 0)
       + coalesce((select sum(delta) from public.session_adjustments
                    where student_id = p_student), 0)
       - coalesce((select count(*) from public.schedules
                    where student_id = p_student
                      and coalesce(status,'confirmed') in ('confirmed','noshow')
                      and coalesce(is_ot,false) = false
                      and coalesce(student_name,'') || ' ' || coalesce(subject,'')
                          !~ '\(\s*신규\s*\)'
                      and (coalesce(source,'web') <> 'gcal'
                           or starts_at > timestamptz '2026-08-12 14:00:00+09')
                      and ends_at < now()), 0);
$$;

-- 3) 잘못 대기 중인 결제 안내를 지운다 (아직 안 나간 것만)
--    새 기준으로 다시 1회가 되면 30분마다 도는 scan_payment_due 가 다시 넣는다.
delete from public.notify_outbox
 where sent_at is null
   and kind = 'payment_due'
   and public.sessions_left_done(student_id) <> 1;

-- 4) 확인 — OT 결제가 있는 학생
--    2026-08-16 실행 결과: 김한섭 8 / 박성준 8 / 서원주 8 / 장지혜 0
select pr.name,
       (select coalesce(sum(p.sessions),0) from public.payments p
         where p.student_id = pr.id and p.kind = 'ot')          as ot_cnt,
       (select coalesce(sum(p.sessions),0) from public.payments p
         where p.student_id = pr.id and coalesce(p.kind,'payment') <> 'ot') as pass_cnt,
       public.sessions_left(pr.id)      as remain,
       public.sessions_left_done(pr.id) as remain_done
  from public.profiles pr
 where exists (select 1 from public.payments p where p.student_id = pr.id and p.kind = 'ot')
 order by pr.name;
