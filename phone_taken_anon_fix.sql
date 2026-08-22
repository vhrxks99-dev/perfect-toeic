-- 2026-08-22  중복 가입 막기
-- 원래 phone_taken 은 where id <> auth.uid() 로 '내 계정 제외'를 했는데,
-- 가입 중인 사람은 로그인 전이라 auth.uid() 가 NULL 이고 NULL 비교는 참이 안 되므로
-- 아무 행도 안 잡혀서 늘 false 가 나왔다. 게다가 anon 에게 실행 권한이 없어
-- 비로그인 호출은 401 이 났고, 클라이언트가 그 오류를 삼켜서 그냥 통과했다.
create or replace function public.phone_taken(p_phone text)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  d text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  n int;
begin
  if length(d) < 10 then
    return false;
  end if;
  select count(*) into n
    from public.profiles
   where (auth.uid() is null or id <> auth.uid())
     and regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') = d;
  return n > 0;
end;
$function$;

grant execute on function public.phone_taken(text) to anon, authenticated;
