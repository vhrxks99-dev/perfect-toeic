-- 선생님 휴무 · 학원 휴무 (2026-08-08 원장 지시)
--
-- 원장 결정
--  · 반복(매주 O요일)은 필요 없다. 날짜를 하나씩 찍는다.
--  · 학원 전체가 쉬는 날도 넣을 수 있어야 한다 → teacher_id 가 NULL 이면 전원 휴무다.
--  · 종일 또는 몇 시~몇 시로 지정한다.
--
-- 휴무를 '수업 일정'으로 넣지 않는 이유: 그러면 스케줄표·강의장 배정·정산·회차에
-- 수업인 척 섞여 들어간다(실제로 '휴가' 일정이 강의장 배정 대상이 됐었다).
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) 휴무 표
create table if not exists public.teacher_off (
  id          bigint generated always as identity primary key,
  teacher_id  uuid references auth.users(id) on delete cascade,   -- NULL = 학원 전체 휴무
  off_date    date not null,
  all_day     boolean not null default true,
  start_hour  int,
  end_hour    int,
  reason      text,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- 종일이 아니면 시작·종료가 있어야 하고, 시작이 종료보다 빨라야 한다
alter table public.teacher_off drop constraint if exists teacher_off_hours_check;
alter table public.teacher_off add constraint teacher_off_hours_check
  check (
    all_day
    or (start_hour is not null and end_hour is not null
        and start_hour >= 0 and end_hour <= 24 and start_hour < end_hour)
  );

create index if not exists teacher_off_date_idx on public.teacher_off(off_date, teacher_id);

alter table public.teacher_off enable row level security;

-- 2) 권한
--    보기 = 로그인한 사람 전부(학생 예약 화면에서 '휴무'라고 알려줄 수 있어야 한다)
--    넣기·지우기 = 원장·매니저는 전부, 선생님은 본인 것만. 학원 전체 휴무는 원장·매니저만.
drop policy if exists off_sel on public.teacher_off;
create policy off_sel on public.teacher_off for select to authenticated using (true);

drop policy if exists off_ins on public.teacher_off;
create policy off_ins on public.teacher_off for insert to authenticated
  with check (
    coalesce(public.my_role(),'') in ('master','manager')
    or (coalesce(public.my_role(),'') = 'admin' and teacher_id = auth.uid())
  );

drop policy if exists off_del on public.teacher_off;
create policy off_del on public.teacher_off for delete to authenticated
  using (
    coalesce(public.my_role(),'') in ('master','manager')
    or (coalesce(public.my_role(),'') = 'admin' and teacher_id = auth.uid())
  );

grant select, insert, delete on public.teacher_off to authenticated;

-- 3) 이 시간에 쉬는가
create or replace function public.is_off(p_teacher uuid, s_ts timestamptz, e_ts timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.teacher_off o
    where (o.teacher_id is null or o.teacher_id = p_teacher)
      and o.off_date = (s_ts at time zone 'Asia/Seoul')::date
      and (
        o.all_day
        or (
              ((o.off_date::timestamp + make_interval(hours => o.start_hour)) at time zone 'Asia/Seoul') < e_ts
          and ((o.off_date::timestamp + make_interval(hours => o.end_hour))   at time zone 'Asia/Seoul') > s_ts
        )
      )
  );
$$;

revoke all on function public.is_off(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.is_off(uuid, timestamptz, timestamptz) to authenticated;

-- 4) 예약 가능 시간에서 휴무를 뺀다
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
      where teacher_id = v_teacher and starts_at < e_ts and ends_at > s_ts;
    select count(distinct room_id) into busy_rooms from public.schedules
      where room_id is not null and starts_at < e_ts and ends_at > s_ts;
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

-- 5) 예약 요청도 서버에서 한 번 더 막는다 (화면만 막으면 우회할 수 있다)
--    나머지 규칙은 sessions_by_schedule.sql 버전과 같다.
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

-- 확인용 — 정책 3개(off_sel/off_ins/off_del)가 나와야 한다
select policyname as 정책, cmd as 동작
from pg_policies
where schemaname = 'public' and tablename = 'teacher_off'
order by policyname;
