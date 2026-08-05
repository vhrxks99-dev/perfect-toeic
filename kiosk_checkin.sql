-- =====================================================================
--  등원관리 (아이패드 키오스크)
--  Supabase > SQL Editor 에 이 파일 전체를 붙여넣고 [Run] 하세요.
--  (여러 번 실행해도 안전합니다)
--
--  하는 일:
--   학원에 둔 아이패드에서 학생이 휴대폰 뒷번호 4자리를 누르면
--   등원/하원이 기록되고, 등원할 때마다 횟수권이 1회 차감된다.
--
--  보안 구조 (키오스크는 '로그인하지 않은' 화면이라 특별히 신경 씀):
--   1. 아이패드는 최초 1회 관리자 PIN을 넣어 '기기 등록'을 한다.
--      → 긴 무작위 토큰을 받아 그 기기에만 저장한다.
--   2. 이후 모든 요청은 토큰이 있어야 통한다. 토큰이 없으면 학생 이름조차 안 나온다.
--   3. PIN을 무작정 대입하는 걸 막으려고 5번 틀리면 10분 잠긴다.
--   4. 표(테이블)에는 아무도 직접 접근 못 하고, 아래 함수를 통해서만 오간다.
-- =====================================================================

-- ─────────────────────────────────────────────
-- 1) 출석표에 등원/하원 시각 칸 추가
--    ※ 기존 계산(출석 횟수 = 출석표의 줄 수)을 그대로 두려고
--       하원은 새 줄을 만들지 않고 같은 줄에 시각만 적는다.
--       그래서 하원은 횟수를 차감하지 않는다.
-- ─────────────────────────────────────────────
alter table public.attendance
  add column if not exists checked_in_at  timestamptz,
  add column if not exists checked_out_at timestamptz,
  add column if not exists source         text;

-- 같은 날 두 번 차감되는 것은 아래 kiosk_mark 함수가 막는다.
-- (표 자체에 '하루 1줄' 제약을 걸면, 예전에 손으로 두 번 눌러 둔 기록이 있을 때
--  이 SQL 전체가 실패해 버리므로 걸지 않았다.)
-- 예전 중복이 있는지 보려면 아래 줄만 따로 실행:
-- select student_name, attended_on, count(*) from public.attendance
--  group by 1,2 having count(*) > 1 order by 2 desc;

-- ─────────────────────────────────────────────
-- 2) 키오스크 설정 (PIN 1개만 저장하는 표)
-- ─────────────────────────────────────────────
create table if not exists public.kiosk_config (
  id            int primary key default 1 check (id = 1),
  pin           text not null default '0000',
  fail_count    int  not null default 0,
  locked_until  timestamptz,
  updated_at    timestamptz not null default now()
);
insert into public.kiosk_config(id) values (1) on conflict (id) do nothing;

alter table public.kiosk_config enable row level security;
-- 정책을 하나도 만들지 않는다 = 아무도 직접 못 읽고 못 쓴다. 오직 아래 함수로만.
revoke all on public.kiosk_config from anon, authenticated;

-- ─────────────────────────────────────────────
-- 3) 등록된 키오스크 기기 목록
-- ─────────────────────────────────────────────
create table if not exists public.kiosk_devices (
  token        text primary key,
  label        text,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz
);

alter table public.kiosk_devices enable row level security;
drop policy if exists kiosk_dev_ops on public.kiosk_devices;
create policy kiosk_dev_ops on public.kiosk_devices for all to authenticated
  using      (coalesce(public.my_role(),'') in ('master','manager'))
  with check (coalesce(public.my_role(),'') in ('master','manager'));
grant select, delete on public.kiosk_devices to authenticated;

-- ─────────────────────────────────────────────
-- 4) 기기 등록 — 관리자 PIN을 확인하고 토큰을 발급한다 (아이패드에서 1회)
-- ─────────────────────────────────────────────
create or replace function public.kiosk_pair(pin text, label text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg public.kiosk_config;
  tok text;
begin
  select * into cfg from public.kiosk_config where id = 1 for update;

  if cfg.locked_until is not null and cfg.locked_until > now() then
    raise exception 'PIN을 여러 번 틀려 잠겼습니다. 잠시 후 다시 시도해 주세요.';
  end if;

  if cfg.pin is distinct from btrim(coalesce(kiosk_pair.pin,'')) then
    update public.kiosk_config
       set fail_count   = fail_count + 1,
           locked_until = case when fail_count + 1 >= 5 then now() + interval '10 minutes' else locked_until end
     where id = 1;
    raise exception 'PIN이 올바르지 않습니다.';
  end if;

  update public.kiosk_config set fail_count = 0, locked_until = null where id = 1;

  tok := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  insert into public.kiosk_devices(token, label, last_seen_at)
  values (tok, nullif(btrim(coalesce(kiosk_pair.label,'')),''), now());
  return tok;
end;
$$;

revoke all on function public.kiosk_pair(text, text) from public;
grant execute on function public.kiosk_pair(text, text) to anon, authenticated;

-- ─────────────────────────────────────────────
-- 5) 토큰 확인 (내부용)
-- ─────────────────────────────────────────────
create or replace function public.kiosk_touch(tok text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  update public.kiosk_devices set last_seen_at = now()
   where token = tok and length(coalesce(tok,'')) >= 32;
  get diagnostics n = row_count;
  return coalesce(n,0) > 0;
end;
$$;

revoke all on function public.kiosk_touch(text) from public;

-- ─────────────────────────────────────────────
-- 6) 뒷번호 4자리로 학생 찾기
--    같은 뒷자리가 여럿이면 여러 명이 나온다 (화면에서 고르게 함)
--    remaining = 구매한 횟수 합계 − 출석한 횟수. 0회 아래로 내려가면 음수가 그대로 보인다.
-- ─────────────────────────────────────────────
create or replace function public.kiosk_lookup(tok text, last4 text)
returns table(
  sid       uuid,
  sname     text,
  remaining int,
  is_in     boolean,
  is_out    boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.kiosk_touch(tok) then
    raise exception '등록되지 않은 기기입니다. 관리자 PIN으로 다시 등록해 주세요.';
  end if;
  if btrim(coalesce(last4,'')) !~ '^[0-9]{4}$' then
    raise exception '뒷번호 4자리를 눌러 주세요.';
  end if;

  return query
  select p.id,
         p.name,
         (coalesce((select sum(pay.sessions) from public.payments pay where pay.student_id = p.id), 0)
          - (select count(*) from public.attendance a where a.student_id = p.id))::int,
         exists(select 1 from public.attendance a where a.student_id = p.id and a.attended_on = current_date),
         exists(select 1 from public.attendance a where a.student_id = p.id and a.attended_on = current_date and a.checked_out_at is not null)
    from public.profiles p
   where p.role = 'student'
     and coalesce(p.status,'active') <> 'ended'
     and regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g') <> ''
     and right(regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g'), 4) = btrim(last4)
   order by p.name;
end;
$$;

revoke all on function public.kiosk_lookup(text, text) from public;
grant execute on function public.kiosk_lookup(text, text) to anon, authenticated;

-- ─────────────────────────────────────────────
-- 7) 등원 / 하원 처리
--    등원(in)  : 오늘 기록이 없으면 만든다 → 횟수 1회 차감
--    하원(out) : 오늘 기록에 나간 시각만 적는다 → 차감 없음
-- ─────────────────────────────────────────────
create or replace function public.kiosk_mark(tok text, student uuid, kind text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  nm     text;
  rem    int;
  again  boolean := false;
  tstamp timestamptz := now();
begin
  if not public.kiosk_touch(tok) then
    raise exception '등록되지 않은 기기입니다. 관리자 PIN으로 다시 등록해 주세요.';
  end if;
  if kind not in ('in','out') then
    raise exception '알 수 없는 요청입니다: %', kind;
  end if;

  select p.name into nm
    from public.profiles p
   where p.id = student and p.role = 'student';
  if nm is null then
    raise exception '학생을 찾을 수 없습니다.';
  end if;

  if kind = 'in' then
    if exists(select 1 from public.attendance a where a.student_id = student and a.attended_on = current_date) then
      again := true;   -- 이미 등원함. 두 번 차감하지 않는다.
      select a.checked_in_at into tstamp from public.attendance a
       where a.student_id = student and a.attended_on = current_date;
      tstamp := coalesce(tstamp, now());
    else
      insert into public.attendance(student_id, student_name, attended_on, checked_in_at, source)
      values (student, nm, current_date, now(), 'kiosk');
    end if;
  else
    if not exists(select 1 from public.attendance a where a.student_id = student and a.attended_on = current_date) then
      raise exception '오늘 등원 기록이 없습니다. 먼저 등원을 눌러 주세요.';
    end if;
    update public.attendance
       set checked_out_at = now()
     where student_id = student and attended_on = current_date;
  end if;

  select (coalesce((select sum(pay.sessions) from public.payments pay where pay.student_id = student), 0)
          - (select count(*) from public.attendance a where a.student_id = student))::int
    into rem;

  return json_build_object(
    'name', nm,
    'kind', kind,
    'at', to_char(tstamp at time zone 'Asia/Seoul', 'HH24:MI'),
    'remaining', rem,
    'already', again
  );
end;
$$;

revoke all on function public.kiosk_mark(text, uuid, text) from public;
grant execute on function public.kiosk_mark(text, uuid, text) to anon, authenticated;

-- ─────────────────────────────────────────────
-- 8) 오늘 등원 현황 (아이패드의 '출석이력보기')
-- ─────────────────────────────────────────────
create or replace function public.kiosk_today(tok text)
returns table(sname text, in_at text, out_at text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.kiosk_touch(tok) then
    raise exception '등록되지 않은 기기입니다.';
  end if;
  return query
  select a.student_name,
         to_char(a.checked_in_at  at time zone 'Asia/Seoul', 'HH24:MI'),
         to_char(a.checked_out_at at time zone 'Asia/Seoul', 'HH24:MI')
    from public.attendance a
   where a.attended_on = current_date
   order by a.checked_in_at desc nulls last, a.created_at desc;
end;
$$;

revoke all on function public.kiosk_today(text) from public;
grant execute on function public.kiosk_today(text) to anon, authenticated;

-- ─────────────────────────────────────────────
-- 9) 원장님용 — PIN 확인 / 변경
-- ─────────────────────────────────────────────
create or replace function public.kiosk_get_pin()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v text;
begin
  if coalesce(public.my_role(),'') <> 'master' then
    raise exception '원장님만 볼 수 있습니다.';
  end if;
  select pin into v from public.kiosk_config where id = 1;
  return v;
end;
$$;

revoke all on function public.kiosk_get_pin() from public;
grant execute on function public.kiosk_get_pin() to authenticated;

create or replace function public.set_kiosk_pin(new_pin text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v text := btrim(coalesce(new_pin,''));
begin
  if coalesce(public.my_role(),'') <> 'master' then
    raise exception '원장님만 변경할 수 있습니다.';
  end if;
  if v !~ '^[0-9]{4,8}$' then
    raise exception 'PIN은 숫자 4~8자리로 정해 주세요.';
  end if;
  update public.kiosk_config
     set pin = v, fail_count = 0, locked_until = null, updated_at = now()
   where id = 1;
end;
$$;

revoke all on function public.set_kiosk_pin(text) from public;
grant execute on function public.set_kiosk_pin(text) to authenticated;

-- ─────────────────────────────────────────────
-- 10) 확인용
-- ─────────────────────────────────────────────
-- select pin from public.kiosk_config;                 -- 현재 PIN (기본 0000)
-- select label, created_at, last_seen_at from public.kiosk_devices;   -- 등록된 아이패드
