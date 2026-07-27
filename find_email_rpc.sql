-- 이메일(아이디) 찾기용 보안 함수
-- 이름 + 휴대폰(숫자만 비교)이 일치하면, 마스킹된 이메일을 돌려줍니다.
-- security definer 라 RLS 를 우회해 profiles 를 조회하지만, 전체 이메일은 절대 노출하지 않고
-- 앞 2글자 + *** 형태로만 반환합니다.

create or replace function public.find_email(p_name text, p_phone text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_local text;
begin
  select email into v_email
  from profiles
  where lower(btrim(name)) = lower(btrim(p_name))
    and regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g')
      = regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g')
    and regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g') <> ''
    and email is not null and email <> ''
  order by created_at asc nulls last
  limit 1;

  if v_email is null then
    return null;
  end if;

  v_local := split_part(v_email, '@', 1);

  -- 앞 2글자만 노출, 나머지는 * 처리 (짧으면 1글자만 노출)
  if length(v_local) > 2 then
    return left(v_local, 2) || repeat('*', length(v_local) - 2) || '@' || split_part(v_email, '@', 2);
  else
    return left(v_local, 1) || repeat('*', greatest(length(v_local) - 1, 1)) || '@' || split_part(v_email, '@', 2);
  end if;
end;
$$;

grant execute on function public.find_email(text, text) to anon, authenticated;
