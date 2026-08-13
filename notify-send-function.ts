// 결제 안내 알림톡 발송기 (Supabase Edge Function · 이름: notify-send)
//
// 하는 일
//   notify_outbox 에서 아직 안 보낸 줄을 꺼내 솔라피로 카카오 알림톡을 쏜다.
//   성공하면 sent_at 을 찍고, 실패하면 error 와 tries 를 남긴다.
//
// 안전장치 (돈이 나가고 학생에게 진짜 카톡이 가는 일이라 일부러 빡빡하게 했다)
//   · 남은 횟수가 딱 1회인 줄만 보낸다(원장 지시 2026-08-13 "1회 수업 남았을 경우 발송이야").
//   · 한 번 돌 때 최대 MAX_PER_RUN 건. 실수로 수십 건이 한꺼번에 나가지 않게.
//   · 세 번 실패한 줄은 건너뛴다(무한 재시도 금지).
//   · ?dry=1 로 부르면 보내지 않고 '무엇을 보낼지'만 알려준다.
//   · ?test=1 로 부르면 대기열은 건드리지 않고 발신번호(원장님 번호)로 한 통만 시험 발송한다.
//
// 템플릿 (2026-08-13 승인됨)
//   이름 '재결제' · 변수 #{이름}, #{결제기한}
//   "수강생 #{이름}님의 남은 수업은 1회입니다. 결제 기한은 #{결제기한}까지입니다."
//   ⚠️ 알림톡은 승인된 템플릿 글자를 그대로 보내야 한다. notify_outbox.body 는
//      사람이 읽어 보라고 만들어 둔 미리보기라 발송에는 쓰지 않는다.
//
// 필요한 Secret (이미 등록돼 있음)
//   SOLAPI_API_KEY · SOLAPI_API_SECRET · SOLAPI_TEMPLATE_ID · SOLAPI_PFID · SOLAPI_FROM
//   SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY 는 Supabase 가 알아서 넣어 준다.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_PER_RUN = 20;

function env(k: string): string {
  const v = Deno.env.get(k);
  if (!v) throw new Error(`Secret 없음: ${k}`);
  return v;
}

// 솔라피 인증 — HMAC-SHA256(secret, date + salt)
async function authHeader(): Promise<string> {
  const key = env("SOLAPI_API_KEY");
  const secret = env("SOLAPI_API_SECRET");
  const date = new Date().toISOString();
  const salt = crypto.randomUUID().replace(/-/g, "");
  const k = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(date + salt));
  const hex = [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `HMAC-SHA256 apiKey=${key}, date=${date}, salt=${salt}, signature=${hex}`;
}

// 결제기한 문구 — 다음 수업이 안 잡혀 있으면 날짜 없이 보낸다(원장 지시 2026-08-06).
function dueText(nextISO: string | null): string {
  if (!nextISO) return "다음 수업 전";
  const d = new Date(new Date(nextISO).getTime() + 9 * 60 * 60 * 1000); // KST
  return `${d.getUTCMonth() + 1}월 ${d.getUTCDate()}일 수업 전`;
}

type SendResult = { ok: boolean; detail: unknown };

async function sendOne(to: string, name: string, due: string): Promise<SendResult> {
  const body = {
    message: {
      to: to.replace(/[^0-9]/g, ""),
      from: env("SOLAPI_FROM"),
      type: "ATA",                       // 알림톡
      kakaoOptions: {
        pfId: env("SOLAPI_PFID"),
        templateId: env("SOLAPI_TEMPLATE_ID"),
        disableSms: true,                // 실패해도 문자로 대체 발송하지 않는다(요금·문구 사고 방지)
        variables: { "#{이름}": name, "#{결제기한}": due },
      },
    },
  };
  const res = await fetch("https://api.solapi.com/messages/v4/send", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: await authHeader() },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  // 솔라피는 200 을 주고도 본문에 실패 사유를 담는 경우가 있어 statusCode 까지 본다.
  const code = (json as any)?.statusCode ?? (json as any)?.errorCode;
  const ok = res.ok && (code === undefined || code === "2000");
  return { ok, detail: json };
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const dry = url.searchParams.get("dry") === "1";
    const test = url.searchParams.get("test") === "1";

    if (test) {
      const r = await sendOne(env("SOLAPI_FROM"), "시험", "8월 20일 수업 전");
      return new Response(JSON.stringify({ mode: "test", ...r }, null, 2), {
        status: r.ok ? 200 : 500, headers: { "content-type": "application/json" },
      });
    }

    const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

    const { data: rows, error } = await db.from("notify_outbox")
      .select("id,student_id,student_name,phone,left_count,next_lesson_at,tries")
      .is("sent_at", null)
      .eq("kind", "payment_due")
      .lt("tries", 3)
      .order("id", { ascending: true })
      .limit(MAX_PER_RUN);
    if (error) throw new Error("대기열 읽기 실패: " + error.message);

    const out: unknown[] = [];
    for (const r of rows ?? []) {
      // 대기열에 들어간 뒤 상황이 바뀌었을 수 있다. 보내는 순간 다시 확인한다.
      const { data: left } = await db.rpc("sessions_left", { p_student: r.student_id });
      if (left !== 1) {
        await db.from("notify_outbox")
          .update({ error: `보낼 때 남은 횟수가 ${left}회라 건너뜀`, tries: (r.tries ?? 0) + 1 })
          .eq("id", r.id);
        out.push({ id: r.id, who: r.student_name, skipped: `남은 ${left}회` });
        continue;
      }
      if (!r.phone) {
        await db.from("notify_outbox")
          .update({ error: "휴대폰 번호 없음", tries: (r.tries ?? 0) + 1 }).eq("id", r.id);
        out.push({ id: r.id, who: r.student_name, skipped: "번호 없음" });
        continue;
      }

      const due = dueText(r.next_lesson_at);
      if (dry) { out.push({ id: r.id, who: r.student_name, to: r.phone, due, dry: true }); continue; }

      const res = await sendOne(r.phone, r.student_name ?? "학생", due);
      if (res.ok) {
        await db.from("notify_outbox")
          .update({ sent_at: new Date().toISOString(), error: null }).eq("id", r.id);
      } else {
        await db.from("notify_outbox")
          .update({ error: JSON.stringify(res.detail).slice(0, 500), tries: (r.tries ?? 0) + 1 })
          .eq("id", r.id);
      }
      out.push({ id: r.id, who: r.student_name, ok: res.ok });
    }

    return new Response(JSON.stringify({ ok: true, dry, count: out.length, out }, null, 2), {
      headers: { "content-type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500, headers: { "content-type": "application/json" },
    });
  }
});
