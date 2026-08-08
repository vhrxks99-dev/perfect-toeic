-- 수업 횟수 차감 기준을 '출석'에서 '스케줄'로 바꾼다 (2026-08-08 원장 지시)
-- 그리고 등원 키오스크(체크인)를 통째로 걷어낸다.
--
-- 규칙
--  1) 스케줄이 잡히면 1회 차감. 스케줄을 지우면 자동으로 1회 돌아온다(건수를 세는 방식이라 별도 처리 없음).
--  2) 구글 캘린더에서 온 수업(source='gcal')은 세지 않는다. 436건이 한꺼번에 차감되는 것을 막는다.
--  3) 학생 예약 '요청'(status='pending')은 승인 전이라 세지 않는다. 승인되는 순간부터 센다.
--  4) 출석 기록(attendance)은 그대로 남긴다. 선생님 평가의 출석률 지표가 이걸 쓴다.
--     다만 이제 출석은 남은 횟수와 무관하다.
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A → Delete → 붙여넣기 → 첫 줄이 주석(--)인지 눈으로 확인 → Run

-- 1) 남은 횟수 = 산 횟수 - 잡힌 수업 수
create or replace function public.sessions_left(p_student uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select sum(sessions) from public.payments
                    where student_id = p_student and sessions is not null), 0)
       - coalesce((select count(*) from public.schedules
                    where student_id = p_student
                      and coalesce(status,'confirmed') = 'confirmed'
                      and coalesce(source,'web') <> 'gcal'), 0);
$$;

revoke all on function public.sessions_left(uuid) from public, anon;
grant execute on function public.sessions_left(uuid) to authenticated;

-- 2) 학생이 앞으로 몇 건 더 예약할 수 있는지
--    sessions_left 가 이미 '확정된 수업'을 빼고 있으므로, 여기서는 아직 승인 안 난
--    '요청'만 추가로 뺀다. (예전 식은 확정분을 두 번 뺐다)
create or replace function public.booking_left(p_student uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select greatest(0, least(
    public.sessions_left(p_student) - (
      select count(*) from public.schedules
       where student_id = p_student and starts_at > now()
         and coalesce(status,'confirmed') = 'pending'),
    4 - (
      select count(*) from public.schedules
       where student_id = p_student and starts_at > now()
         and coalesce(status,'confirmed') in ('pending','confirmed'))
  ))::int;
$$;

revoke all on function public.booking_left(uuid) from public, anon;
grant execute on function public.booking_left(uuid) to authenticated;

-- 3) 예약 요청 — 잔여 검사만 위 규칙에 맞춘다(나머지는 booking_v2.sql 과 동일)
create or replace function public.request_booking(p_date date, p_start text, p_subject text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_teacher uuid; v_teacher_name text; v_student_name text;
  h int; s_ts timestamptz; e_ts timestamptz; v_room int; busy_teacher int;
  v_future int; v_pending int; v_sess int;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'msg','로그인이 필요해요.'); end if;
  select teacher_id, name into v_teacher, v_student_name from public.profiles where id = v_uid;
  if v_teacher is null then return jsonb_build_object('ok',false,'msg','담당 선생님 배정 후 이용할 수 있어요.'); end if;
  if p_start !~ '^[0-9]{2}:00$' then return jsonb_build_object('ok',false,'msg','잘못된 시간이에요.'); end if;
  h := split_part(p_start,':',1)::int;
  -- ↔ free_slots 의 v_hours 와 같아야 함
  if h <> all (array[10,13,15,17,19,21]) then return jsonb_build_object('ok',false,'msg','예약 가능한 시간이 아니에요.'); end if;

  select count(*) into v_future from public.schedules
   where student_id = v_uid and starts_at > now()
     and coalesce(status,'confirmed') in ('pending','confirmed');

  if v_future >= 4 then
    return jsonb_build_object('ok',false,'msg','예약은 한 번에 4건까지만 잡을 수 있어요. 지난 수업이 끝나면 다시 잡아주세요.');
  end if;

  select count(*) into v_pending from public.schedules
   where student_id = v_uid and starts_at > now()
     and coalesce(status,'confirmed') = 'pending';

  v_sess := public.sessions_left(v_uid);
  if v_sess - v_pending <= 0 then
    return jsonb_build_object('ok',false,'msg','남은 수업 횟수가 부족해요. (남은 '||v_sess||'회 · 승인 대기 '||v_pending||'건)');
  end if;

  select name into v_teacher_name from public.profiles where id = v_teacher;
  s_ts := (p_date::timestamp + make_interval(hours => h)) at time zone 'Asia/Seoul';
  e_ts := s_ts + interval '2 hours';
  if s_ts <= now() then return jsonb_build_object('ok',false,'msg','이미 지난 시간이에요.'); end if;
  select count(*) into busy_teacher from public.schedules
    where teacher_id = v_teacher and starts_at < e_ts and ends_at > s_ts;
  if busy_teacher > 0 then return jsonb_build_object('ok',false,'msg','방금 그 시간이 찼어요. 다른 시간을 골라주세요.'); end if;
  if exists(select 1 from public.schedules where student_id = v_uid and starts_at < e_ts and ends_at > s_ts) then
    return jsonb_build_object('ok',false,'msg','이미 그 시간에 예약이 있어요.');
  end if;

  select r.id into v_room from public.rooms r
    where coalesce(r.active,true)
      and not exists (select 1 from public.schedules s where s.room_id = r.id and s.starts_at < e_ts and s.ends_at > s_ts)
    order by r.id limit 1;

  insert into public.schedules(room_id, teacher_id, teacher_name, student_id, student_name, subject, starts_at, ends_at, memo, status)
    values (v_room, v_teacher, v_teacher_name, v_uid, v_student_name, coalesce(nullif(p_subject,''),'토익'), s_ts, e_ts, '학생 예약 요청', 'pending');

  return jsonb_build_object('ok',true,'msg','예약이 요청되었어요. 선생님 승인 후 확정됩니다.','left',public.booking_left(v_uid));
end;
$$;

revoke all on function public.request_booking(date, text, text) from public, anon;
grant execute on function public.request_booking(date, text, text) to authenticated;

-- 4) 노쇼 — 이제 스케줄 자체가 이미 1회를 쓰고 있으므로 따로 차감하지 않는다.
--    출석 기록에 '노쇼'로 남기는 역할만 한다.
create or replace function public.mark_noshow(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text; v_row record; v_day date;
begin
  v_role := coalesce(public.my_role(),'');
  if v_role not in ('admin','manager','master') then
    raise exception '권한이 없습니다.';
  end if;
  select * into v_row from public.schedules where id = p_id;
  if not found then return jsonb_build_object('ok',false,'msg','없는 수업이에요.'); end if;
  if v_role = 'admin' and v_row.teacher_id is distinct from auth.uid() then
    raise exception '담당 선생님만 처리할 수 있습니다.';
  end if;
  if v_row.student_id is null then
    return jsonb_build_object('ok',false,'msg','회원으로 등록된 학생이 아니에요.');
  end if;
  if v_row.ends_at > now() then
    return jsonb_build_object('ok',false,'msg','아직 끝나지 않은 수업이에요.');
  end if;

  v_day := (v_row.starts_at at time zone 'Asia/Seoul')::date;
  if exists (select 1 from public.attendance
              where student_id = v_row.student_id and attended_on = v_day) then
    return jsonb_build_object('ok',false,'msg','그날 이미 출석 기록이 있어요.');
  end if;

  insert into public.attendance(student_id, student_name, attended_on, admin_id, source)
  values (v_row.student_id, v_row.student_name, v_day, auth.uid(), 'noshow');

  return jsonb_build_object('ok',true,'msg','노쇼로 기록했습니다. 수업 횟수는 스케줄이 잡힐 때 이미 차감됐어요.');
end;
$$;

revoke all on function public.mark_noshow(bigint) from public, anon;
grant execute on function public.mark_noshow(bigint) to authenticated;

-- 5) 결제 안내(남은 1회) 시점을 '출석'에서 '스케줄'로 옮긴다
drop trigger if exists trg_payment_due on public.attendance;
drop trigger if exists trg_payment_due on public.schedules;
drop trigger if exists trg_payment_due_upd on public.schedules;

-- 수업을 새로 잡을 때
create trigger trg_payment_due
  after insert on public.schedules
  for each row
  when (new.student_id is not null
        and coalesce(new.status,'confirmed') = 'confirmed'
        and coalesce(new.source,'web') <> 'gcal')
  execute function public.enqueue_payment_due();

-- 학생 예약을 승인해서 확정으로 바뀔 때(그때 처음 차감된다)
create trigger trg_payment_due_upd
  after update of status on public.schedules
  for each row
  when (new.student_id is not null
        and coalesce(new.status,'confirmed') = 'confirmed'
        and coalesce(old.status,'confirmed') <> 'confirmed'
        and coalesce(new.source,'web') <> 'gcal')
  execute function public.enqueue_payment_due();

-- 6) 등원 키오스크(체크인) 삭제
--    인자 목록을 손으로 적으면 하나만 달라도 조용히 안 지워진다 → 이름으로 싹 지운다
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and (p.proname like 'kiosk\_%' or p.proname = 'set_kiosk_pin')
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end $$;

drop table if exists public.kiosk_devices;
drop table if exists public.kiosk_config;

-- 확인용 — 키오스크 함수가 0줄이어야 하고, 아래 4개는 남아 있어야 한다
select proname as 남은함수 from pg_proc
where proname in ('sessions_left','booking_left','request_booking','mark_noshow',
                  'kiosk_pair','kiosk_lookup','kiosk_mark','kiosk_today','kiosk_get_pin','set_kiosk_pin')
order by proname;
