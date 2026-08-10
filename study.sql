-- 주말 스터디 (2026-08-10 원장 확정)
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.
--
-- 규칙 (원장 답변: 가1 / 토일 둘다 / 다2)
--  1) 스터디 참여 자격은 원장님·선생님이 회원 관리에서 켜고 끈다. 학생이 스스로 못 켠다.
--  2) 토요일·일요일 12:00~14:00 고정.
--  3) 토익 시험이 있는 날은 스터디를 쉰다 → study_off 에 날짜를 넣어 둔다.
--  4) 참여 자격이 있는 학생이 '그 주에 갈 사람'만 따로 손을 든다(study_signups).
--  5) 강의장은 그날 인원 보고 사람이 1~2개 고른다(study_rooms).
--
-- ⚠️ 스터디는 schedules 에 넣지 않는다.
--    남은 수업 횟수 = 구매 + 조정 − 확정 스케줄 수 이므로, 스케줄에 넣으면
--    학생들끼리 하는 스터디 때문에 수업 횟수가 깎인다.

-- 1) 참여 자격 --------------------------------------------------------------
alter table public.profiles add column if not exists study boolean not null default false;
-- 새 칸을 추가하면 authenticated update 권한도 같이 줘야 한다.
-- (단 study 는 학생이 스스로 못 바꿔야 하므로 grant 하지 않고 아래 RPC 로만 바꾼다)

-- 2) 스터디 쉬는 날 (토익 시험일 등) -----------------------------------------
create table if not exists public.study_off(
  off_date   date primary key,
  reason     text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.study_off enable row level security;
drop policy if exists study_off_read on public.study_off;
create policy study_off_read on public.study_off for select to authenticated using (true);
drop policy if exists study_off_write on public.study_off;
create policy study_off_write on public.study_off for all to authenticated
  using (coalesce(public.my_role(),'') in ('master','manager'))
  with check (coalesce(public.my_role(),'') in ('master','manager'));

-- 3) 그 주에 가겠다고 손든 기록 ----------------------------------------------
-- going: true=참석 false=불참. 행이 아예 없으면 '아직 안 찍음(미응답)'.
-- 원장 지시(2026-08-10): "매주 스터디 전까지 참불 투표도 하게 해야 해."
-- 안 찍은 사람과 불참을 구분해야 인원 파악이 된다.
create table if not exists public.study_signups(
  id           bigserial primary key,
  student_id   uuid not null references public.profiles(id) on delete cascade,
  student_name text,
  study_date   date not null,
  going        boolean not null default true,
  created_at   timestamptz not null default now(),
  unique(student_id, study_date)
);
alter table public.study_signups add column if not exists going boolean not null default true;
create index if not exists study_signups_date_idx on public.study_signups(study_date);
alter table public.study_signups enable row level security;

-- 학생은 본인 것만, 선생님·운영진은 전부 본다.
drop policy if exists study_su_read on public.study_signups;
create policy study_su_read on public.study_signups for select to authenticated
  using (student_id = auth.uid() or coalesce(public.my_role(),'') in ('admin','manager','master'));
-- 넣고 빼는 건 본인(자격이 있을 때만) 또는 운영진.
drop policy if exists study_su_ins on public.study_signups;
create policy study_su_ins on public.study_signups for insert to authenticated
  with check (
    (student_id = auth.uid() and exists(select 1 from public.profiles p where p.id = auth.uid() and p.study))
    or coalesce(public.my_role(),'') in ('manager','master'));
drop policy if exists study_su_del on public.study_signups;
create policy study_su_del on public.study_signups for delete to authenticated
  using (student_id = auth.uid() or coalesce(public.my_role(),'') in ('manager','master'));
-- 참↔불 전환은 update 다(행을 지웠다 넣으면 미응답과 헷갈린다).
drop policy if exists study_su_upd on public.study_signups;
create policy study_su_upd on public.study_signups for update to authenticated
  using (student_id = auth.uid() or coalesce(public.my_role(),'') in ('manager','master'))
  with check (student_id = auth.uid() or coalesce(public.my_role(),'') in ('manager','master'));

-- 4) 그날 쓰는 강의장 (1~2개) ------------------------------------------------
create table if not exists public.study_rooms(
  study_date date not null,
  room_id    bigint not null references public.rooms(id) on delete cascade,   -- rooms.id 가 bigint
  primary key(study_date, room_id)
);
alter table public.study_rooms enable row level security;
drop policy if exists study_rm_read on public.study_rooms;
create policy study_rm_read on public.study_rooms for select to authenticated using (true);
drop policy if exists study_rm_write on public.study_rooms;
create policy study_rm_write on public.study_rooms for all to authenticated
  using (coalesce(public.my_role(),'') in ('master','manager'))
  with check (coalesce(public.my_role(),'') in ('master','manager'));

-- 5) 참여 자격 켜고 끄기 ------------------------------------------------------
-- 원장·매니저는 아무나, 선생님은 본인 담당 학생만.
-- ⚠️ coalesce 를 반드시 쓴다 — 비로그인이면 my_role() 이 NULL 이라 'not in' 이 NULL 이 되어
--    IF 가 false 로 떨어지고 검사를 그냥 통과해 버린다(2026-08-05 에 겪은 함정).
create or replace function public.set_study(target uuid, on_off boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_role text := coalesce(public.my_role(),'');
begin
  if v_role in ('master','manager') then
    null;
  elsif v_role = 'admin' then
    if not public.is_my_student(target) then
      raise exception '담당 학생만 바꿀 수 있습니다.';
    end if;
  else
    raise exception '권한이 없습니다.';
  end if;
  update public.profiles set study = coalesce(on_off,false) where id = target;
end;
$$;
revoke all on function public.set_study(uuid, boolean) from public, anon;
grant execute on function public.set_study(uuid, boolean) to authenticated;

-- 6) 이번(다가오는) 주말 스터디 한눈에 보기 -----------------------------------
-- p_date 가 속한 주의 토·일을 돌려준다. 쉬는 날이면 off=true.
create or replace function public.study_weekend(p_date date)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with d as (
    -- 월요일을 주의 시작으로 본다. 토 = +5, 일 = +6
    select (p_date - ((extract(isodow from p_date)::int) - 1))::date as mon
  ),
  days as (
    select (mon + 5)::date as day from d
    union all
    select (mon + 6)::date from d
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'day',  day,
           'off',  exists(select 1 from public.study_off o where o.off_date = day),
           'reason', (select o.reason from public.study_off o where o.off_date = day),
           'rooms', coalesce((select jsonb_agg(r.room_id order by r.room_id)
                              from public.study_rooms r where r.study_date = day), '[]'::jsonb),
           -- n = 참석, no = 불참, todo = 아직 안 찍은 사람(자격자 중)
           'n',    (select count(*) from public.study_signups s where s.study_date = day and s.going),
           'no',   (select count(*) from public.study_signups s where s.study_date = day and not s.going),
           'todo', greatest(0,
                     (select count(*) from public.profiles p where p.role='student' and p.study
                        and coalesce(p.status,'active') <> 'ended')
                   - (select count(*) from public.study_signups s where s.study_date = day)),
           -- mine: 'yes' / 'no' / null(아직 안 찍음)
           'mine', (select case when s.going then 'yes' else 'no' end
                      from public.study_signups s
                     where s.study_date = day and s.student_id = auth.uid())
         ) order by day), '[]'::jsonb)
  from days;
$$;
revoke all on function public.study_weekend(date) from public, anon;
grant execute on function public.study_weekend(date) to authenticated;

-- 7) 2026년 남은 토익 시험일 미리 넣기 ---------------------------------------
-- 출처: exam.toeic.co.kr 시험일정 (2026-08-10에 읽어 옴). 원장 지시 "저 날에는 스터디 없어".
-- 이미 있는 날짜는 건드리지 않는다(사유를 손으로 고쳐 뒀을 수 있으므로).
-- ⚠️ 공식 페이지에는 2026년 12월까지만 나와 있다. 2027년 일정은 나오면 그때 넣어야 한다.
insert into public.study_off(off_date, reason) values
  ('2026-08-23','토익 제576회'),
  ('2026-08-30','토익 제577회'),
  ('2026-09-06','토익 제578회'),
  ('2026-09-20','토익 제579회'),
  ('2026-10-11','토익 제580회'),
  ('2026-10-31','토익 제581회'),   -- 이 회차만 토요일
  ('2026-11-15','토익 제582회'),
  ('2026-11-29','토익 제583회'),
  ('2026-12-13','토익 제584회'),
  ('2026-12-27','토익 제585회')
on conflict (off_date) do nothing;

-- 8) 스터디가 강의장을 잡고 있으면 그 시간에 수업을 못 넣게 --------------------
-- 원장 지시(2026-08-10): "스터디는 학원 A·B강의장을 우선 쓴다. 그 시간대에 스터디가
-- 잡혀 있다면 수업은 못 잡게 해야 한다."
-- 스터디 시간은 그 날짜의 12:00~14:00 (Asia/Seoul) 고정.
-- ⚠️ p_room 은 반드시 bigint — rooms.id·schedules.room_id 가 bigint 라
--    int 로 만들면 트리거가 함수를 못 찾아 수업 등록이 통째로 막힌다(2026-08-10에 겪음).
create or replace function public.study_busy(p_room bigint, p_start timestamptz, p_end timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.study_rooms r
    where r.room_id = p_room
      and not exists(select 1 from public.study_off o where o.off_date = r.study_date)
      and p_start < ((r.study_date::timestamp + time '14:00') at time zone 'Asia/Seoul')
      and p_end   > ((r.study_date::timestamp + time '12:00') at time zone 'Asia/Seoul')
  );
$$;
revoke all on function public.study_busy(bigint, timestamptz, timestamptz) from public, anon;
grant execute on function public.study_busy(bigint, timestamptz, timestamptz) to authenticated;

-- 겹침 차단 트리거를 다시 만든다. 기존 로직(rooms_setup.sql)에 스터디 검사만 더했다.
-- ⚠️ rooms_setup.sql 을 나중에 다시 돌리면 이 함수가 예전 것으로 덮인다 → 그때는 study.sql 을 다시 돌릴 것.
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
  if new.room_id is null then
    if coalesce(new.source,'web') = 'gcal' then
      return new;
    end if;

    select lesson_mode into v_mode from public.profiles where id = new.student_id;
    if coalesce(v_mode,'offline') = 'online' then
      return new;
    end if;

    if coalesce(new.status,'confirmed') = 'pending' then
      -- 빈 강의장 세기 — 스터디가 잡고 있는 방도 '찬 방'으로 본다.
      select count(*) into v_free
      from public.rooms r
      where coalesce(r.active, true)
        and not public.study_busy(r.id, new.starts_at, new.ends_at)
        and not exists (
          select 1 from public.schedules s
          where s.room_id = r.id
            and s.id is distinct from new.id
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

  -- ★ 스터디가 그 방을 쓰는 시간이면 수업을 못 넣는다.
  if public.study_busy(new.room_id, new.starts_at, new.ends_at) then
    -- 구글 캘린더발은 막으면 동기화가 통째로 멈추므로 강의장만 비운다(기존 정책과 동일).
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
$$;

drop trigger if exists trg_room_conflict on public.schedules;
create trigger trg_room_conflict
  before insert or update of room_id, starts_at, ends_at
  on public.schedules
  for each row execute function public.check_room_conflict();

-- 반대 방향도 막는다: 이미 수업이 잡힌 방을 스터디 방으로 지정하려 할 때.
create or replace function public.check_study_room()
returns trigger
language plpgsql
as $$
declare c record; rname text;
begin
  select s.starts_at, s.ends_at, coalesce(s.student_name,'-') as sn into c
  from public.schedules s
  where s.room_id = new.room_id
    and s.starts_at < ((new.study_date::timestamp + time '14:00') at time zone 'Asia/Seoul')
    and s.ends_at   > ((new.study_date::timestamp + time '12:00') at time zone 'Asia/Seoul')
  limit 1;
  if found then
    select name into rname from public.rooms where id = new.room_id;
    raise exception '%은(는) 그 시간에 이미 수업이 있습니다. (% ~ % · %) 먼저 수업을 옮겨주세요.',
      coalesce(rname,'그 강의장'),
      to_char(c.starts_at at time zone 'Asia/Seoul','MM"월" DD"일" HH24:MI'),
      to_char(c.ends_at   at time zone 'Asia/Seoul','HH24:MI'), c.sn;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_study_room on public.study_rooms;
create trigger trg_study_room
  before insert or update on public.study_rooms
  for each row execute function public.check_study_room();

-- 확인용 (필요할 때만 따로 돌려 보세요)
-- select name, study from public.profiles where role='student' and study order by name;
-- select * from public.study_off order by off_date;
