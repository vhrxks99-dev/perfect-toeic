-- 주말 스터디 강의장 자동 배분 (2026-08-13 원장 지시)
-- "참석 인원을 방마다 인원 맞춰 나누되, 점수대가 골고루 섞이게 해달라."
--
-- ⚠️ 원장 지시: 여기 쓰는 실력값은 **어림값이라 회원 페이지 점수 칸에 적지 않는다.**
--    그래서 profiles.current_score 를 건드리지 않고 study_levels 라는 별도 표에 둔다.
--    이 값은 원장·매니저·선생님만 보고, 학생 화면에는 절대 안 나온다.
--
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.

-- 1) 배분 결과를 적어 둘 칸 ---------------------------------------------------
-- room_name 은 스냅샷이다(강의장 이름이 바뀌어도 그날 배분 표시가 흔들리지 않게,
-- 그리고 학생이 rooms 표를 못 읽어도 방 이름을 볼 수 있게).
alter table public.study_signups
  add column if not exists room_id   bigint references public.rooms(id) on delete set null,
  add column if not exists room_name text;

-- 2) 배분용 실력값 -------------------------------------------------------------
create table if not exists public.study_levels(
  student_id uuid primary key references public.profiles(id) on delete cascade,
  level      int not null,
  note       text,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table public.study_levels enable row level security;

-- 학생에게는 통째로 안 보인다 — 어림값이라 학생이 보면 오해한다(원장 지시).
drop policy if exists sl_ops on public.study_levels;
create policy sl_ops on public.study_levels for all to authenticated
  using      (coalesce(public.my_role(),'') in ('admin','manager','master'))
  with check (coalesce(public.my_role(),'') in ('admin','manager','master'));

-- 3) 배분 저장 함수 ------------------------------------------------------------
-- 화면에서 계산한 결과를 한 번에 적용한다.
-- ⚠️ study_signups 의 update RLS 는 원장·매니저까지만 허용한다 → 선생님도 배분할 수
--    있어야 하므로 security definer 함수로 우회한다.
-- ⚠️ 먼저 그날 배분을 전부 비운다. 안 그러면 참석을 취소한 학생이 옛 방에 남는다.
create or replace function public.study_assign_rooms(p_date date, p_map jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_role text := coalesce(public.my_role(),'');
  n int := 0;
  rec record;
begin
  if v_role not in ('admin','manager','master') then
    raise exception '권한이 없습니다.';
  end if;

  update public.study_signups
     set room_id = null, room_name = null
   where study_date = p_date;

  for rec in
    select (e->>'student_id')::uuid as sid, (e->>'room_id')::bigint as rid
    from jsonb_array_elements(coalesce(p_map,'[]'::jsonb)) e
  loop
    update public.study_signups s
       set room_id   = rec.rid,
           room_name = (select r.name from public.rooms r where r.id = rec.rid)
     where s.study_date = p_date
       and s.student_id = rec.sid;
    n := n + 1;
  end loop;

  return n;
end;
$fn$;
revoke all on function public.study_assign_rooms(date, jsonb) from public, anon;
grant execute on function public.study_assign_rooms(date, jsonb) to authenticated;

-- 4) 원장이 알려준 어림 실력값 (2026-08-13) ------------------------------------
-- ⚠️ 이름으로 맞춘다 — 동명이인이 있으면 엉뚱한 사람에게 들어간다.
--    그래서 '스터디 자격이 켜진 수강중 학생'으로 좁힌다.
--    이예은은 원장이 "없음"이라 해서 넣지 않는다(배분 때 중간값으로 취급).
insert into public.study_levels(student_id, level, note)
select p.id, v.lv, '원장 어림값 2026-08-13'
from (values
  ('강민채',720),('김유준',820),('마승우',620),('유재인',710),('윤성빈',720),
  ('이보민',720),('임현진',720),('정은비',560),('조예린',550),
  ('이인혁',735),('정지원',660)          -- 이 둘은 회원 페이지에 있는 실제 점수
) v(nm, lv)
join public.profiles p
  on p.name = v.nm and p.role = 'student' and p.study and coalesce(p.status,'active') <> 'ended'
on conflict (student_id) do update
  set level = excluded.level, note = excluded.note, updated_at = now();

-- 확인용 (필요할 때만 따로 돌려 보세요)
-- select p.name, l.level from public.study_levels l join public.profiles p on p.id=l.student_id order by l.level desc;
-- select student_name, room_name from public.study_signups where study_date='2026-08-15' order by room_name, student_name;
