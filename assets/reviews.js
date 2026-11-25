// 상세페이지 후기 칸 (2026-11-25 원장님 「데일리·스윽 리뷰 페이지」)
// 쓰는 법: <section id="reviews" data-product="daily|seuk" data-theme="light|dark"></section> + 이 파일
// 후기는 완토 Supabase product_reviews. 누구나 쓰고, 원장·실장이 승인(status='ok')한 것만 보인다.
// 🚨 지어낸 후기 금지(표시광고법). 체험단(무료 제공·보상) 후기는 sponsored=true → 「체험단」 표시.
(function () {
  const box = document.getElementById('reviews');
  if (!box) return;
  const P = box.dataset.product, dark = box.dataset.theme === 'dark';
  const SB = 'https://guaqfsuwrvqjffmbiwpw.supabase.co', KEY = 'sb_publishable_0bsxx0fJt86WQFuuZeoH-g_9pxVxh-C';
  const rpc = (fn, body) => fetch(`${SB}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }).then((r) => r.json());
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const C = dark
    ? { bg: '#111', line: '#262626', ink: '#ededed', sub: '#9b9b9b', star: '#d8ff3e', btn: '#d8ff3e', btnInk: '#0b0b0b', field: '#181818' }
    : { bg: '#fff', line: '#ebe8e1', ink: '#191f28', sub: '#6b7684', star: '#f2a43a', btn: '#191f28', btnInk: '#fff', field: '#f6f4ef' };
  const css = document.createElement('style');
  css.textContent = `
  .rv{padding:${dark ? '56px 0' : '56px 22px'};max-width:${dark ? 'none' : '560px'};margin:0 auto;${dark ? `border-top:1px solid ${C.line}` : ''}}
  .rv h2{font-size:26px;font-weight:800;line-height:1.35;color:${C.ink}}
  .rv .sum{display:flex;align-items:center;gap:10px;margin:10px 0 20px;color:${C.sub};font-size:15px}
  .rv .sum b{font-size:22px;color:${C.ink}}
  .rv .st{color:${C.star};letter-spacing:1px}
  .rv .list{display:grid;gap:12px}
  .rv .it{background:${C.bg};border:1px solid ${C.line};border-radius:18px;padding:18px}
  .rv .hd{display:flex;justify-content:space-between;gap:8px;font-size:14px;color:${C.sub}}
  .rv .hd b{color:${C.ink};font-size:15px;margin-right:6px}
  .rv .sp{display:inline-block;font-size:11.5px;font-weight:700;border:1px solid ${C.line};border-radius:999px;padding:1px 8px;margin-left:6px;color:${C.sub}}
  .rv .bd{font-size:15.5px;line-height:1.7;margin-top:8px;color:${C.ink};white-space:pre-wrap;word-break:keep-all}
  .rv .sc{font-size:13.5px;color:${C.sub};margin-top:6px}
  .rv .empty{border:1px dashed ${C.line};border-radius:18px;padding:24px;text-align:center;color:${C.sub};font-size:15px;line-height:1.6}
  .rv .more{display:block;margin:12px auto 0;background:none;border:1px solid ${C.line};color:${C.sub};border-radius:999px;padding:8px 18px;font:inherit;cursor:pointer}
  .rv details{margin-top:18px;border:1px solid ${C.line};border-radius:18px;padding:16px 18px;background:${C.bg}}
  .rv summary{cursor:pointer;font-weight:800;font-size:16px;color:${C.ink};list-style:none}
  .rv summary::-webkit-details-marker{display:none}
  .rv form{display:grid;gap:10px;margin-top:14px}
  .rv input,.rv textarea{width:100%;font:inherit;font-size:16px;border:1px solid ${C.line};border-radius:12px;padding:12px 13px;background:${C.field};color:${C.ink};box-sizing:border-box}
  .rv textarea{min-height:110px;resize:vertical}
  .rv .stars{display:flex;gap:4px}
  .rv .stars button{background:none;border:0;font-size:30px;line-height:1;cursor:pointer;color:${C.line};padding:2px}
  .rv .stars button.on{color:${C.star}}
  .rv .go{background:${C.btn};color:${C.btnInk};border:0;border-radius:12px;padding:14px;font:inherit;font-weight:800;font-size:16px;cursor:pointer}
  .rv .msg{font-size:14px;color:${C.sub}}
  `;
  document.head.appendChild(css);
  const stars = (n) => '★★★★★'.slice(0, n) + '☆☆☆☆☆'.slice(0, 5 - n);
  box.innerHTML = `<div class="rv">
    <h2>써 본 사람들의 후기</h2>
    <div class="sum" id="rv_sum"></div>
    <div class="list" id="rv_list"></div>
    <details><summary>후기 남기기</summary>
      <form id="rv_form">
        <div class="stars" id="rv_stars" role="radiogroup" aria-label="별점">${[1, 2, 3, 4, 5].map((i) => `<button type="button" data-v="${i}" aria-label="${i}점" class="on">★</button>`).join('')}</div>
        <input id="rv_name" maxlength="20" placeholder="이름 (화면에는 가운데 글자를 가려요)" autocomplete="name">
        <input id="rv_score" maxlength="60" placeholder="점수 변화나 목표 (선택) 예: 650 → 780">
        <textarea id="rv_body" maxlength="600" placeholder="써 보니 어땠는지 적어 주세요 (5자 이상)"></textarea>
        <button class="go" type="submit">후기 보내기</button>
        <p class="msg" id="rv_msg">보내 주신 후기는 확인한 뒤에 올라가요.</p>
      </form>
    </details>
  </div>`;
  let rating = 5, all = [], shown = 6;
  const $ = (s) => box.querySelector(s);
  $('#rv_stars').addEventListener('click', (e) => {
    const v = +(e.target.dataset.v || 0); if (!v) return; rating = v;
    box.querySelectorAll('#rv_stars button').forEach((b) => b.classList.toggle('on', +b.dataset.v <= v));
  });
  function draw() {
    if (!all.length) {
      $('#rv_sum').innerHTML = '';
      $('#rv_list').innerHTML = '<div class="empty">아직 올라온 후기가 없어요.<br>써 보셨다면 첫 후기를 남겨 주세요.</div>';
      return;
    }
    const avg = all.reduce((a, r) => a + r.rating, 0) / all.length;
    $('#rv_sum').innerHTML = `<span class="st">${stars(Math.round(avg))}</span><b>${avg.toFixed(1)}</b> 후기 ${all.length}개`;
    $('#rv_list').innerHTML = all.slice(0, shown).map((r) => `<div class="it">
      <div class="hd"><span><b>${esc(r.name)}</b><span class="st">${stars(r.rating)}</span>${r.sponsored ? '<span class="sp">체험단</span>' : ''}</span><span>${esc(r.date)}</span></div>
      <div class="bd">${esc(r.body)}</div>${r.score ? `<div class="sc">${esc(r.score)}</div>` : ''}</div>`).join('')
      + (all.length > shown ? '<button class="more" type="button" id="rv_more">후기 더 보기</button>' : '');
    const m = $('#rv_more'); if (m) m.onclick = () => { shown += 10; draw(); };
  }
  rpc('review_list', { p_product: P }).then((a) => { all = Array.isArray(a) ? a : []; draw(); }).catch(draw);
  $('#rv_form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = $('#rv_name').value.trim(), body = $('#rv_body').value.trim();
    if (!name) { $('#rv_msg').textContent = '이름을 적어 주세요.'; return; }
    if (body.length < 5) { $('#rv_msg').textContent = '후기를 5자 이상 적어 주세요.'; return; }
    $('#rv_msg').textContent = '보내는 중…';
    try {
      const r = await rpc('review_add', { p_product: P, p_name: name, p_rating: rating, p_body: body, p_score: $('#rv_score').value.trim() || null });
      if (r && r.ok) { $('#rv_form').reset(); $('#rv_msg').textContent = '고마워요! 확인한 뒤에 올라가요.'; }
      else $('#rv_msg').textContent = '보내지 못했어요. 잠시 뒤 다시 해 주세요.';
    } catch { $('#rv_msg').textContent = '인터넷 연결을 확인하고 다시 보내 주세요.'; }
  });
})();
