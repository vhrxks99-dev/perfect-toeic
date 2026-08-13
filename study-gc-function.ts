// ============================================================
// 주말 스터디 교재 자동 소각 (2026-08-13 원장 지시 · 선택 A = 진짜 삭제)
// Supabase Dashboard > Edge Functions > study-gc > Code 에 붙여넣고 Deploy.
//
// 하는 일: 스터디가 끝난 회차의 교재 파일을 버킷에서 실제로 지우고 표에서도 뺀다.
//          하루 한 번 **서울 오후 2시**(스터디 끝나는 시각) pg_cron 이 부른다.
//          ⚠️ 2026-08-13 원장 지시로 '다음 날 새벽' → '당일 2시'로 바꿈.
//          그래서 오늘 것까지 지운다(lte).
//
// 🔑 암호(x-sync-secret)를 쓰지 않는다. 대신 **시간 자물쇠**로 잠근다.
//    이유: cron 쪽 SQL 에 암호를 적어 넣어야 하는데, 그 SQL 을 자동으로 넣는 것이
//    막혀 있어 원장님이 손으로 붙여넣어야 했다. 암호를 없애는 편이 안전하기도 하다 —
//    이 함수는 서울 14시대(14:00~14:59)에만 일하므로, 남이 아무 때나 불러도
//    스터디 중(12~14시)에 교재가 사라지지 않는다. 14시대에 남이 부른들
//    cron 이 어차피 할 일과 똑같다. 응답에도 파일 이름을 담지 않는다(개수만).
//
// ⚠️ 시각을 바꾸려면 여기 SWEEP_HOUR 와 cron 시각을 **둘 다** 고쳐야 한다.
//    한쪽만 고치면 cron 이 불러도 함수가 그냥 넘어가 소각이 조용히 멈춘다.
// ⚠️ 'Verify JWT with legacy secret' 은 꺼 둔다(gcal-sync 와 동일).
//
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 는 자동 주입된다. 따로 넣을 Secret 없음.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BUCKET = "study-files";
const SWEEP_HOUR = 14; // 서울 기준. 스터디가 12:00~14:00 이라 끝나는 시각.

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// 서울 시각. DB·서버는 UTC 라 그대로 쓰면 날짜가 하루 어긋난다.
function kstNow(): Date {
  return new Date(Date.now() + 9 * 60 * 60 * 1000);
}
function kstToday(): string {
  return kstNow().toISOString().slice(0, 10);
}

async function sweep() {
  const today = kstToday();

  // 끝난 회차 교재 = 스터디 날짜가 오늘까지인 것.
  const { data, error } = await db
    .from("study_files")
    .select("id,path")
    .lte("study_date", today);
  if (error) throw new Error("목록 조회 실패: " + error.message);

  const rows = data ?? [];
  if (!rows.length) return { today, deleted: 0 };

  // 1) 파일 실체를 먼저 지운다.
  const rm = await db.storage.from(BUCKET).remove(rows.map((r) => r.path as string));
  if (rm.error) throw new Error("파일 삭제 실패: " + rm.error.message);

  // 2) 표에서 뺀다. 여기서 실패해도 다음 날 다시 시도된다
  //    (이미 없는 파일을 remove 해도 오류가 아니다).
  const del = await db.from("study_files").delete().in("id", rows.map((r) => r.id));
  if (del.error) throw new Error("표 정리 실패: " + del.error.message);

  return { today, deleted: rows.length };
}

Deno.serve(async (_req) => {
  const h = kstNow().getUTCHours(); // kstNow 는 이미 +9 를 더한 값이라 UTC 시로 읽으면 서울 시각
  if (h !== SWEEP_HOUR) {
    // 스터디 중이거나 엉뚱한 시각 — 아무것도 지우지 않는다.
    return new Response(JSON.stringify({ ok: true, skipped: true, kstHour: h }), {
      headers: { "Content-Type": "application/json" },
    });
  }
  try {
    const out = await sweep();
    return new Response(JSON.stringify({ ok: true, ...out }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
