-- 수업 결과(출석 · 결석 · 휴강) (2026-08-09 원장 지시)
--
-- 배경
--  · 등원 키오스크를 없앴다. 이제 아무도 체크인을 찍지 않는다.
--  · 그런데 선생님 평가의 '출석률'과 '등원 기록이 없어요' 알림이 아직
--    attendance(등원 기록)를 보고 있어서, 출석률은 전원 0%로 나오고
--    끝난 수업마다 가짜 노쇼 알림이 떴다.
--
-- 원장 결정
--  · 스케줄이 확정되면 그게 곧 출석이다. 선생님은 '안 온 경우'만 표시한다.
--    평소에는 아무것도 안 눌러도 된다.
--  · 결석(학생 사정)은 횟수를 차감한다. 휴강(학생 잘못이 아닌 경우)은 차감하지 않는다.
--  · 휴강하면 그 시간 강의장이 비어야 한다. 다른 선생님이 그 방을 쓸 수 있어야 한다.
--
-- schedules.status 4가지
--   pending   승인 대기      차감 X   출석률 제외   강의장 잡음
--   confirmed 확정 = 출석    차감 O   출석률 분자   강의장 잡음
--   noshow    결석           차감 O   출석률 분모   강의장 잡음(이미 지난 수업)
--   canceled  휴강           차감 X   출석률 제외   강의장 놓음 ← 여기가 핵심
--
-- attendance 표는 지우지 않는다. 예전 등원 기록이 남아 있어서 이력으로 본다.
-- mark_noshow 도 그대로 둔다(이제 화면에서 부르지 않는다).
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) status 에 들어올 수 있는 값을 4가지로 못 박는다.
--    이미 다른 값이 들어 있으면 제약을 걸지 않는다(스크립트 전체가 실패하면 안 되므로).
--    그때는 아래 확인용 쿼리의 '제약' 칸이 비어서 나온다.
do $$
begin
  if not exists (
    select 1 from public.schedules
     where coalesce(status,'confirmed') not in ('confirmed','pending','noshow','canceled')
  ) then
    alter table public.schedules drop constraint if exists schedules_status_check;
    alter table public.schedules add constraint schedules_status_check
      check (status in ('confirmed','pending','noshow','canceled'));
  end if;
end $$;

-- 2) 남은 횟수 — 결석도 차감한다(안 왔어도 그 자리는 쓴 것이므로).
--    휴강(canceled)과 승인 대기(pending)는 세지 않는다.
create or replace function public.sessions_left(p_student uuid)
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
                      and coalesce(source,'web') <> 'gcal'), 0);
$$;

revoke all on function public.sessions_left(uuid) from public, anon;
grant execute on function public.sessions_left(uuid) to authenticated;

-- 3) 강의장 겹침 검사 — 휴강한 수업은 그 방을 놓은 것으로 본다.
--    rooms_setup.sql 의 함수를 두 군데만 고쳐 다시 만든다.
--      (가) 겹침을 찾을 때 휴강 행은 건너뛴다  → 그 시간 그 방이 다시 열린다
--      (나) 휴강 행은 '대면은 강의장 필수' 검사에서 빼준다 → 강의장을 비울 수 있다
create or replace function public.check_room_conflict()
returns trigger
language plpgsql
as $$
declare
  c record;
  rname text;
  v_mode text;
  v_free int;
begin
  -- 휴강한 수업은 강의장을 잡고 있으면 안 된다. 검사 없이 통과시킨다.
  if coalesce(new.status,'confirmed') = 'canceled' then
    return new;
  end if;

  -- 강의장을 안 고른 수업 (원장 지시: 대면은 강의장 필수, 미배정은 비대면만)
  if new.room_id is null then
    -- 구글 캘린더에서 온 수업은 막지 않는다. 막으면 동기화가 통째로 멈춘다.
    if coalesce(new.source,'web') = 'gcal' then
      return new;
    end if;

    select lesson_mode into v_mode
      from public.profiles where id = new.student_id;

    if coalesce(v_mode,'offline') = 'online' then
      return new;
    end if;

    -- 학생이 보낸 예약 '요청'은 아직 강의장을 정할 단계가 아니다.
    -- 다만 그 시간에 빈 강의장이 아예 없으면 요청 자체를 받지 않는다.
    if coalesce(new.status,'confirmed') = 'pending' then
      select count(*) into v_free
      from public.rooms r
      where coalesce(r.active, true)
        and not exists (
          select 1 from public.schedules s
          where s.room_id = r.id
            and s.id is distinct from new.id
            and coalesce(s.status,'confirmed') <> 'canceled'
            and s.starts_at < new.ends_at
            and s.ends_at   > new.starts_at);
      if v_free = 0 then
        raise exception '그 시간에는 빈 강의장이 없습니다. 다른 시간을 골라주세요. (% ~ %)',
          to_char(new.starts_at at time zone 'Asia/Seoul','MM"월" DD"일" HH24:MI'),
          to_char(new.ends_at   at time zone 'Asia/Seoul','HH24:MI');
      end if;
      return new;
    end if;

    raise exception '대면 수업은 강의장을 정해야 합니다. 미배정으로 둘 수 있는 건 비대면 학생뿐입니다.';
  end if;

  select s.starts_at, s.ends_at,
         coalesce(s.teacher_name,'-') as tn,
         coalesce(s.student_name,'-') as sn
    into c
  from public.schedules s
  where s.room_id = new.room_id
    and s.id is distinct from new.id
    and coalesce(s.status,'confirmed') <> 'canceled'
    and s.starts_at < new.ends_at
    and s.ends_at   > new.starts_at
  limit 1;

  if not found then
    return new;
  end if;

  -- 구글 캘린더에서 넘어온 수업이 시간이 바뀌어 겹치게 된 경우:
  -- 여기서 막으면 동기화 전체가 실패하므로, 강의장만 비워서 '미배정'으로 되돌린다.
  if coalesce(new.source,'web') = 'gcal' then
    new.room_id := null;
    return new;
  end if;

  select name into rname from public.rooms where id = new.room_id;

  raise exception '%은(는) 그 시간에 이미 사용 중입니다. (% ~ % / % 선생님 · %)',
    coalesce(rname,'그 강의장'),
    to_char(c.starts_at at time zone 'Asia/Seoul','MM"월" DD"일" HH24:MI'),
    to_char(c.ends_at   at time zone 'Asia/Seoul','HH24:MI'),
    c.tn, c.sn;
end;
$$;

-- status 를 바꿀 때도 검사가 돌아야 한다(휴강 → 되살리기 때 방이 비었는지 봐야 하므로).
drop trigger if exists trg_room_conflict on public.schedules;
create trigger trg_room_conflict
  before insert or update of room_id, starts_at, ends_at, status
  on public.schedules
  for each row execute function public.check_room_conflict();

-- 4) 수업 결과 표시
--    원장·매니저는 전부, 선생님은 본인이 맡은 수업만.
--    결석은 끝난 수업에만(안 온 게 확정돼야 하므로), 휴강은 앞으로의 수업도 미리 찍을 수 있다.
--    휴강으로 바꾸면 강의장을 비운다 → 그 시간 그 방을 다른 선생님이 쓸 수 있다.
create or replace function public.set_lesson_result(p_id bigint, p_result text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_row  record;
  v_freed boolean := false;
begin
  v_role := coalesce(public.my_role(),'');
  if v_role not in ('admin','manager','master') then
    raise exception '권한이 없습니다.';
  end if;

  if p_result not in ('confirmed','noshow','canceled') then
    return jsonb_build_object('ok',false,'msg','알 수 없는 결과예요.');
  end if;

  select * into v_row from public.schedules where id = p_id;
  if not found then
    return jsonb_build_object('ok',false,'msg','없는 수업이에요.');
  end if;

  if v_role = 'admin' and v_row.teacher_id is distinct from auth.uid() then
    raise exception '담당 선생님만 처리할 수 있습니다.';
  end if;

  -- 승인 전 예약은 결과를 남길 게 없다. 먼저 승인하거나 거절해야 한다.
  if coalesce(v_row.status,'confirmed') = 'pending' then
    return jsonb_build_object('ok',false,'msg','아직 승인 전 예약이에요. 먼저 승인하거나 거절해주세요.');
  end if;

  -- 구글 캘린더에서 온 수업은 애초에 횟수를 세지 않는다.
  if coalesce(v_row.source,'web') = 'gcal' then
    return jsonb_build_object('ok',false,'msg','구글 캘린더에서 온 수업은 횟수를 세지 않아 결과를 남기지 않습니다.');
  end if;

  -- 결석은 끝난 수업에만. 휴강은 미리 정할 수 있어야 한다(그래야 강의장이 미리 열린다).
  if p_result = 'noshow' and v_row.ends_at > now() then
    return jsonb_build_object('ok',false,'msg','아직 끝나지 않은 수업이에요. 결석은 수업이 끝난 뒤에 표시할 수 있어요.');
  end if;

  if p_result = 'canceled' then
    -- 휴강 = 그 자리를 놓는 것. 강의장을 비워야 다른 선생님이 쓴다.
    v_freed := (v_row.room_id is not null);
    update public.schedules set status = p_result, room_id = null where id = p_id;
  else
    -- 되살리는 경우: 강의장은 비어 있는 채로 둔다. 트리거가 그 시간 그 방이
    -- 이미 찼는지 알 수 없으므로, 선생님이 직접 다시 고르게 하는 편이 안전하다.
    update public.schedules set status = p_result where id = p_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'result', p_result,
    'room_freed', v_freed,
    'left', case when v_row.student_id is null
                 then null
                 else public.sessions_left(v_row.student_id) end
  );
end;
$$;

revoke all on function public.set_lesson_result(bigint, text) from public, anon;
grant execute on function public.set_lesson_result(bigint, text) to authenticated;

-- 5) 학생 예약 화면에서도 휴강한 자리는 비어 보여야 한다.
--    teacher_off.sql 의 free_slots 를 그대로 두고 '휴강 제외' 조건만 넣어 다시 만든다.
create or replace function public.free_slots(p_date date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_teacher uuid;
  v_teacher_name text;
  v_room_count int;
  v_slots jsonb := '[]'::jsonb;
  v_hours int[] := array[10,13,15,17,19,21];   -- ↔ request_booking 검증 배열과 같아야 함
  h int; s_ts timestamptz; e_ts timestamptz;
  busy_teacher int; busy_rooms int; avail boolean; v_off boolean;
begin
  if v_uid is null then return jsonb_build_object('error','login'); end if;
  select teacher_id into v_teacher from public.profiles where id = v_uid;
  if v_teacher is null then return jsonb_build_object('error','no_teacher'); end if;
  select name into v_teacher_name from public.profiles where id = v_teacher;
  select count(*) into v_room_count from public.rooms;

  foreach h in array v_hours loop
    s_ts := (p_date::timestamp + make_interval(hours => h)) at time zone 'Asia/Seoul';
    e_ts := s_ts + interval '2 hours';
    select count(*) into busy_teacher from public.schedules
      where teacher_id = v_teacher
        and coalesce(status,'confirmed') <> 'canceled'
        and starts_at < e_ts and ends_at > s_ts;
    select count(distinct room_id) into busy_rooms from public.schedules
      where room_id is not null
        and coalesce(status,'confirmed') <> 'canceled'
        and starts_at < e_ts and ends_at > s_ts;
    v_off := public.is_off(v_teacher, s_ts, e_ts);
    avail := (busy_teacher = 0)
             and (v_room_count = 0 or busy_rooms < v_room_count)
             and (s_ts > now())
             and not v_off;
    v_slots := v_slots || jsonb_build_object(
      'start', lpad(h::text,2,'0')||':00',
      'end',   lpad((h+2)::text,2,'0')||':00',
      'available', avail,
      'off', v_off
    );
  end loop;

  return jsonb_build_object('teacher_name', v_teacher_name, 'slots', v_slots);
end;
$$;

revoke all on function public.free_slots(date) from public, anon;
grant execute on function public.free_slots(date) to authenticated;

-- 6) 예약 요청도 같은 기준으로 — 휴강한 자리는 비어 있는 것으로 본다.
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

  if public.is_off(v_teacher, s_ts, e_ts) then
    return jsonb_build_object('ok',false,'msg','그 시간은 휴무예요. 다른 날짜나 시간을 골라주세요.');
  end if;

  select count(*) into busy_teacher from public.schedules
    where teacher_id = v_teacher
      and coalesce(status,'confirmed') <> 'canceled'
      and starts_at < e_ts and ends_at > s_ts;
  if busy_teacher > 0 then return jsonb_build_object('ok',false,'msg','방금 그 시간이 찼어요. 다른 시간을 골라주세요.'); end if;

  if exists(select 1 from public.schedules
             where student_id = v_uid
               and coalesce(status,'confirmed') <> 'canceled'
               and starts_at < e_ts and ends_at > s_ts) then
    return jsonb_build_object('ok',false,'msg','이미 그 시간에 예약이 있어요.');
  end if;

  select r.id into v_room from public.rooms r
    where coalesce(r.active,true)
      and not exists (select 1 from public.schedules s
                       where s.room_id = r.id
                         and coalesce(s.status,'confirmed') <> 'canceled'
                         and s.starts_at < e_ts and s.ends_at > s_ts)
    order by r.id limit 1;

  insert into public.schedules(room_id, teacher_id, teacher_name, student_id, student_name, subject, starts_at, ends_at, memo, status)
    values (v_room, v_teacher, v_teacher_name, v_uid, v_student_name, coalesce(nullif(p_subject,''),'토익'), s_ts, e_ts, '학생 예약 요청', 'pending');

  return jsonb_build_object('ok',true,'msg','예약이 요청되었어요. 선생님 승인 후 확정됩니다.','left',public.booking_left(v_uid));
end;
$$;

revoke all on function public.request_booking(date, text, text) from public, anon;
grant execute on function public.request_booking(date, text, text) to authenticated;

-- 확인용 — 네 칸이 다 채워져 나와야 정상이다.
select
  (select conname from pg_constraint
    where conrelid = 'public.schedules'::regclass
      and conname = 'schedules_status_check')                       as 제약,
  (select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'set_lesson_result')  as 결과함수,
  (select string_agg(a.attname, ',' order by a.attnum)
     from pg_trigger t
     join unnest(t.tgattr) with ordinality u(attnum, ord) on true
     join pg_attribute a on a.attrelid = t.tgrelid and a.attnum = u.attnum
    where t.tgrelid = 'public.schedules'::regclass
      and t.tgname = 'trg_room_conflict')                           as 겹침검사_감시칸,
  (select count(*) from public.schedules
    where coalesce(status,'confirmed') = 'canceled'
      and room_id is not null)                                      as 강의장_안비워진_휴강;
