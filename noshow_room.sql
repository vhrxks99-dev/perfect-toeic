-- 결석도 강의장을 놓는다 (2026-08-13 원장 지시)
--
-- 원장 말: "학생이 결석하는 거라 차감은 하고 강의장은 쓰게 해야 하는데,
--           지금은 '휴강 · 차감 없고 강의장이 열립니다' 밖에 없다."
-- 즉 **차감 O + 강의장 열림** 조합이 없었다. 그걸 결석에 붙인다.
--
--   status      뜻      차감   출석률      강의장
--   pending     승인대기  X    제외        잡음
--   confirmed   출석     O    분자        잡음
--   noshow      결석     O    분모만      놓음  ← 2026-08-13 바뀜(전에는 잡고 있었다)
--   canceled    휴강     X    제외        놓음
--
-- 🚨 같이 고친 것: **라이브 check_room_conflict 에 휴강 예외가 사라져 있었다.**
--    study.sql(08-10)이 lesson_result.sql(08-09)보다 나중에 돌면서 덮어썼다.
--    (2026-08-13 확인: 함수 본문에 'canceled' 없음 / 'study_busy'만 있음)
--    그래서 대면 학생은 휴강을 눌러도 '대면 수업은 강의장을 정해야 합니다'로 막혔다.
--    이 파일의 check_room_conflict 는 **세 가지를 한꺼번에** 담는다:
--      (가) 스터디가 쓰는 방 막기   (study.sql 것)
--      (나) 휴강은 방을 놓음        (lesson_result.sql 것)
--      (다) 결석도 방을 놓음        (이번에 추가)
--    ⚠️ 앞으로 rooms_setup.sql / study.sql / lesson_result.sql 중 하나를 다시 돌리면
--       나머지 규칙이 또 사라진다. 그때는 이 파일을 마지막에 한 번 더 돌릴 것.
--
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.

-- 1) 강의장 겹침 검사 -----------------------------------------------------------
create or replace function public.check_room_conflict()
returns trigger
language plpgsql
as $fn$
declare
  c record;
  rname text;
  v_mode text;
  v_free int;
begin
  -- 휴강·결석한 수업은 강의장을 잡고 있으면 안 된다. 검사 없이 통과시킨다.
  if coalesce(new.status,'confirmed') in ('canceled','noshow') then
    return new;
  end if;

  if new.room_id is null then
    -- 구글 캘린더에서 온 수업은 막지 않는다. 막으면 동기화가 통째로 멈춘다.
    if coalesce(new.source,'web') = 'gcal' then
      return new;
    end if;

    select lesson_mode into v_mode from public.profiles where id = new.student_id;
    if coalesce(v_mode,'offline') = 'online' then
      return new;
    end if;

    -- 학생이 보낸 예약 '요청'은 아직 강의장을 정할 단계가 아니다.
    -- 다만 그 시간에 빈 강의장이 아예 없으면 요청 자체를 받지 않는다.
    if coalesce(new.status,'confirmed') = 'pending' then
      select count(*) into v_free
      from public.rooms r
      where coalesce(r.active, true)
        and not public.study_busy(r.id, new.starts_at, new.ends_at)
        and not exists (
          select 1 from public.schedules s
          where s.room_id = r.id
            and s.id is distinct from new.id
            and coalesce(s.status,'confirmed') not in ('canceled','noshow')
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

  -- 주말 스터디가 그 방을 쓰는 시간이면 수업을 못 넣는다.
  if public.study_busy(new.room_id, new.starts_at, new.ends_at) then
    if coalesce(new.source,'web') = 'gcal' then
      new.room_id := null;
      return new;
    end if;
    select name into rname from public.rooms where id = new.room_id;
    raise exception '%은(는) 그 시간에 주말 스터디가 씁니다. (12:00~14:00) 다른 강의장이나 시간을 골라주세요.',
      coalesce(rname,'그 강의장');
  end if;

  select s.starts_at, s.ends_at,
         coalesce(s.teacher_name,'-') as tn,
         coalesce(s.student_name,'-') as sn
    into c
  from public.schedules s
  where s.room_id = new.room_id
    and s.id is distinct from new.id
    and coalesce(s.status,'confirmed') not in ('canceled','noshow')
    and s.starts_at < new.ends_at
    and s.ends_at   > new.starts_at
  limit 1;

  if not found then
    return new;
  end if;

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
$fn$;

-- status 를 바꿀 때도 검사가 돌아야 한다(되살릴 때 방이 비었는지 봐야 하므로).
drop trigger if exists trg_room_conflict on public.schedules;
create trigger trg_room_conflict
  before insert or update of room_id, starts_at, ends_at, status
  on public.schedules
  for each row execute function public.check_room_conflict();

-- 2) 수업 결과 표시 -------------------------------------------------------------
-- 바뀐 곳 두 군데:
--   · 결석을 '끝난 수업에만' 이라고 막던 줄을 뺐다 → 오늘 못 온다고 미리 연락 오면 그때 찍는다.
--   · 결석도 휴강처럼 강의장을 비운다 → 그 시간 그 방을 다른 선생님이 쓴다.
create or replace function public.set_lesson_result(p_id bigint, p_result text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_role text := coalesce(public.my_role(),'');
  v_row  record;
  v_freed boolean := false;
begin
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

  if coalesce(v_row.status,'confirmed') = 'pending' then
    return jsonb_build_object('ok',false,'msg','아직 승인 전 예약이에요. 먼저 승인하거나 거절해주세요.');
  end if;

  if coalesce(v_row.source,'web') = 'gcal' then
    return jsonb_build_object('ok',false,'msg','구글 캘린더에서 온 수업은 횟수를 세지 않아 결과를 남기지 않습니다.');
  end if;

  -- 결석은 학생이 회원으로 연결돼 있어야 뜻이 있다(깎을 횟수가 있어야 하므로).
  if p_result = 'noshow' and v_row.student_id is null then
    return jsonb_build_object('ok',false,'msg','학생이 회원으로 연결돼 있지 않아 결석 처리를 할 수 없어요. 수업 수정에서 학생을 골라주세요.');
  end if;

  if p_result in ('canceled','noshow') then
    -- 둘 다 그 자리를 놓는 것. 강의장을 비워야 다른 선생님이 쓴다.
    -- (차감 여부는 sessions_left 가 status 로 판단한다 — 결석은 차감, 휴강은 안 함)
    v_freed := (v_row.room_id is not null);
    update public.schedules set status = p_result, room_id = null where id = p_id;
  else
    -- 되살리는 경우: 강의장은 비어 있는 채로 둔다. 그 사이 다른 사람이 잡았을 수 있으므로
    -- 서버가 함부로 복구하지 않고 선생님이 다시 고르게 한다.
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
$fn$;

revoke all on function public.set_lesson_result(bigint, text) from public, anon;
grant execute on function public.set_lesson_result(bigint, text) to authenticated;

-- 3) 학생 예약 화면 — 결석한 자리도 비어 보여야 한다 ----------------------------
create or replace function public.free_slots(p_date date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
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
        and coalesce(status,'confirmed') not in ('canceled','noshow')
        and starts_at < e_ts and ends_at > s_ts;
    select count(distinct room_id) into busy_rooms from public.schedules
      where room_id is not null
        and coalesce(status,'confirmed') not in ('canceled','noshow')
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
$fn$;

revoke all on function public.free_slots(date) from public, anon;
grant execute on function public.free_slots(date) to authenticated;

-- 4) 예약 요청도 같은 기준으로 ---------------------------------------------------
create or replace function public.request_booking(p_date date, p_start text, p_subject text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
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
      and coalesce(status,'confirmed') not in ('canceled','noshow')
      and starts_at < e_ts and ends_at > s_ts;
  if busy_teacher > 0 then return jsonb_build_object('ok',false,'msg','방금 그 시간이 찼어요. 다른 시간을 골라주세요.'); end if;

  if exists(select 1 from public.schedules
             where student_id = v_uid
               and coalesce(status,'confirmed') not in ('canceled','noshow')
               and starts_at < e_ts and ends_at > s_ts) then
    return jsonb_build_object('ok',false,'msg','이미 그 시간에 예약이 있어요.');
  end if;

  select r.id into v_room from public.rooms r
    where coalesce(r.active,true)
      and not public.study_busy(r.id, s_ts, e_ts)
      and not exists (select 1 from public.schedules s
                       where s.room_id = r.id
                         and coalesce(s.status,'confirmed') not in ('canceled','noshow')
                         and s.starts_at < e_ts and s.ends_at > s_ts)
    order by r.id limit 1;

  insert into public.schedules(room_id, teacher_id, teacher_name, student_id, student_name, subject, starts_at, ends_at, memo, status)
    values (v_room, v_teacher, v_teacher_name, v_uid, v_student_name, coalesce(nullif(p_subject,''),'토익'), s_ts, e_ts, '학생 예약 요청', 'pending');

  return jsonb_build_object('ok',true,'msg','예약이 요청되었어요. 선생님 승인 후 확정됩니다.','left',public.booking_left(v_uid));
end;
$fn$;

revoke all on function public.request_booking(date, text, text) from public, anon;
grant execute on function public.request_booking(date, text, text) to authenticated;

-- 확인용 — 세 칸이 다 true 여야 정상이다.
-- select (d like '%canceled%') as 휴강, (d like '%noshow%') as 결석, (d like '%study_busy%') as 스터디
-- from (select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--        where n.nspname='public' and p.proname='check_room_conflict') t;
