-- 구글 캘린더 수업도 결석·휴강을 찍을 수 있게 (2026-08-13 원장 지시)
--
-- 원장 지시 그대로
--  · "8월12일 오후2시 이후에 넘어온 수업만 출석율 체크되게 하면 되고"
--  · "이미 구글에서 넘어온 수업은 결석인지 출석인지 모르니 일단 전부 출석처리해놓으면 돼"
--  · "웹 스케줄에 표시되어 있는 것들, 만약 결석 나오면 결석처리 이창희 혹은 김태완이 직접 할 거야"
--
-- 왜 필요한가
--  원장님·이창희쌤 수업은 전부 구글에서 넘어온다. 그런데 지금은 구글발이라는 이유로
--  결과(결석·휴강) 버튼이 아예 막혀 있어서, 학생이 못 온다고 해도 그 시간 강의장을
--  놓을 방법이 없다. 다른 선생님이 빈 방을 못 쓴다.
--
-- 함정 — 10분마다 도는 동기화가 덮어쓴다
--  gcal-sync 는 구글 일정을 upsert 하면서 status 를 늘 'confirmed' 로 다시 넣는다.
--  그대로 두면 애써 찍은 결석이 다음 동기화에 지워지고 강의장도 되돌아온다.
--  그래서 '사람이 결과를 정한 행'에 표를 달고(result_locked),
--  동기화가 그 행을 건드릴 때는 status 와 room_id 를 그대로 두게 막는다.
--  동기화인지 아닌지는 gcal_synced_at 이 바뀌는지로 안다 — 그 칸은 동기화만 건드린다.
--
-- 회차(수업 횟수)는 한 줄도 바꾸지 않았다. 기준은 그대로 2026-08-12 14:00 이후 구글 수업.
--
-- 붙여넣는 법: SQL Editor 에서 Ctrl+A -> Delete -> 붙여넣기 -> 첫 줄이 -- 인지 확인 -> Run

-- 1) 사람이 정한 결과라는 표
alter table public.schedules add column if not exists result_locked boolean not null default false;

comment on column public.schedules.result_locked is
  '사람이 결석·휴강을 직접 정한 행. 구글 동기화가 덮어쓰지 못하게 막는 표(2026-08-13).';

-- 2) 동기화가 사람 결정을 덮어쓰지 못하게
create or replace function public.gcal_keep_result()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- gcal_synced_at 이 바뀌는 갱신 = 동기화가 쓰는 중
  if coalesce(old.source,'web') = 'gcal'
     and coalesce(old.result_locked,false)
     and new.gcal_synced_at is distinct from old.gcal_synced_at then
    new.status  := old.status;     -- 결석·휴강 유지
    new.room_id := old.room_id;    -- 놓은 강의장 그대로 (되돌아오면 안 된다)
    new.result_locked := true;
  end if;
  return new;
end;
$$;

-- 이름 순서가 곧 실행 순서다.
--   trg_gcal_fill_student(f) -> trg_gcal_keep_result(g) -> trg_room_conflict(r)
-- 방 겹침 검사가 맨 뒤에 와야 고쳐진 값으로 검사한다.
drop trigger if exists trg_gcal_keep_result on public.schedules;
create trigger trg_gcal_keep_result
  before update on public.schedules
  for each row execute function public.gcal_keep_result();

-- 3) 결과 남기기 — 구글발 차단을 '기준 시각 이전'으로만 좁힌다
create or replace function public.set_lesson_result(p_id bigint, p_result text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_role text := coalesce(public.my_role(),'');
  v_row  record;
  v_freed boolean := false;
begin
  if v_role not in ('admin','manager','master') then
    raise exception '권한이 없습니다.';
  end if;

  if p_result not in ('confirmed','noshow','canceled') then
    return jsonb_build_object('ok',false,'msg','알 수 없는 결과예요.');
  end if;

  select * into v_row from public.schedules where id = p_id;
  if not found then
    return jsonb_build_object('ok',false,'msg','없는 수업이에요.');
  end if;

  if v_role = 'admin' and v_row.teacher_id is distinct from auth.uid() then
    raise exception '담당 선생님만 처리할 수 있습니다.';
  end if;

  if coalesce(v_row.status,'confirmed') = 'pending' then
    return jsonb_build_object('ok',false,'msg','아직 승인 전 예약이에요. 먼저 승인하거나 거절해주세요.');
  end if;

  -- 2026-08-12 14:00 이전 구글 수업은 통통통 시절 기록이다.
  -- 회원 연결도 안 돼 있고 횟수도 그때 이미 깎였으므로 결과를 남기지 않는다.
  if coalesce(v_row.source,'web') = 'gcal'
     and not (v_row.starts_at > timestamptz '2026-08-12 14:00:00+09') then
    return jsonb_build_object('ok',false,'msg','2026년 8월 12일 오후 2시 이전에 잡힌 구글 수업은 결과를 남기지 않습니다.');
  end if;

  -- 결석은 학생이 회원으로 연결돼 있어야 뜻이 있다(깎을 횟수가 있어야 하므로).
  if p_result = 'noshow' and v_row.student_id is null then
    return jsonb_build_object('ok',false,'msg','학생이 회원으로 연결돼 있지 않아 결석 처리를 할 수 없어요. 수업 수정에서 학생을 골라주세요.');
  end if;

  if p_result in ('canceled','noshow') then
    -- 둘 다 그 자리를 놓는 것. 강의장을 비워야 다른 선생님이 쓴다.
    -- (차감 여부는 sessions_left 가 status 로 판단한다 — 결석은 차감, 휴강은 안 함)
    v_freed := (v_row.room_id is not null);
    update public.schedules
       set status = p_result, room_id = null, result_locked = true
     where id = p_id;
  else
    -- 되살리는 경우: 강의장은 비어 있는 채로 둔다. 그 사이 다른 사람이 잡았을 수 있으므로
    -- 서버가 함부로 복구하지 않고 선생님이 다시 고르게 한다.
    -- 표(result_locked)는 그대로 둔다 — 사람이 한 번 손댄 행이라는 뜻이라
    -- 동기화가 강의장을 되돌려 놓으면 안 되기 때문이다.
    update public.schedules
       set status = p_result, result_locked = true
     where id = p_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'result', p_result,
    'room_freed', v_freed,
    'left', case when v_row.student_id is null
                 then null
                 else public.sessions_left(v_row.student_id) end
  );
end;
$fn$;

revoke all on function public.set_lesson_result(bigint, text) from public, anon;
grant execute on function public.set_lesson_result(bigint, text) to authenticated;

-- 확인용
-- select (d like '%result_locked%') as 표달기,
--        (d like '%2026-08-12 14:00%') as 기준시각
--   from (select pg_get_functiondef(p.oid) d from pg_proc p
--           join pg_namespace n on n.oid=p.pronamespace
--          where n.nspname='public' and p.proname='set_lesson_result') t;
-- select tgname from pg_trigger where tgrelid='public.schedules'::regclass and not tgisinternal order by tgname;
