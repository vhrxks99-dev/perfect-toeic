-- ============================================================
-- 학생 수업 예약 (선생님 승인제, 2시간 단위, 이름 비노출)
-- Supabase SQL Editor 에 붙여넣고 RUN 하세요.
-- ============================================================

-- 1) schedules 에 상태 컬럼 추가 (pending=승인대기 / confirmed=확정)
alter table public.schedules add column if not exists status text not null default 'confirmed';
update public.schedules set status='confirmed' where status is null;

-- 2) 빈 슬롯 조회 (현재 로그인 학생의 담당 선생님 기준, 이름은 절대 반환 안 함)
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
  v_hours int[] := array[10,12,14,16,18,20];
  h int; s_ts timestamptz; e_ts timestamptz;
  busy_teacher int; busy_rooms int; avail boolean;
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
    avail := (busy_teacher = 0)
             and (v_room_count = 0 or busy_rooms < v_room_count)
             and (s_ts > now());
    v_slots := v_slots || jsonb_build_object(
      'start', lpad(h::text,2,'0')||':00',
      'end',   lpad((h+2)::text,2,'0')||':00',
      'available', avail
    );
  end loop;

  return jsonb_build_object('teacher_name', v_teacher_name, 'slots', v_slots);
end;
$$;
grant execute on function public.free_slots(date) to authenticated;

-- 3) 예약 요청 (pending 생성) — 서버에서 충돌·시간대 재검증
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
begin
  if v_uid is null then return jsonb_build_object('ok',false,'msg','로그인이 필요해요.'); end if;
  select teacher_id, name into v_teacher, v_student_name from public.profiles where id = v_uid;
  if v_teacher is null then return jsonb_build_object('ok',false,'msg','담당 선생님 배정 후 이용할 수 있어요.'); end if;
  if p_start !~ '^[0-9]{2}:00$' then return jsonb_build_object('ok',false,'msg','잘못된 시간이에요.'); end if;
  h := split_part(p_start,':',1)::int;
  if h <> all (array[10,12,14,16,18,20]) then return jsonb_build_object('ok',false,'msg','예약 가능한 시간이 아니에요.'); end if;
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
    where not exists (select 1 from public.schedules s where s.room_id = r.id and s.starts_at < e_ts and s.ends_at > s_ts)
    order by r.id limit 1;
  insert into public.schedules(room_id, teacher_id, teacher_name, student_id, student_name, subject, starts_at, ends_at, memo, status)
    values (v_room, v_teacher, v_teacher_name, v_uid, v_student_name, coalesce(nullif(p_subject,''),'토익'), s_ts, e_ts, '학생 예약 요청', 'pending');
  return jsonb_build_object('ok',true,'msg','예약이 요청되었어요. 선생님 승인 후 확정됩니다.');
end;
$$;
grant execute on function public.request_booking(date, text, text) to authenticated;

-- 4) 학생이 본인의 '승인대기' 예약을 취소(삭제)할 수 있게
drop policy if exists "sched_student_cancel" on public.schedules;
create policy "sched_student_cancel" on public.schedules for delete
  using (student_id = auth.uid() and status = 'pending');
