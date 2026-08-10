-- 중복 가입 막기 (2026-08-10)
-- 원장 지적: '채채'(=강민채), 김효민, 이보민, 조상근이 두 번 가입돼 있다.
-- 원인은 카카오 로그인이다. OAuth 는 계정을 먼저 만들어 놓고 우리에게 넘기므로
-- "이미 가입한 사람인가"를 물어볼 시점이 없다. 게다가 카카오 닉네임이 그대로 이름이 되고
-- (강민채 → '채채') 이메일 동의를 안 하면 이메일도 비어서 이름·메일로는 못 잡는다.
--
-- 유일하게 믿을 수 있는 열쇠가 휴대폰 번호다. 그래서 필수정보 입력창에서
-- 번호를 저장할 때 "이미 다른 계정이 쓰는 번호"인지 확인한다.
-- 학생은 남의 프로필을 못 읽으므로(RLS) security definer 함수로 물어야 한다.
-- 번호 자체는 돌려주지 않고 true/false 만 준다.

create or replace function public.phone_taken(p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  d text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  n int;
begin
  if length(d) < 10 then
    return false;                      -- 번호 같지도 않은 값은 여기서 판단하지 않는다
  end if;
  select count(*) into n
  from public.profiles
  where id <> auth.uid()               -- 내 계정은 당연히 제외
    and regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') = d;
  return n > 0;
end;
$$;

revoke all on function public.phone_taken(text) from public, anon;
grant execute on function public.phone_taken(text) to authenticated;

-- 확인용: 지금 중복인 번호가 있는지 (원장님이 SQL Editor에서 돌려 보는 용도)
-- select regexp_replace(phone,'[^0-9]','','g') as d, count(*), string_agg(name,' / ')
-- from public.profiles
-- where length(regexp_replace(coalesce(phone,''),'[^0-9]','','g')) >= 10
-- group by 1 having count(*) > 1;
