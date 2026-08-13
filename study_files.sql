-- 주말 스터디 교재 첨부 (2026-08-13 원장 지시)
-- "스터디 각 회차마다 그날 쓸 교재를 첨부하고, 학생은 홈페이지에서 받아 쓰고,
--  다음 스터디가 열리기 전에 파일을 자동으로 소각한다." (원장 선택 A = 진짜 삭제)
--
-- 올리는 사람 : 원장(master) · 매니저(manager) · 선생님(admin)
-- 받는 사람   : 스터디 자격(profiles.study)이 켜진 수강중인 학생
-- 소각        : 스터디가 끝나는 그날 오후 2시(서울)에 파일 실체까지 삭제
--               → Edge Function 'study-gc' + pg_cron 이 담당 (이 파일 맨 아래 참고)
--               ⚠️ 2026-08-13 원장이 '다음 날 새벽' → '당일 14:00'으로 바꿈
--
-- Supabase > SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전합니다.

-- 1) 파일을 담을 비공개 버킷 --------------------------------------------------
-- public=false 라 주소를 알아도 못 연다. 오직 서명 링크(5분짜리)로만 열린다.
-- 한 파일 20MB 까지.
insert into storage.buckets (id, name, public, file_size_limit)
values ('study-files', 'study-files', false, 20971520)
on conflict (id) do update set public = false, file_size_limit = 20971520;

-- 2) 어느 회차 교재인지 적어 두는 표 ------------------------------------------
-- path = 버킷 안의 파일 위치, name = 학생에게 보여줄 원래 파일 이름.
create table if not exists public.study_files(
  id              bigserial primary key,
  study_date      date not null,
  path            text not null unique,
  name            text not null,
  size            bigint,
  created_by      uuid,
  created_by_name text,
  created_at      timestamptz not null default now()
);
create index if not exists study_files_date_idx on public.study_files(study_date);
alter table public.study_files enable row level security;

-- 3) 날짜 기준 ----------------------------------------------------------------
-- ⚠️ DB 시각은 UTC 라 current_date 를 그냥 쓰면 밤 9시 이후에 하루가 어긋난다.
--    "오늘"은 반드시 서울 기준으로 센다.
create or replace function public.kst_today()
returns date
language sql
stable
as $$ select (now() at time zone 'Asia/Seoul')::date $$;

-- 4) 교재를 받을 자격이 있는 사람인가 -----------------------------------------
-- ⚠️ coalesce 를 반드시 쓴다 — 비로그인이면 my_role() 이 NULL 이라 검사가 그냥 통과한다.
-- security definer 인 이유: 학생은 RLS 상 자기 profiles 행 밖을 못 읽어
-- 정책 안에서 직접 조회하면 자격이 있어도 false 가 나온다.
create or replace function public.study_file_ok()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.my_role(),'') in ('admin','manager','master')
      or exists(select 1 from public.profiles p
                 where p.id = auth.uid()
                   and p.study
                   and coalesce(p.status,'active') <> 'ended');
$$;
revoke all on function public.study_file_ok() from public, anon;
grant execute on function public.study_file_ok() to authenticated;

-- 5) 표 권한 ------------------------------------------------------------------
-- 학생은 '오늘 이후' 회차 것만 목록에 보인다(지난 회차는 어차피 소각된다).
-- 운영진·선생님은 지난 것도 보인다 — 소각 전까지 관리할 수 있어야 하므로.
drop policy if exists sf_read on public.study_files;
create policy sf_read on public.study_files for select to authenticated
using (
  public.study_file_ok()
  and (coalesce(public.my_role(),'') in ('admin','manager','master')
       or study_date >= public.kst_today())
);

-- 올리고 지우는 건 원장·매니저·선생님 (원장 지시 2026-08-13).
drop policy if exists sf_write on public.study_files;
create policy sf_write on public.study_files for all to authenticated
using      (coalesce(public.my_role(),'') in ('admin','manager','master'))
with check (coalesce(public.my_role(),'') in ('admin','manager','master'));

-- 6) 파일 실체(storage) 권한 ---------------------------------------------------
-- 표만 막아 두면 소용없다. 서명 링크를 만들려면 storage.objects 에 select 권한이 있어야 하므로
-- 같은 잣대를 파일 쪽에도 건다.
create or replace function public.study_file_readable(p text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.study_file_ok()
     and exists(select 1 from public.study_files f
                 where f.path = p
                   and (coalesce(public.my_role(),'') in ('admin','manager','master')
                        or f.study_date >= public.kst_today()));
$$;
revoke all on function public.study_file_readable(text) from public, anon;
grant execute on function public.study_file_readable(text) to authenticated;

drop policy if exists study_obj_ops on storage.objects;
create policy study_obj_ops on storage.objects for all to authenticated
using      (bucket_id = 'study-files' and coalesce(public.my_role(),'') in ('admin','manager','master'))
with check (bucket_id = 'study-files' and coalesce(public.my_role(),'') in ('admin','manager','master'));

drop policy if exists study_obj_read on storage.objects;
create policy study_obj_read on storage.objects for select to authenticated
using (bucket_id = 'study-files' and public.study_file_readable(name));

-- 7) 소각 대상 확인용 (Edge Function 이 쓰는 것과 같은 기준) --------------------
-- 끝난 회차 = study_date 가 서울 기준 오늘까지.
-- ⚠️ 오후 2시(스터디 끝나는 시각)에만 부르는 걸 전제로 오늘 것도 포함한다.
create or replace function public.study_files_expired()
returns table(id bigint, path text, study_date date)
language sql
stable
security definer
set search_path = public
as $$
  select f.id, f.path, f.study_date
  from public.study_files f
  where f.study_date <= public.kst_today()
  order by f.study_date;
$$;
revoke all on function public.study_files_expired() from public, anon;
grant execute on function public.study_files_expired() to authenticated;

-- 8) 자동 소각 예약 (pg_cron) --------------------------------------------------
-- ⚠️ cron 시각은 UTC 다. 05:00 UTC = 14:00 서울 (스터디 끝나는 시각).
-- ⚠️ study-gc 함수 안에도 SWEEP_HOUR=14 라는 같은 시각이 박혀 있다.
--    시각을 바꾸려면 **둘 다** 고쳐야 한다. 한쪽만 고치면 cron 이 불러도
--    함수가 그냥 넘어가 소각이 조용히 멈춘다.
-- 🔑 암호를 쓰지 않는다 — 함수가 서울 14시대에만 일하도록 잠겨 있어서,
--    남이 아무 때나 불러도 스터디 중에 교재가 사라지지 않는다.
create extension if not exists pg_net;

select cron.schedule(
  'study-file-gc-daily', '0 5 * * *',
  $cron$
  select net.http_post(
    url     := 'https://guaqfsuwrvqjffmbiwpw.supabase.co/functions/v1/study-gc',
    headers := jsonb_build_object('Content-Type','application/json'),
    body    := '{}'::jsonb
  );
  $cron$
);

-- 중단하려면:  select cron.unschedule('study-file-gc-daily');
-- 확인:        select jobname, schedule, active from cron.job where jobname like 'study%';

-- 확인용 (필요할 때만 따로 돌려 보세요)
-- select study_date, name, round(size/1024.0) as kb from public.study_files order by study_date desc;
-- select * from public.study_files_expired();
