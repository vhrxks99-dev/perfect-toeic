-- 완토 데일리 토익 (알림톡 + 개인 링크 학습 페이지)  2026-11-19
-- 표 3개 + 손님용 함수 2개(로그인 없이 개인 토큰으로) + 관리용 함수.
-- 다시 돌려도 안전하게(if not exists / create or replace).


-- 1) 하루치 문제: product(rc/lc) × day_no(1,2,3…) → payload(jsonb, 학습 페이지가 그대로 씀)
create table if not exists public.daily_items (
  product   text not null check (product in ('rc','lc')),
  day_no    int  not null check (day_no > 0),
  payload   jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (product, day_no)
);

-- 2) 구매자(구독): 개인 링크 토큰, 이용 기간 1년
create table if not exists public.daily_subs (
  id         uuid primary key default gen_random_uuid(),
  token      text not null unique default replace(gen_random_uuid()::text, '-', ''),
  product    text not null check (product in ('rc','lc')),
  name       text not null,
  phone      text not null,
  start_date date not null,                       -- 첫 알림톡 날(평일)
  end_date   date not null,                       -- start_date + 1년
  amount     int  not null default 39990,
  paid_at    date,
  pay_method text,                                -- 결제선생 등
  status     text not null default 'active' check (status in ('active','refunded','ended')),
  memo       text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists daily_subs_phone on public.daily_subs(phone);

-- 3) 푼 기록: 날짜 × 파트(p5/p6/p7/wd)
create table if not exists public.daily_progress (
  sub_id   uuid not null references public.daily_subs(id) on delete cascade,
  day_date date not null,
  part     text not null check (part in ('p5','p6','p7','wd','lc')),
  score    int,
  total    int,
  done_at  timestamptz not null default now(),
  primary key (sub_id, day_date, part)
);

alter table public.daily_items    enable row level security;
alter table public.daily_subs     enable row level security;
alter table public.daily_progress enable row level security;

-- 원장·실장만 직접 보고 고침. 손님은 아래 함수로만.
drop policy if exists daily_items_staff on public.daily_items;
create policy daily_items_staff on public.daily_items for all
  using (public.my_role() in ('master','manager')) with check (public.my_role() in ('master','manager'));
drop policy if exists daily_subs_staff on public.daily_subs;
create policy daily_subs_staff on public.daily_subs for all
  using (public.my_role() in ('master','manager')) with check (public.my_role() in ('master','manager'));
drop policy if exists daily_progress_staff on public.daily_progress;
create policy daily_progress_staff on public.daily_progress for select
  using (public.my_role() in ('master','manager'));

-- 서울 날짜
create or replace function public.daily_kst_today() returns date
language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;

-- start_date 부터 d 까지 평일 수(시작일 = 1일째). 주말이면 그 직전 평일 기준.
create or replace function public.daily_day_no(p_start date, p_d date) returns int
language sql immutable as $$
  select count(*)::int from generate_series(p_start, p_d, interval '1 day') g
   where extract(isodow from g) < 6
$$;

-- 연속 일수: 오늘(안 끝났으면 어제)부터 거꾸로, 네 파트 다 끝낸 평일이 이어진 수
create or replace function public.daily_streak(p_sub uuid, p_parts int) returns int
language plpgsql stable security definer set search_path = public as $$
declare d date := daily_kst_today(); n int := 0; c int;
begin
  -- 오늘 다 못 했으면 어제부터 셈
  select count(*) into c from daily_progress where sub_id = p_sub and day_date = d;
  if c < p_parts then d := d - 1; end if;
  loop
    while extract(isodow from d) >= 6 loop d := d - 1; end loop;
    select count(*) into c from daily_progress where sub_id = p_sub and day_date = d;
    exit when c < p_parts;
    n := n + 1; d := d - 1;
  end loop;
  return n;
end $$;

-- 손님: 오늘의 문제 + 내 기록 (로그인 없이 토큰만)
create or replace function public.daily_today(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s daily_subs; d date := daily_kst_today(); dn int; mx int; it jsonb; wk boolean;
        parts int; prog jsonb;
begin
  select * into s from daily_subs where token = p_token;
  if not found then return jsonb_build_object('error','no_sub'); end if;
  if s.status <> 'active' then return jsonb_build_object('error','inactive','name',s.name); end if;
  if d < s.start_date then return jsonb_build_object('error','not_started','name',s.name,'start_date',s.start_date); end if;
  if d > s.end_date then return jsonb_build_object('error','expired','name',s.name,'end_date',s.end_date); end if;
  wk := extract(isodow from d) >= 6;
  dn := greatest(daily_day_no(s.start_date, d), 1);
  select max(day_no) into mx from daily_items where product = s.product;
  if mx is null then return jsonb_build_object('error','no_items','name',s.name); end if;
  select payload into it from daily_items where product = s.product and day_no = ((dn - 1) % mx) + 1;
  parts := case when s.product = 'rc' then 4 else 2 end;
  select coalesce(jsonb_object_agg(part, jsonb_build_object('score',score,'total',total)), '{}'::jsonb)
    into prog from daily_progress where sub_id = s.id and day_date = d;
  return jsonb_build_object('name', s.name, 'product', s.product, 'date', d, 'weekend', wk,
    'day_no', dn, 'items', it, 'progress', prog, 'streak', daily_streak(s.id, parts),
    'end_date', s.end_date);
end $$;

-- 손님: 한 파트 끝냄 기록 (오늘 날짜로만, 주말 복습은 기록 안 함)
create or replace function public.daily_mark(p_token text, p_part text, p_score int, p_total int) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare s daily_subs; d date := daily_kst_today(); parts int;
begin
  select * into s from daily_subs where token = p_token and status = 'active';
  if not found then return jsonb_build_object('error','no_sub'); end if;
  if d < s.start_date or d > s.end_date then return jsonb_build_object('error','out_of_range'); end if;
  if extract(isodow from d) >= 6 then return jsonb_build_object('ok', true, 'weekend', true); end if;
  if p_part not in ('p5','p6','p7','wd','lc') then return jsonb_build_object('error','bad_part'); end if;
  insert into daily_progress(sub_id, day_date, part, score, total)
  values (s.id, d, p_part, p_score, p_total)
  on conflict (sub_id, day_date, part) do update set score = excluded.score, total = excluded.total, done_at = now();
  parts := case when s.product = 'rc' then 4 else 2 end;
  return jsonb_build_object('ok', true, 'streak', daily_streak(s.id, parts));
end $$;

revoke all on function public.daily_today(text) from public;
revoke all on function public.daily_mark(text, text, int, int) from public;
grant execute on function public.daily_today(text) to anon, authenticated;
grant execute on function public.daily_mark(text, text, int, int) to anon, authenticated;
revoke all on function public.daily_streak(uuid, int) from public, anon;

-- 관리: 이번 달 매일 다 푼 사람(환급 후보) 보기
create or replace view public.daily_month_report with (security_invoker = true) as
select s.id, s.name, s.phone, s.product, date_trunc('month', p.day_date)::date as month,
       count(distinct p.day_date) filter (where p.cnt >= case when s.product='rc' then 4 else 2 end) as full_days
  from public.daily_subs s
  join (select sub_id, day_date, count(*) cnt from public.daily_progress group by 1,2) p on p.sub_id = s.id
 group by 1,2,3,4,5;
