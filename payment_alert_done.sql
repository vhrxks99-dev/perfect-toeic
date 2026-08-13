-- 결제 안내 기준을 '끝낸 수업'으로 바꾼다 (2026-08-13 원장 지시)
--
-- 원장 지시 그대로
--  "그게 수업스케줄때문에 그래. 수업스케줄을 잡으면 지금 수업횟수를 차감하게 해버렸잖아.
--   근데 8회수업기준 7회차 수업을 완료하고 나면 전송되도록 해야 해"
--
-- 무엇이 문제였나
--  화면의 '남은 횟수'는 **잡아 둔 수업까지** 뺀다. 예약을 남발하지 못하게 하려고 그렇게 만들었다.
--  그래서 8회를 끊고 8개를 한꺼번에 잡으면 그 자리에서 0회가 된다. 한 번도 안 했는데 말이다.
--  이 숫자로 알림톡을 쏘면 수업 시작도 전에 결제 안내가 나간다.
--
-- 어떻게 고치나
--  화면 숫자(sessions_left)는 그대로 둔다 — 예약 제한에 쓰는 값이라 건드리면 안 된다.
--  알림톡 판단만 따로 센다: 산 횟수 - **이미 끝난 수업**. 8회 중 7회를 마치면 1이 되고 그때 보낸다.
--
-- '끝난 수업'의 뜻 (sessions_left 와 같은 제외 규칙 + 시간 조건 하나)
--  · 회원으로 연결된 수업만
--  · 확정(출석) 또는 결석. 휴강·승인대기는 안 센다
--  · 사전 OT 는 안 센다
--  · 구글 수업은 2026-08-12 14:00 이후 것만
--  · 그리고 **끝나는 시각이 이미 지났을 것**  ← 이 줄이 이번에 새로 들어간 조건이다
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) 끝낸 수업 기준 남은 횟수
create or replace function public.sessions_left_done(p_student uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select sum(sessions) from public.payments
                    where student_id = p_student and sessions is not null), 0)
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

comment on function public.sessions_left_done(uuid) is
  '결제 안내 판단용. 화면의 sessions_left 와 달리 아직 안 한 수업은 빼지 않는다(원장 지시 2026-08-13).';

revoke all on function public.sessions_left_done(uuid) from public, anon;
grant execute on function public.sessions_left_done(uuid) to authenticated;

-- 2) 옛 방식 끄기 — '수업을 잡는 순간' 대기열에 넣던 것들
--    (출석표는 이제 안 쓰고, 스케줄에 걸린 건 잡자마자 안내가 나가서 문제였다)
drop trigger if exists trg_payment_due on public.attendance;
drop trigger if exists trg_payment_due on public.schedules;

-- 3) 새 방식 — 주기적으로 훑어서 '딱 1회 남은' 학생을 대기열에 넣는다
--    수업이 끝나는 '순간'을 알려 주는 사건이 없어서 훑는 수밖에 없다.
create or replace function public.scan_payment_due()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r          record;
  v_left     int;
  v_last_pay timestamptz;
  v_next     timestamptz;
  v_body     text;
  v_n        int := 0;
begin
  for r in
    select id, name, phone from public.profiles
     where role = 'student' and coalesce(status,'active') <> 'ended'
  loop
    v_left := public.sessions_left_done(r.id);
    if v_left <> 1 then
      continue;
    end if;

    -- 이번 수강권에 이미 넣었으면 또 넣지 않는다.
    -- 횟수를 새로 사면 그 결제 시각 이후로 다시 한 번 열린다.
    select max(created_at) into v_last_pay
      from public.payments
     where student_id = r.id and coalesce(sessions,0) > 0;

    if exists (
      select 1 from public.notify_outbox o
       where o.student_id = r.id
         and o.kind = 'payment_due'
         and o.created_at > coalesce(v_last_pay, '-infinity'::timestamptz)
    ) then
      continue;
    end if;

    -- 다음 수업이 잡혀 있으면 날짜를 같이 알려준다(원장 지시 2026-08-06).
    select min(starts_at) into v_next
      from public.schedules
     where student_id = r.id
       and starts_at > now()
       and coalesce(status,'confirmed') <> 'pending';

    v_body :=
         '안녕하세요, 완벽한토익입니다.' || E'\n'
      || '수강생 ' || coalesce(r.name,'학생') || '님 남은 수업은 1회입니다.' || E'\n\n'
      || '완벽한토익 웹페이지에서 ''내 학습''에 들어가 출석내역·결제내역을 확인하신 후 다음 수업 결제를 부탁드립니다.' || E'\n'
      || '결제기한은 '
      || case when v_next is null then '다음 수업 전까지입니다.'
              else to_char(v_next at time zone 'Asia/Seoul','MM"월" DD"일"') || ' 수업 전까지입니다.'
         end || E'\n\n'
      || '· 계좌 : 기업은행 04313343401013 완벽한토익' || E'\n'
      || '· 카드결제가 필요하시면 다음 수업 때 창구에서 결제 부탁드립니다.';

    insert into public.notify_outbox(student_id, student_name, phone, kind,
                                     left_count, next_lesson_at, body)
    values (r.id, r.name, r.phone, 'payment_due', v_left, v_next, v_body);
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

revoke all on function public.scan_payment_due() from public, anon;
grant execute on function public.scan_payment_due() to authenticated;

-- 4) 옛 기준으로 들어간 대기열 정리 — 아직 한 통도 안 보냈으므로 지워도 안전하다.
--    새 기준에 맞는 학생은 아래 훑기에서 다시 들어온다.
delete from public.notify_outbox
 where sent_at is null
   and kind = 'payment_due'
   and public.sessions_left_done(student_id) <> 1;

-- 5) 30분마다 훑기
select cron.unschedule('payment-due-scan')
 where exists (select 1 from cron.job where jobname = 'payment-due-scan');

select cron.schedule('payment-due-scan', '*/30 * * * *',
  $cron$ select public.scan_payment_due(); $cron$);

-- 확인용
-- select public.scan_payment_due();
-- select id, student_name, left_count, created_at, sent_at from public.notify_outbox order by id;
-- select jobname, schedule, active from cron.job where jobname = 'payment-due-scan';
