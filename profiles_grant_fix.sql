-- =====================================================================
--  회원 정보 저장 실패 수정 (permission denied for table profiles)
--  원인: 2026-08-05에 추가한 goal_period(목표 기간) 칸이
--        authenticated 의 update 허용 목록에 빠져 있었음.
--        (2026-07 보안 작업 때 role 칸을 막으면서 칸 목록을 지정했는데,
--         그 뒤에 새로 생긴 칸이 목록에 안 들어감)
--  Supabase > SQL Editor 에 전체 붙여넣고 [Run]
-- =====================================================================

-- 1) 지금 수정 가능한 칸 확인
select string_agg(column_name, ', ' order by column_name) as "고치기전_수정가능한_칸"
from information_schema.column_privileges
where table_schema = 'public' and table_name = 'profiles'
  and grantee = 'authenticated' and privilege_type = 'UPDATE';

-- 2) 빠진 칸에 수정 권한 부여
--    ※ role(권한) 과 pay_rate(배분율) 은 일부러 제외 — 전용 함수로만 변경.
--    ※ teacher_id / status / lesson_mode / end_reason / ended_at 도 제외 —
--      security definer 함수(set_teacher 등)가 처리하므로 권한 불필요.
grant update (
  name, phone, birth, gender, interest,
  current_score, goal_score, route, marketing, goal_period
) on public.profiles to authenticated;

-- 3) 결과 확인 — goal_period 가 목록에 보이면 성공
select string_agg(column_name, ', ' order by column_name) as "고친후_수정가능한_칸"
from information_schema.column_privileges
where table_schema = 'public' and table_name = 'profiles'
  and grantee = 'authenticated' and privilege_type = 'UPDATE';
