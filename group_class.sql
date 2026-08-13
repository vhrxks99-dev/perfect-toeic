-- 2:1 합반 수업 — 같은 방·같은 시간에 학생별로 한 줄씩 (2026-08-13 원장 선택 A)
--
-- 왜: schedules 는 수업 한 건에 학생 한 명만 담는다. 그래서 '다은예린' 처럼 이름을
--     붙여 놓으면 회원과 연결이 안 되고 수업 횟수도 안 깎인다.
--     → 학생마다 한 줄씩 잡는다. 차감·출석·결석·숙제가 전부 학생별로 저절로 맞는다.
--
-- 그러려면 겹침 검사가 '같은 방·같은 시간 두 건'을 허용해야 한다.
-- 합반으로 보는 조건(셋 다 맞아야 한다):
--   · 같은 강의장
--   · 시작·끝 시각이 완전히 같음   ← 조금이라도 어긋나면 그냥 겹친 것이다
--   · 같은 선생님                  ← 다른 선생님이면 실수로 겹쳐 잡은 것이다
-- 그리고 그 방 정원을 넘으면 막는다(강의장 A 4인 / B 6인 / C 4인).
--
-- ⚠️ 이 파일은 check_room_conflict 를 다시 만든다. 그 함수에는 규칙이 네 개 들어 있다:
--    스터디 검사 / 휴강 / 결석 / 합반. rooms_setup·study·lesson_result·noshow_room 중
--    하나를 다시 돌리면 나머지가 사라지니, 그때는 이 파일을 마지막에 한 번 더 돌릴 것.
--
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.

create or replace function public.check_room_conflict()
returns trigger
language plpgsql
as $fn$
declare
  c record;
  rname text;
  v_mode text;
  v_free int;
  v_same int;
  v_cap  int;
begin
  -- 휴강·결석한 수업은 강의장을 잡고 있으면 안 된다. 검사 없이 통과시킨다.
  if coalesce(new.status,'confirmed') in ('canceled','noshow') then
    return new;
  end if;

  if new.room_id is null then
    if coalesce(new.source,'web') = 'gcal' then
      return new;
    end if;

    select lesson_mode into v_mode from public.profiles where id = new.student_id;
    if coalesce(v_mode,'offline') = 'online' then
      return new;
    end if;

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

  -- ★ 합반(2:1) — 같은 방·같은 시각·같은 선생님이면 한 수업을 나눠 적은 것으로 본다.
  --   정원까지는 허용하고, 넘으면 막는다.
  select count(*) into v_same
  from public.schedules s
  where s.room_id = new.room_id
    and s.id is distinct from new.id
    and coalesce(s.status,'confirmed') not in ('canceled','noshow')
    and s.starts_at = new.starts_at
    and s.ends_at   = new.ends_at
    and s.teacher_id is not distinct from new.teacher_id;

  if v_same > 0 then
    select capacity, name into v_cap, rname from public.rooms where id = new.room_id;
    if (v_same + 1) > coalesce(v_cap, 99) then
      raise exception '%은(는) 정원이 %명입니다. 그 시간에 이미 %명이 잡혀 있어요.',
        coalesce(rname,'그 강의장'), coalesce(v_cap,0), v_same;
    end if;
    return new;              -- 합반으로 인정
  end if;

  -- 여기서부터는 진짜 겹침. 합반 조건에 맞는 행은 위에서 걸러졌으므로 제외하고 찾는다.
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
    and not (s.starts_at = new.starts_at
             and s.ends_at = new.ends_at
             and s.teacher_id is not distinct from new.teacher_id)
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

drop trigger if exists trg_room_conflict on public.schedules;
create trigger trg_room_conflict
  before insert or update of room_id, starts_at, ends_at, status
  on public.schedules
  for each row execute function public.check_room_conflict();

-- 확인용 — 네 칸이 다 true 여야 정상이다.
-- select (d like '%canceled%') as 휴강, (d like '%noshow%') as 결석,
--        (d like '%study_busy%') as 스터디, (d like '%v_same%') as 합반
-- from (select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--        where n.nspname='public' and p.proname='check_room_conflict') t;
