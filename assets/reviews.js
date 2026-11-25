// 상세페이지 구매평 (2026-11-25 원장님 「데일리·스윽 리뷰 페이지」 → 「스테디처럼」)
// 쓰는 법: <section id="reviews" data-product="daily|seuk" data-theme="light|dark" data-tabs-before="CSS선택자"></section> + 이 파일
//   data-tabs-before 앞에 「상세정보 | 구매평(N)」 탭 막대가 붙고, 내려도 위에 따라온다.
// 후기는 완토 Supabase product_reviews(사진은 저장통 review-photos). 누구나 쓰고, 원장·실장이 승인(status='ok')한 것만 보인다.
// 🚨 지어낸 후기 금지(표시광고법). 체험단(무료 제공·보상) 후기는 sponsored=true → 「체험단」 표시.
(function () {
  const box = document.getElementById('reviews');
  if (!box) return;
  const P = box.dataset.product, dark = box.dataset.theme === 'dark';
  const SB = 'https://guaqfsuwrvqjffmbiwpw.supabase.co', KEY = 'sb_publishable_0bsxx0fJt86WQFuuZeoH-g_9pxVxh-C';
  const H = { apikey: KEY, Authorization: 'Bearer ' + KEY };
  const rpc = (fn, body) => fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then((r) => r.json());
  const photoUrl = (p) => `${SB}/storage/v1/object/public/review-photos/${p}`;
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const C = dark
    ? { page: '#000', bg: '#111', line: '#262626', ink: '#ededed', sub: '#9b9b9b', star: '#d8ff3e', bar: '#2a2a2a', btn: '#d8ff3e', btnInk: '#0b0b0b', field: '#181818', tab: '#d8ff3e', tabInk: '#0b0b0b' }
    : { page: '#fff', bg: '#fff', line: '#ebe8e1', ink: '#191f28', sub: '#6b7684', star: '#f26a2e', bar: '#eeebe4', btn: '#191f28', btnInk: '#fff', field: '#f6f4ef', tab: '#f26a2e', tabInk: '#fff' };
  const css = document.createElement('style');
  css.textContent = `
  .rvtabs{position:sticky;top:0;z-index:20;display:grid;grid-template-columns:1fr 1fr;background:${C.page};border-bottom:1px solid ${C.line}}
  .rvtabs a{display:block;text-align:center;padding:15px 0;font-weight:800;font-size:16px;text-decoration:none;color:${C.ink}}
  .rvtabs a.on{background:${C.tab};color:${C.tabInk}}
  .rv{padding:${dark ? '56px 0' : '56px 22px'};max-width:${dark ? 'none' : '560px'};margin:0 auto;${dark ? `border-top:1px solid ${C.line}` : ''}}
  .rv h2{font-size:26px;font-weight:800;line-height:1.35;color:${C.ink}}
  .rv .sumbox{display:grid;grid-template-columns:auto 1fr;gap:22px;align-items:center;background:${dark ? '#111' : '#f6f4ef'};border-radius:18px;padding:20px 22px;margin:16px 0 22px}
  .rv .avg{text-align:center;min-width:110px}
  .rv .avg .st{font-size:20px}.rv .avg b{display:block;font-size:44px;font-weight:800;line-height:1.15;color:${C.ink}}
  .rv .avg span{font-size:13px;color:${C.sub}}
  .rv .bars{display:grid;gap:7px}
  .rv .br{display:grid;grid-template-columns:34px 1fr;gap:10px;align-items:center;font-size:14px;color:${C.sub}}
  .rv .br i{display:block;height:10px;border-radius:99px;background:${C.bar};overflow:hidden}
  .rv .br i u{display:block;height:100%;background:${C.star};border-radius:99px}
  .rv .st{color:${C.star};letter-spacing:1px}
  .rv h3{font-size:17px;font-weight:800;color:${C.ink};margin:6px 0 10px}
  .rv .strip{display:flex;gap:8px;overflow-x:auto;padding-bottom:6px;margin-bottom:10px;scrollbar-width:none}
  .rv .strip img{flex:none;width:96px;height:96px;object-fit:cover;border-radius:12px;border:1px solid ${C.line};cursor:pointer}
  .rv .fl{display:flex;gap:8px;align-items:center;font-size:14px;color:${C.sub};margin:6px 0 14px;cursor:pointer}
  .rv .fl input{accent-color:${C.star}}
  .rv .list{display:grid;gap:0}
  .rv .it{border-top:1px solid ${C.line};padding:18px 2px}
  .rv .hd{display:flex;justify-content:space-between;gap:8px;font-size:13.5px;color:${C.sub};align-items:center}
  .rv .hd .st{font-size:17px}
  .rv .who{font-size:13.5px;color:${C.sub};margin-top:4px}
  .rv .sp{display:inline-block;font-size:11.5px;font-weight:700;border:1px solid ${C.line};border-radius:999px;padding:1px 8px;margin-left:6px;color:${C.sub}}
  .rv .bd{font-size:15.5px;line-height:1.75;margin-top:8px;color:${C.ink};white-space:pre-wrap;word-break:keep-all}
  .rv .sc{font-size:13.5px;color:${C.sub};margin-top:6px}
  .rv .ph{display:flex;gap:8px;margin-top:10px}
  .rv .ph img{width:88px;height:88px;object-fit:cover;border-radius:10px;border:1px solid ${C.line};cursor:pointer}
  .rv .empty{border:1px dashed ${C.line};border-radius:18px;padding:24px;text-align:center;color:${C.sub};font-size:15px;line-height:1.6}
  .rv .more{display:block;margin:12px auto 0;background:none;border:1px solid ${C.line};color:${C.sub};border-radius:999px;padding:8px 18px;font:inherit;cursor:pointer}
  .rv details{margin-top:18px;border:1px solid ${C.line};border-radius:18px;padding:16px 18px;background:${C.bg}}
  .rv summary{cursor:pointer;font-weight:800;font-size:16px;color:${C.ink};list-style:none}
  .rv summary::-webkit-details-marker{display:none}
  .rv form{display:grid;gap:10px;margin-top:14px}
  .rv input[type=text],.rv textarea{width:100%;font:inherit;font-size:16px;border:1px solid ${C.line};border-radius:12px;padding:12px 13px;background:${C.field};color:${C.ink};box-sizing:border-box}
  .rv textarea{min-height:110px;resize:vertical}
  .rv .stars{display:flex;gap:4px}
  .rv .stars button{background:none;border:0;font-size:30px;line-height:1;cursor:pointer;color:${C.bar};padding:2px}
  .rv .stars button.on{color:${C.star}}
  .rv .pick{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
  .rv .pick label{display:inline-flex;align-items:center;justify-content:center;width:72px;height:72px;border:1px dashed ${C.line};border-radius:12px;color:${C.sub};font-size:13px;cursor:pointer;text-align:center}
  .rv .pick img{width:72px;height:72px;object-fit:cover;border-radius:12px}
  .rv .go{background:${C.btn};color:${C.btnInk};border:0;border-radius:12px;padding:14px;font:inherit;font-weight:800;font-size:16px;cursor:pointer}
  .rv .msg{font-size:14px;color:${C.sub}}
  .rvzoom{position:fixed;inset:0;background:rgba(0,0,0,.85);display:flex;align-items:center;justify-content:center;z-index:99;padding:16px}
  .rvzoom img{max-width:100%;max-height:100%;border-radius:12px}
  @media(max-width:420px){.rv .sumbox{grid-template-columns:1fr}.rv .avg{min-width:0}}
  `;
  document.head.appendChild(css);
  const stars = (n) => '★★★★★'.slice(0, n) + '☆☆☆☆☆'.slice(0, 5 - n);

  // 탭 막대
  const before = box.dataset.tabsBefore && document.querySelector(box.dataset.tabsBefore);
  let tabs = null;
  if (before) {
    tabs = document.createElement('nav');
    tabs.className = 'rvtabs';
    tabs.innerHTML = '<a href="#" data-t="info" class="on">상세정보</a><a href="#reviews" data-t="rv">구매평</a>';
    before.parentNode.insertBefore(tabs, before);
    tabs.querySelector('[data-t=info]').onclick = (e) => { e.preventDefault(); window.scrollTo({ top: tabs.offsetTop, behavior: 'smooth' }); };
    tabs.querySelector('[data-t=rv]').onclick = (e) => { e.preventDefault(); window.scrollTo({ top: box.getBoundingClientRect().top + scrollY - tabs.offsetHeight, behavior: 'smooth' }); };
    addEventListener('scroll', () => {
      const r = box.getBoundingClientRect(), inRv = r.top < tabs.offsetHeight + 40 && r.bottom > tabs.offsetHeight + 40;
      tabs.querySelector('[data-t=rv]').classList.toggle('on', inRv);
      tabs.querySelector('[data-t=info]').classList.toggle('on', !inRv);
    }, { passive: true });
  }

  box.innerHTML = `<div class="rv">
    <h2>구매평</h2>
    <div id="rv_sum"></div>
    <div id="rv_photos"></div>
    <div class="list" id="rv_list"></div>
    <details><summary>구매평 쓰기</summary>
      <form id="rv_form">
        <div class="stars" id="rv_stars" role="radiogroup" aria-label="별점">${[1, 2, 3, 4, 5].map((i) => `<button type="button" data-v="${i}" aria-label="${i}점" class="on">★</button>`).join('')}</div>
        <input type="text" id="rv_name" maxlength="20" placeholder="이름 (화면에는 가운데 글자를 가려요)" autocomplete="name">
        <input type="text" id="rv_score" maxlength="60" placeholder="점수 변화나 목표 (선택) 예: 650 → 780">
        <textarea id="rv_body" maxlength="600" placeholder="써 보니 어땠는지 적어 주세요 (5자 이상)"></textarea>
        <div class="pick" id="rv_pick"><label>사진 추가<br>(최대 3장)<input type="file" id="rv_file" accept="image/*" multiple hidden></label></div>
        <button class="go" type="submit">구매평 보내기</button>
        <p class="msg" id="rv_msg">보내 주신 구매평은 확인한 뒤에 올라가요.</p>
      </form>
    </details>
  </div>`;
  const $ = (s) => box.querySelector(s);
  let rating = 5, all = [], shown = 6, photoOnly = false, files = [];

  function zoom(src) {
    const z = document.createElement('div'); z.className = 'rvzoom'; z.innerHTML = `<img src="${esc(src)}" alt="">`;
    z.onclick = () => z.remove(); document.body.appendChild(z);
  }
  box.addEventListener('click', (e) => { if (e.target.matches('.strip img,.ph img')) zoom(e.target.src); });

  $('#rv_stars').addEventListener('click', (e) => {
    const v = +(e.target.dataset.v || 0); if (!v) return; rating = v;
    box.querySelectorAll('#rv_stars button').forEach((b) => b.classList.toggle('on', +b.dataset.v <= v));
  });
  $('#rv_file').addEventListener('change', (e) => {
    files = [...files, ...e.target.files].filter((f) => /^image\//.test(f.type)).slice(0, 3);
    box.querySelectorAll('#rv_pick img').forEach((i) => i.remove());
    files.forEach((f) => { const i = document.createElement('img'); i.src = URL.createObjectURL(f); $('#rv_pick').appendChild(i); });
    e.target.value = '';
  });

  function draw() {
    if (tabs) tabs.querySelector('[data-t=rv]').textContent = `구매평 (${all.length})`;
    if (!all.length) {
      $('#rv_sum').innerHTML = ''; $('#rv_photos').innerHTML = '';
      $('#rv_list').innerHTML = '<div class="empty">아직 올라온 구매평이 없어요.<br>써 보셨다면 첫 구매평을 남겨 주세요.</div>';
      return;
    }
    const avg = all.reduce((a, r) => a + r.rating, 0) / all.length;
    const cnt = [5, 4, 3, 2, 1].map((s) => all.filter((r) => r.rating === s).length);
    $('#rv_sum').innerHTML = `<div class="sumbox"><div class="avg"><div class="st">${stars(Math.round(avg))}</div><b>${avg.toFixed(1)}</b><span>(총 ${all.length}개의 구매평)</span></div>
      <div class="bars">${cnt.map((c, i) => `<div class="br">${5 - i}점<i><u style="width:${(c / all.length) * 100}%"></u></i></div>`).join('')}</div></div>`;
    const pics = all.flatMap((r) => (r.photos || []).map(photoUrl));
    $('#rv_photos').innerHTML = pics.length ? `<h3>포토 구매평 모아보기</h3><div class="strip">${pics.slice(0, 20).map((u) => `<img src="${u}" alt="" loading="lazy">`).join('')}</div>
      <label class="fl"><input type="checkbox" id="rv_only" ${photoOnly ? 'checked' : ''}> 포토 구매평만 보기</label>` : '';
    const oc = $('#rv_only'); if (oc) oc.onchange = () => { photoOnly = oc.checked; shown = 6; draw(); };
    const list = photoOnly ? all.filter((r) => (r.photos || []).length) : all;
    $('#rv_list').innerHTML = list.slice(0, shown).map((r) => `<div class="it">
      <div class="hd"><span class="st">${stars(r.rating)}</span><span>${esc(r.date)}</span></div>
      <div class="who">${esc(r.name)}${r.sponsored ? '<span class="sp">체험단</span>' : ''}</div>
      <div class="bd">${esc(r.body)}</div>${r.score ? `<div class="sc">${esc(r.score)}</div>` : ''}
      ${(r.photos || []).length ? `<div class="ph">${r.photos.map((p) => `<img src="${photoUrl(p)}" alt="" loading="lazy">`).join('')}</div>` : ''}</div>`).join('')
      + (list.length > shown ? '<button class="more" type="button" id="rv_more">구매평 더 보기</button>' : '');
    const m = $('#rv_more'); if (m) m.onclick = () => { shown += 10; draw(); };
  }
  rpc('review_list', { p_product: P }).then((a) => { all = Array.isArray(a) ? a : []; draw(); }).catch(draw);

  async function shrink(f) {
    // 긴 변 1600px JPEG 로 줄여서 올린다(용량·개인정보 메타데이터 제거)
    const img = await createImageBitmap(f);
    const k = Math.min(1, 1600 / Math.max(img.width, img.height));
    const c = document.createElement('canvas'); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    return new Promise((res) => c.toBlob(res, 'image/jpeg', 0.85));
  }
  async function upload(f) {
    const blob = await shrink(f);
    const name = 'r/' + crypto.getRandomValues(new Uint32Array(4)).join('').slice(0, 24) + '.jpg';
    const r = await fetch(`${SB}/storage/v1/object/review-photos/${name}`, { method: 'POST', headers: { ...H, 'Content-Type': 'image/jpeg' }, body: blob });
    if (!r.ok) throw new Error('upload');
    return name;
  }
  $('#rv_form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = $('#rv_name').value.trim(), body = $('#rv_body').value.trim();
    if (!name) { $('#rv_msg').textContent = '이름을 적어 주세요.'; return; }
    if (body.length < 5) { $('#rv_msg').textContent = '구매평을 5자 이상 적어 주세요.'; return; }
    $('#rv_msg').textContent = files.length ? '사진 올리는 중…' : '보내는 중…';
    try {
      const photos = [];
      for (const f of files) photos.push(await upload(f));
      const r = await rpc('review_add', { p_product: P, p_name: name, p_rating: rating, p_body: body, p_score: $('#rv_score').value.trim() || null, p_photos: photos });
      if (r && r.ok) {
        $('#rv_form').reset(); files = []; box.querySelectorAll('#rv_pick img').forEach((i) => i.remove());
        $('#rv_msg').textContent = '고마워요! 확인한 뒤에 올라가요.';
      } else $('#rv_msg').textContent = '보내지 못했어요. 잠시 뒤 다시 해 주세요.';
    } catch { $('#rv_msg').textContent = '보내지 못했어요. 인터넷 연결을 확인하고 다시 보내 주세요.'; }
  });
})();
