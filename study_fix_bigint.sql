-- 🚨 급한 수정 (2026-08-10) — 이걸 돌리기 전까지 수업 등록이 통째로 막힙니다.
--
-- 무엇이 잘못됐나
--   study.sql 에서 study_busy 를 `p_room int` 로 만들었는데, schedules.room_id 와
--   rooms.id 는 bigint 다. 겹침 차단 트리거가 new.room_id(bigint)를 넘기면
--   `function public.study_busy(bigint, ...) does not exist` 가 나면서
--   **스터디와 상관없는 시간의 수업까지 전부 거절**된다.
--
-- 고치는 법: 함수를 bigint 로 다시 만들고 옛 int 판을 지운다.
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.

-- 1) 옛 int 판 제거 (트리거가 이 이름을 부르므로 먼저 만들고 나중에 지운다)
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

drop function if exists public.study_busy(int, timestamptz, timestamptz);

-- 2) study_rooms.room_id 도 타입을 맞춘다 (rooms.id 가 bigint)
do $$
begin
  if exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='study_rooms'
      and column_name='room_id' and data_type='integer')
  then
    alter table public.study_rooms drop constraint if exists study_rooms_room_id_fkey;
    alter table public.study_rooms alter column room_id type bigint;
    alter table public.study_rooms
      add constraint study_rooms_room_id_fkey foreign key (room_id)
      references public.rooms(id) on delete cascade;
  end if;
end $$;

-- 3) 잘 고쳐졌는지 (이 줄만 결과가 보입니다 — true 두 개면 정상)
select
  exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='study_busy'
           and pg_get_function_identity_arguments(p.oid) like 'bigint%') as "bigint판_있음",
  not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='study_busy'
           and pg_get_function_identity_arguments(p.oid) like 'integer%') as "int판_없음";
