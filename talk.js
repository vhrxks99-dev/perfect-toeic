/* 완토 Talk — 웹 (2026-11-28 원장님 「톡 기능 전부 웹페이지에도」)
 * 앱(screens/talk)과 같은 서버 함수·표를 쓴다: talk_my_rooms · talk_contacts · talk_all_rooms · talk_messages
 * talk_open_dm · talk_invite · talk_leave · talk_set_pref · talk_mark_read · talk_profile · talk_consult · talk_renewal_state
 * 오른쪽 아래 「Talk」 버튼 → 오른쪽에서 열리는 창(폰 화면에선 꽉 차게).
 * 버튼형 「완토」(수업 옮기기)는 웹엔 없다 — 웹은 스케줄 화면에서 바로 옮긴다.
 */
(function () {
  'use strict';
  var BRAND = '#2F6BE8';
  var S = { open: false, tab: 'chat', rooms: null, contacts: null, all: null, room: null, msgs: [], filter: 'all', q: '', find: '', unread: 0, chan: null, timer: null, roomTimer: null, fs: 1 };
  try { S.fs = Number(localStorage.getItem('talk_fs') || '1') || 1; } catch (e) {}

  function me() { return window.WT_REAL_PROFILE || window.WT_PROFILE || S.guestMe || null; }
  function guestToken() { try { var t = localStorage.getItem('tk_guest'); if (!t) { t = 'g' + Array.from(crypto.getRandomValues(new Uint8Array(18))).map(function (b) { return b.toString(16).padStart(2, '0'); }).join(''); localStorage.setItem('tk_guest', t); } return t; } catch (e) { return null; } }
  function sb() { return window.sb; }
  function isStaff(p) { return p && ['admin', 'master', 'manager'].indexOf(p.role) >= 0; }
  function isOps(p) { return p && (p.role === 'master' || p.role === 'manager'); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function $(id) { return document.getElementById(id); }
  function kst(iso) { var d = new Date(new Date(iso).getTime() + 9 * 3600e3); return d; }
  function ymd(iso) { return kst(iso).toISOString().slice(0, 10); }
  function hm(iso) { return kst(iso).toISOString().slice(11, 16); }
  function today() { return ymd(new Date().toISOString()); }
  var WK = ['일', '월', '화', '수', '목', '금', '토'];
  function sdate(y) { var p = y.split('-'); var w = new Date(y + 'T00:00:00Z').getUTCDay(); return (+p[1]) + '/' + (+p[2]) + '(' + WK[w] + ')'; }
  function whenShort(iso) { return ymd(iso) === today() ? hm(iso) : sdate(ymd(iso)).replace(/\(.\)/, ''); }
  function roomName(r) { return r.kind === 'wanto' ? '완토' : r.kind === 'group' ? (r.title || '단체 톡') : (r.other_name || '이름 없음'); }
  function toast(t) { var el = document.createElement('div'); el.className = 'tk-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(function () { el.remove(); }, 2200); }

  var PERSON = '<svg viewBox="0 0 24 24" fill="#7EA2EA"><circle cx="12" cy="7.5" r="4.5"/><path d="M3 21c0-4.6 4-7.5 9-7.5s9 2.9 9 7.5z"/></svg>';
  var LOGO = 'apple-touch-icon.png';
  function face(name, uri, kind, size) {
    size = size || 44;
    var st = 'width:' + size + 'px;height:' + size + 'px;border-radius:' + Math.round(size * 0.38) + 'px';
    if (kind === 'wanto') return '<img class="tk-face" style="' + st + ';border:1px solid #eee;background:#fff" src="' + LOGO + '">';
    if (uri) return '<img class="tk-face" style="' + st + '" src="' + esc(uri) + '">';
    if (kind === 'group') return '<span class="tk-face tk-facebg" style="' + st + ';background:#E9F0FE;color:' + BRAND + ';font-weight:800">👥</span>';
    return '<span class="tk-face tk-facebg" style="' + st + '">' + PERSON + '</span>';
  }

  // ── 스타일 ──
  var css = '' +
    '.tk-fab{position:fixed;right:22px;bottom:26px;width:62px;height:62px;border-radius:22px;background:' + BRAND + ';color:#fff;font:800 16px Pretendard,sans-serif;border:0;cursor:pointer;box-shadow:0 8px 22px rgba(31,95,224,.35);z-index:9998}' +
    '.tk-fab:after{content:"";position:absolute;bottom:-8px;left:14px;border:8px solid transparent;border-top:10px solid ' + BRAND + ';border-bottom:0}' +
    '.tk-badge{position:absolute;top:-7px;right:-7px;min-width:22px;height:22px;padding:0 6px;border-radius:11px;background:#E24B3B;color:#fff;font:800 12px/22px Pretendard,sans-serif;border:2px solid #fff;box-sizing:content-box}' +
    '.tk-panel{position:fixed;top:0;right:0;bottom:0;width:420px;max-width:100vw;background:#fff;z-index:9999;box-shadow:-10px 0 30px rgba(0,0,0,.12);display:flex;flex-direction:column;font-family:Pretendard,"Malgun Gothic",sans-serif;color:#1A1A1F;transform:translateX(105%);transition:transform .22s ease}' +
    '.tk-panel.on{transform:none}' +
    '@media(max-width:600px){.tk-panel{width:100vw}}' +
    '.tk-head{display:flex;align-items:center;gap:10px;padding:16px 18px 10px}.tk-head b{flex:1;font-size:24px;font-weight:800}' +
    '.tk-x{border:0;background:none;font-size:24px;cursor:pointer;color:#43434C}' +
    '.tk-search{margin:0 16px;display:flex;align-items:center;gap:6px;background:#F5F5F5;border-radius:20px;padding:0 12px;height:40px}.tk-search input{flex:1;border:0;background:none;font:15px Pretendard,sans-serif;outline:0}' +
    '.tk-chips{display:flex;gap:8px;padding:10px 16px 0}.tk-chip{border:0;border-radius:999px;padding:7px 14px;background:#F5F5F5;color:#6E6E78;font:700 14px Pretendard,sans-serif;cursor:pointer}.tk-chip.on{background:' + BRAND + ';color:#fff}' +
    '.tk-body{flex:1;overflow:auto}' +
    '.tk-item{display:flex;align-items:center;gap:12px;padding:10px 18px;cursor:pointer;position:relative}.tk-item:hover{background:#F7F8FA}' +
    '.tk-face{flex:none;object-fit:cover;display:inline-flex;align-items:center;justify-content:center;background:#EBEBEB}.tk-facebg{background:#D3E2FC}.tk-facebg svg{width:56%;height:56%}' +
    '.tk-it{flex:1;min-width:0}.tk-it b{font-size:16px}.tk-it div{font-size:14px;color:#6E6E78;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:3px}' +
    '.tk-rt{text-align:right;font-size:12px;color:#A3A3AD;display:flex;flex-direction:column;align-items:flex-end;gap:5px}' +
    '.tk-un{min-width:20px;height:20px;border-radius:10px;background:#E24B3B;color:#fff;font:800 12px/20px Pretendard,sans-serif;text-align:center;padding:0 6px}' +
    '.tk-more{border:0;background:none;color:#A3A3AD;font-size:18px;cursor:pointer;padding:4px 6px;visibility:hidden}.tk-item:hover .tk-more{visibility:visible}' +
    '.tk-sec{font-size:13px;font-weight:700;color:#6E6E78;padding:14px 18px 4px}' +
    '.tk-empty{text-align:center;color:#6E6E78;font-size:15px;padding:40px 30px;line-height:1.6}' +
    '.tk-nav{display:flex;justify-content:space-around;border-top:1px solid #EAE7E3;padding:8px 0}.tk-nav button{border:0;background:none;font:700 12px Pretendard,sans-serif;color:#A3A3AD;cursor:pointer;display:flex;flex-direction:column;align-items:center;gap:3px;min-width:70px}.tk-nav button.on{color:' + BRAND + '}.tk-nav i{font-style:normal;font-size:20px}' +
    '.tk-room{display:flex;flex-direction:column;height:100%;background:#E9EEF8}' +
    '.tk-rhead{display:flex;align-items:center;gap:12px;padding:14px 14px}.tk-rhead b{flex:1;font-size:22px;font-weight:800;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.tk-rhead button{border:0;background:none;font-size:22px;cursor:pointer;color:#43434C}' +
    '.tk-msgs{flex:1;overflow:auto;padding:6px 12px 16px}' +
    '.tk-day{text-align:center;margin:10px 0}.tk-day span{background:rgba(255,255,255,.6);color:#7C869A;font-size:12.5px;border-radius:10px;padding:3px 10px}' +
    '.tk-nm{font-size:13px;color:#43434C;margin:10px 0 3px 4px}' +
    '.tk-row{display:flex;align-items:flex-end;gap:6px;margin-top:4px}.tk-row.me{justify-content:flex-end}' +
    '.tk-tm{font-size:11px;color:#8A92A3;white-space:nowrap}.tk-one{font-size:11px;color:#E2A400;font-weight:700;display:block;text-align:right}' +
    '.tk-bb{max-width:74%;background:#fff;border-radius:16px;padding:9px 13px;font-size:15.5px;line-height:1.5;white-space:pre-wrap;word-break:keep-all;overflow-wrap:anywhere}' +
    '.tk-row.me .tk-bb{background:' + BRAND + ';color:#fff}' +
    '.tk-bot{background:#EDF3FE!important;border:1.5px solid #DCE8FD}.tk-claude{background:#FFF5E4!important;border:1.5px solid #F2D9A6}' +
    '.tk-card{max-width:82%;background:#fff;border-radius:16px;padding:12px 13px;font-size:15px;line-height:1.5;white-space:pre-wrap}' +
    '.tk-card img{width:100%;border-radius:10px;margin-top:8px;cursor:zoom-in}.tk-imp{border:2px solid #D2483C}' +
    '.tk-tag{display:inline-block;font-size:12px;font-weight:800;border-radius:6px;padding:2px 7px;margin-bottom:4px}' +
    '.tk-btn{display:block;width:100%;border:0;border-radius:12px;padding:10px;margin-top:8px;font:800 14px Pretendard,sans-serif;cursor:pointer;background:#EDF3FE;color:' + BRAND + '}.tk-btn.main{background:' + BRAND + ';color:#fff}.tk-btn:disabled{opacity:.45;cursor:default}' +
    '.tk-ops{display:flex;flex-wrap:wrap;gap:7px;margin-top:8px}.tk-op{border:1.5px solid ' + BRAND + ';color:' + BRAND + ';background:#fff;border-radius:999px;padding:6px 12px;font:800 13px Pretendard,sans-serif;cursor:pointer}.tk-op.on{background:' + BRAND + ';color:#fff}' +
    '.tk-img{max-width:220px;border-radius:14px;cursor:zoom-in;display:block}.tk-file{display:flex;gap:10px;align-items:center;background:#fff;border-radius:14px;padding:10px;max-width:260px;color:#1A1A1F;text-decoration:none}.tk-file i{font-style:normal;width:38px;height:44px;border-radius:7px;background:#E24B3B;color:#fff;font-size:10px;font-weight:800;display:flex;align-items:center;justify-content:center}' +
    '.tk-hit{background:rgba(255,214,102,.45);border-radius:12px}' +
    '.tk-input{display:flex;gap:8px;align-items:flex-end;background:#fff;padding:8px 10px}.tk-input textarea{flex:1;resize:none;border:0;background:#F5F5F5;border-radius:20px;padding:10px 14px;font:15.5px Pretendard,sans-serif;max-height:120px;outline:0}.tk-send,.tk-att{width:40px;height:40px;border-radius:20px;border:0;cursor:pointer;font-size:18px}.tk-send{background:' + BRAND + ';color:#fff}.tk-att{background:#F5F5F5;color:#6E6E78}' +
    '.tk-ro{background:#fff;text-align:center;color:#A3A3AD;font-size:14px;padding:12px}' +
    '.tk-findbar{display:flex;gap:8px;align-items:center;margin:0 12px 6px;background:#fff;border-radius:20px;padding:0 12px;height:40px}.tk-findbar input{flex:1;border:0;outline:0;font:15px Pretendard,sans-serif}.tk-findbar button{border:0;background:none;cursor:pointer;font-size:16px;color:' + BRAND + '}' +
    '.tk-sheet{position:absolute;inset:0;background:rgba(20,28,45,.4);display:flex;align-items:flex-end;z-index:5}.tk-sheet>div{background:#fff;width:100%;border-radius:22px 22px 0 0;padding:18px 18px 26px;max-height:80%;overflow:auto}' +
    '.tk-sheet h4{margin:0 0 10px;font-size:17px}.tk-mrow{display:flex;align-items:center;gap:10px;padding:7px 0;cursor:pointer}' +
    '.tk-pcard{text-align:center}.tk-pcard .nm{font-size:23px;font-weight:800;margin-top:10px}.tk-pcard .sub{color:#6E6E78;font-size:14px;margin-top:4px}' +
    '.tk-pbtns{display:flex;justify-content:center;gap:18px;margin:18px 0 14px}.tk-pbtns a,.tk-pbtns button{display:flex;flex-direction:column;align-items:center;gap:6px;border:0;background:none;cursor:pointer;font:700 13px Pretendard,sans-serif;color:#43434C;text-decoration:none}.tk-pbtns span{width:54px;height:54px;border-radius:20px;color:#fff;font-size:22px;display:flex;align-items:center;justify-content:center}' +
    '.tk-pinfo{background:#F5F7FB;border-radius:16px;padding:12px 14px;text-align:left;font-size:14.5px;line-height:1.9}.tk-pinfo b{color:#6E6E78;margin-right:8px}' +
    '.tk-set{background:#F5F5F5;border-radius:18px;padding:16px;margin:12px 16px}.tk-set label{display:flex;justify-content:space-between;align-items:center;font-weight:700}.tk-set small{display:block;color:#6E6E78;font-weight:400;margin-top:3px}' +
    '.tk-toast{position:fixed;left:50%;bottom:110px;transform:translateX(-50%);background:#1A1A1F;color:#fff;padding:10px 16px;border-radius:12px;font:14px Pretendard,sans-serif;z-index:10000}';

  function mount() {
    if ($('tkFab')) return;
    if (!document.getElementById('tkCss')) { var st = document.createElement('style'); st.id = 'tkCss'; st.textContent = css; document.head.appendChild(st); }
    var fab = document.createElement('button'); fab.id = 'tkFab'; fab.className = 'tk-fab'; fab.innerHTML = 'Talk<span class="tk-badge" id="tkBadge" style="display:none"></span>';
    fab.onclick = openPanel; document.body.appendChild(fab);
    var p = document.createElement('div'); p.id = 'tkPanel'; p.className = 'tk-panel'; document.body.appendChild(p);
    var f = document.createElement('input'); f.type = 'file'; f.id = 'tkFile'; f.multiple = true; f.style.display = 'none'; f.onchange = onFiles; document.body.appendChild(f);
  }
  function unmount() { ['tkFab', 'tkPanel', 'tkFile'].forEach(function (id) { var e = $(id); if (e) e.remove(); }); stopLive(); }

  function setBadge(n) { S.unread = n; var b = $('tkBadge'); if (!b) return; b.style.display = n > 0 ? '' : 'none'; b.textContent = n > 99 ? '99+' : n; }
  async function refreshUnread() {
    var p = me(); if (!p || !sb()) return;
    var r = await sb().rpc('talk_unread_total', { u: p.id }); if (!r.error) setBadge(r.data || 0);
  }
  function startLive() {
    stopLive();
    try {
      S.chan = sb().channel('talk_web_' + Math.random().toString(36).slice(2, 7))
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'talk_messages' }, function (pl) {
          refreshUnread();
          if (S.open && !S.room) loadRooms();
          if (S.room && pl.new && pl.new.room_id === S.room.id) loadMsgs();
        }).subscribe();
    } catch (e) {}
    S.timer = setInterval(function () { refreshUnread(); if (S.open && !S.room) loadRooms(); }, 25000);
  }
  function stopLive() { if (S.chan) { try { sb().removeChannel(S.chan); } catch (e) {} S.chan = null; } if (S.timer) clearInterval(S.timer); S.timer = null; }

  async function openPanel() {
    var p = me(); if (!p) return;
    S.open = true; S.room = null; $('tkPanel').classList.add('on'); $('tkFab').style.display = 'none';
    try { await sb().rpc('talk_open_wanto'); if (isStaff(p)) await sb().rpc('talk_open_staff'); } catch (e) {}
    // 담당 선생님이 없는 학생은 「완토 상담」을 연다
    if (p.role === 'student' && !p.teacher_id) { try { await sb().rpc('talk_consult', { p_action: 'start', p_value: null }); } catch (e) {} }
    renderList(); loadRooms();
  }
  function closePanel() { S.open = false; S.room = null; $('tkPanel').classList.remove('on'); var f = $('tkFab'); if (f) f.style.display = S.guest ? 'none' : ''; if (S.guestTimer) { clearInterval(S.guestTimer); S.guestTimer = null; } if (!S.guest) refreshUnread(); }

  async function loadRooms() {
    var r = await sb().rpc('talk_my_rooms'); S.rooms = r.error ? [] : (r.data || []);
    setBadge(S.rooms.reduce(function (a, x) { return a + (x.unread || 0); }, 0));
    if (S.open && !S.room) renderList();
  }

  // ── 목록 화면 ──
  function renderList() {
    var p = me(); var html = '';
    var title = S.tab === 'friends' ? '친구' : S.tab === 'all' ? '전체 톡' : S.tab === 'settings' ? '설정' : 'Talk';
    html += '<div class="tk-head"><b>' + title + '</b><button class="tk-x" data-a="close">✕</button></div>';
    if (S.tab !== 'settings') html += '<div class="tk-search">🔍<input id="tkQ" placeholder="이름 검색" value="' + esc(S.q) + '"></div>';
    if (S.tab === 'chat' && isStaff(p)) html += '<div class="tk-chips">' + [['all', '전체'], ['student', '학생'], ['staff', '선생님']].map(function (c) { return '<button class="tk-chip' + (S.filter === c[0] ? ' on' : '') + '" data-f="' + c[0] + '">' + c[1] + '</button>'; }).join('') + '</div>';
    html += '<div class="tk-body" id="tkBody">' + listBody() + '</div>';
    var tabs = [['friends', '👤', '친구'], ['chat', '💬', '채팅']]; if (isOps(p)) tabs.push(['all', '👁', '전체 톡']); tabs.push(['settings', '⚙', '설정']);
    html += '<div class="tk-nav">' + tabs.map(function (t) { return '<button class="' + (S.tab === t[0] ? 'on' : '') + '" data-t="' + t[0] + '"><i>' + t[1] + '</i>' + t[2] + '</button>'; }).join('') + '</div>';
    var el = $('tkPanel'); el.innerHTML = html;
    var q = $('tkQ'); if (q) { q.oninput = function () { S.q = q.value; $('tkBody').innerHTML = listBody(); }; }
    if (S.tab === 'friends' && !S.contacts) sb().rpc('talk_contacts').then(function (r) { S.contacts = r.error ? [] : r.data || []; if (S.tab === 'friends') $('tkBody').innerHTML = listBody(); });
    if (S.tab === 'all' && !S.all) sb().rpc('talk_all_rooms').then(function (r) { S.all = r.error ? [] : r.data || []; if (S.tab === 'all') $('tkBody').innerHTML = listBody(); });
    if (S.tab === 'settings') loadSettings();
  }
  function listBody() {
    var q = S.q.trim();
    if (S.tab === 'chat') {
      if (!S.rooms) return '<div class="tk-empty">불러오는 중…</div>';
      var list = S.rooms.filter(function (r) { return r.kind !== 'dm' || r.last_body; });
      if (S.filter === 'student') list = list.filter(function (r) { return r.kind === 'dm' && r.other_role === 'student'; });
      if (S.filter === 'staff') list = list.filter(function (r) { return r.kind === 'group' || (r.kind === 'dm' && r.other_role !== 'student'); });
      if (q) list = list.filter(function (r) { return roomName(r).indexOf(q) >= 0; });
      if (!list.length) return '<div class="tk-empty">아직 톡이 없어요.<br>「친구」에서 이름을 누르면 톡이 시작돼요.</div>';
      var out = ''; var hadPin = false;
      list.forEach(function (r, i) {
        if (i === 0 && r.pinned) { out += '<div class="tk-sec">고정</div>'; hadPin = true; }
        if (hadPin && i > 0 && list[i - 1].pinned && !r.pinned) out += '<div class="tk-sec">전체</div>';
        out += '<div class="tk-item" data-room="' + r.room_id + '">' + face(roomName(r), r.other_role !== 'student' ? r.other_avatar : null, r.kind) +
          '<div class="tk-it"><b>' + esc(roomName(r)) + '</b>' + (r.pinned ? ' 📌' : '') + (r.muted ? ' 🔕' : '') + '<div>' + esc(r.last_body || (r.kind === 'wanto' ? '자동 알림이 여기로 와요' : '')) + '</div></div>' +
          '<div class="tk-rt">' + (r.last_body ? whenShort(r.last_at) : '') + (r.unread ? '<span class="tk-un">' + (r.unread > 99 ? '99+' : r.unread) + '</span>' : '') + '</div>' +
          '<button class="tk-more" data-more="' + r.room_id + '" title="메뉴">⋯</button></div>';
      });
      return out;
    }
    if (S.tab === 'friends') {
      if (!S.contacts) return '<div class="tk-empty">불러오는 중…</div>';
      var out2 = '';
      [['staff', '선생님'], ['student', isOps(me()) ? '학생' : '내 학생']].forEach(function (g) {
        var l = S.contacts.filter(function (c) { return c.grp === g[0] && (!q || (c.name || '').indexOf(q) >= 0); });
        if (!l.length) return;
        out2 += '<div class="tk-sec">' + g[1] + ' · ' + l.length + '</div>' + l.map(function (c) { return '<div class="tk-item" data-user="' + c.id + '">' + face(c.name, c.grp === 'staff' ? c.avatar_url : null) + '<div class="tk-it"><b>' + esc(c.name) + '</b></div><span style="color:#ccc">›</span></div>'; }).join('');
      });
      return out2 || '<div class="tk-empty">톡할 수 있는 사람이 없어요.</div>';
    }
    if (S.tab === 'all') {
      if (!S.all) return '<div class="tk-empty">불러오는 중…</div>';
      return S.all.filter(function (r) { return !q || (r.names || '').indexOf(q) >= 0; }).map(function (r) { return '<div class="tk-item" data-peek="' + r.room_id + '" data-title="' + esc(r.names) + '">' + face(r.names) + '<div class="tk-it"><b>' + esc(r.names) + '</b><div>' + esc(r.last_body) + '</div></div><div class="tk-rt">' + whenShort(r.last_at) + '</div></div>'; }).join('') || '<div class="tk-empty">아직 톡이 없어요.</div>';
    }
    return '';
  }

  async function loadSettings() {
    var p = me(); var r = await sb().from('push_prefs').select('talk, quiet, quiet_from, quiet_to').eq('user_id', p.id).maybeSingle();
    var v = Object.assign({ talk: true, quiet: false, quiet_from: 23, quiet_to: 8 }, r.data || {});
    var muted = (S.rooms || []).filter(function (x) { return x.muted; });
    var h = '<div class="tk-set"><label>톡 알림 받기<input type="checkbox" id="tkSetTalk"' + (v.talk !== false ? ' checked' : '') + '></label><small>새 톡이 오면 폰 알림</small></div>' +
      '<div class="tk-set"><label>방해 금지 시간<input type="checkbox" id="tkSetQuiet"' + (v.quiet ? ' checked' : '') + '></label><small>그 시간엔 소리 없이 와요 · ' +
      '<select id="tkQf">' + [20, 21, 22, 23, 0].map(function (x) { return '<option' + (x === v.quiet_from ? ' selected' : '') + '>' + x + '</option>'; }).join('') + '</select>시 ~ ' +
      '<select id="tkQt">' + [6, 7, 8, 9].map(function (x) { return '<option' + (x === v.quiet_to ? ' selected' : '') + '>' + x + '</option>'; }).join('') + '</select>시</small></div>' +
      '<div class="tk-set"><label>톡 글자 크기</label><div class="tk-ops">' + [[0.9, '작게'], [1, '보통'], [1.18, '크게']].map(function (f) { return '<button class="tk-op' + (S.fs === f[0] ? ' on' : '') + '" data-fs="' + f[0] + '">' + f[1] + '</button>'; }).join('') + '</div></div>' +
      '<div class="tk-set"><label>알림 끈 톡방 ' + muted.length + '</label>' + (muted.length ? muted.map(function (m) { return '<div class="tk-mrow"><span style="flex:1">' + esc(roomName(m)) + '</span><button class="tk-op" data-unmute="' + m.room_id + '">알림 켜기</button></div>'; }).join('') : '<small>목록에서 ⋯ → 알림 끄기를 누르면 여기 모여요.</small>') + '</div>';
    var b = $('tkBody'); if (b) b.innerHTML = h;
    function save() {
      var row = { user_id: p.id, talk: $('tkSetTalk').checked, quiet: $('tkSetQuiet').checked, quiet_from: +$('tkQf').value, quiet_to: +$('tkQt').value, updated_at: new Date().toISOString() };
      sb().from('push_prefs').upsert(row, { onConflict: 'user_id' }).then(function (x) { toast(x.error ? '저장 못 했어요' : '저장했어요'); });
    }
    ['tkSetTalk', 'tkSetQuiet', 'tkQf', 'tkQt'].forEach(function (id) { var e = $(id); if (e) e.onchange = save; });
  }

  // ── 톡방 ──
  async function openRoom(id, title, kind, peek) {
    S.room = { id: id, title: title, kind: kind, peek: !!peek }; S.find = ''; S.limit = 150; S.msgs = [];
    renderRoom(); await loadMsgs(); if (!peek) markRead();
  }
  async function markRead() { if (!S.room) return; var r = await sb().rpc('talk_mark_read', { p_room: S.room.id }); if (!r.error) setBadge(r.data || 0); }
  async function loadMsgs() {
    if (!S.room) return;
    if (S.guest) {
      var g = await sb().rpc('talk_guest_read', { p_token: S.guest, p_after: 0 });
      S.msgs = g.data || []; paintMsgs(); scrollEnd(); return;
    }
    var r = await sb().from('talk_messages').select('id, room_id, sender_id, sender_name, kind, body, data, created_at').eq('room_id', S.room.id).order('created_at', { ascending: false }).limit(S.limit || 150);
    S.msgs = (r.data || []).reverse();
    if (S.room.kind === 'dm') { var m = await sb().from('talk_members').select('user_id, last_read_at').eq('room_id', S.room.id); var o = (m.data || []).filter(function (x) { return x.user_id !== me().id; })[0]; S.otherRead = o ? o.last_read_at : null; }
    var box = $('tkMsgs'); var atBottom = !box || box.scrollHeight - box.scrollTop - box.clientHeight < 80;
    paintMsgs(); if (atBottom && !S.find) scrollEnd();
    if (!S.room.peek) markRead();
  }
  function scrollEnd() { var b = $('tkMsgs'); if (b) b.scrollTop = b.scrollHeight; }
  function isConsult() { return S.room && S.room.kind === 'group' && S.room.title === '완토 상담'; }

  function renderRoom() {
    var p = me(); var r = S.room;
    var ro = r.peek || (r.kind === 'wanto' && !isStaff(p));
    var h = '<div class="tk-room"><div class="tk-rhead"><button data-a="back">‹</button><b>' + esc(r.title) + '</b>' + (r.peek ? '<span style="font-size:12px;color:#B26A00">보기만</span>' : '') +
      (S.guest ? '<button data-a="close" title="닫기">✕</button>' : '<button data-a="find" title="검색">🔍</button>' + (!r.peek && r.kind !== 'wanto' ? '<button data-a="menu" title="메뉴">☰</button>' : '')) + '</div>' +
      '<div id="tkFind" style="display:none" class="tk-findbar"><input id="tkFindQ" placeholder="대화 검색"><span id="tkFindN" style="font-size:13px;color:#6E6E78"></span><button data-a="fup">▲</button><button data-a="fdn">▼</button></div>' +
      '<div class="tk-msgs" id="tkMsgs"></div>' +
      (ro ? '<div class="tk-ro">' + (r.peek ? '원장·부원장·실장 보기 화면이에요' : '알림을 받는 톡이에요') + '</div>'
        : '<div class="tk-input">' + (S.guest ? '' : '<button class="tk-att" data-a="attach" title="사진·동영상·파일">＋</button>') + '<textarea id="tkText" rows="1" placeholder="메시지 입력 (Enter 보내기, Shift+Enter 줄바꿈)"></textarea><button class="tk-send" data-a="send">↑</button></div>') +
      '</div>';
    $('tkPanel').innerHTML = h;
    var t = $('tkText'); if (t) t.onkeydown = function (e) { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); } };
    var fq = $('tkFindQ'); if (fq) fq.oninput = function () { S.find = fq.value; S.hitAt = -1; paintMsgs(); jump(0, true); };
  }

  function bubble(m, mine) {
    var d = m.data || {}; var big = S.fs !== 1 ? ' style="font-size:' + (15.5 * S.fs).toFixed(1) + 'px"' : '';
    if (m.kind === 'image' && d.path) return '<img class="tk-img" data-path="' + esc(d.path) + '" alt="사진">';
    if (m.kind === 'video' && d.path) return '<a class="tk-file" href="#" data-open="' + esc(d.path) + '"><i>▶</i><div><b>동영상</b><div style="font-size:12px;color:#6E6E78">눌러서 보기</div></div></a>';
    if (m.kind === 'file' && d.path) return '<a class="tk-file" href="#" data-open="' + esc(d.path) + '"><i>' + esc(String(d.name || '').split('.').pop().toUpperCase().slice(0, 4) || 'FILE') + '</i><div><b>' + esc(d.name || m.body) + '</b><div style="font-size:12px;color:#6E6E78">' + (d.size ? (d.size / 1048576).toFixed(1) + 'MB · ' : '') + '눌러서 열기</div></div></a>';
    if (m.kind === 'task' || m.kind === 'task_done') {
      var done = m.kind === 'task_done';
      return '<div class="tk-card"' + (done ? ' style="background:#E8F7F0"' : '') + '><span class="tk-tag" style="' + (done ? 'color:#12855C' : 'color:#7A5AF0;background:#F0ECFE') + '">' + (done ? '완료' : '업무 지시') + '</span><br><b>' + esc(done ? '「' + m.body + '」 완료했어요' : m.body) + '</b>' + (!done && d.due ? '<br><span style="color:#6E6E78">마감 ' + sdate(String(d.due)) + '</span>' : '') + (!done && d.detail ? '<br><span style="color:#6E6E78">' + esc(d.detail) + '</span>' : '') + '</div>';
    }
    if (m.kind === 'renewal') return renewalCard(m);
    if (m.kind === 'notice') {
      if (d.consult) return consultCard(m);
      return '<div class="tk-card"' + big + '>' + esc(m.body) + '</div>';
    }
    var cls = m.kind === 'bot' ? ' tk-bot' : m.kind === 'claude' ? ' tk-claude' : '';
    return '<div class="tk-bb' + cls + '"' + big + '>' + (d.task_title ? '<span style="font-size:12px;opacity:.75">업무 「' + esc(d.task_title) + '」 답글</span>\n' : '') + esc(m.body) + '</div>';
  }

  function paintMsgs() {
    var box = $('tkMsgs'); if (!box) return; var p = me(); var msgs = S.msgs; var q = (S.find || '').trim().toLowerCase();
    var hits = []; var h = '';
    if (!msgs.length) h = '<div class="tk-empty">' + (S.room.kind === 'wanto' ? '결제 안내·수업 알림 같은 자동 알림이 여기로 와요.' : '첫 메시지를 보내 보세요.') + '</div>';
    var lastConsult = null; msgs.forEach(function (m) { if (m.kind === 'notice' && m.data && m.data.consult) lastConsult = m.id; }); S.lastConsult = lastConsult;
    msgs.forEach(function (m, i) {
      var prev = msgs[i - 1]; var newDay = !prev || ymd(prev.created_at) !== ymd(m.created_at);
      var mine = m.sender_id === p.id || (!!S.guest && m.sender_id == null && m.kind === 'text' && m.data && m.data.guest);
      var hit = q && (m.body + ' ' + ((m.data && m.data.name) || '')).toLowerCase().indexOf(q) >= 0; if (hit) hits.push(m.id);
      var name = m.kind === 'bot' ? '완토 · ' + (m.sender_name || '') : m.kind === 'claude' ? '검사' : (isConsult() && m.sender_id && m.sender_id !== p.id && isStaffName(m)) ? '완벽한토익' : (m.sender_name || '완토');
      var showName = !mine && (!prev || prev.sender_id !== m.sender_id || newDay);
      var unread = mine && S.room.kind === 'dm' && S.otherRead && m.created_at > S.otherRead;
      h += '<div id="tkm' + m.id + '"' + (hit && S.curHit === m.id ? ' class="tk-hit"' : '') + '>' + (newDay ? '<div class="tk-day"><span>' + sdate(ymd(m.created_at)) + '</span></div>' : '') +
        (showName ? '<div class="tk-nm">' + esc(name) + '</div>' : '') +
        '<div class="tk-row' + (mine ? ' me' : '') + '">' + (mine ? '<span class="tk-tm">' + (unread ? '<span class="tk-one">1</span>' : '') + hm(m.created_at) + '</span>' : '') + bubble(m, mine) + (!mine ? '<span class="tk-tm">' + hm(m.created_at) + '</span>' : '') +
        (!S.guest && (mine || isOps(p)) ? '<button class="tk-more" style="visibility:visible;opacity:.35" data-del="' + m.id + '" title="삭제">✕</button>' : '') + '</div></div>';
    });
    box.innerHTML = h; S.hits = hits;
    var n = $('tkFindN'); if (n) n.textContent = q ? (hits.length ? ((S.hitAt >= 0 ? S.hitAt : hits.length - 1) + 1) + '/' + hits.length : '0') : '';
    box.querySelectorAll('img[data-path]').forEach(function (img) { signed(img.getAttribute('data-path')).then(function (u) { if (u) img.src = u; }); });
    wireConsult(box);
  }
  var staffIds = null;
  function isStaffName(m) { if (S.guest) return !!m.sender_id; return staffIds ? staffIds[m.sender_id] : false; }
  function loadStaffIds() { sb().from('profiles').select('id').in('role', ['admin', 'master', 'manager']).then(function (r) { staffIds = {}; (r.data || []).forEach(function (x) { staffIds[x.id] = true; }); if (S.room) paintMsgs(); }); }

  function jump(step, toLatest) {
    var hits = S.hits || []; if (!hits.length) return;
    var k = toLatest ? hits.length - 1 : ((S.hitAt >= 0 ? S.hitAt : hits.length - 1) + step + hits.length) % hits.length;
    S.hitAt = k; S.curHit = hits[k]; paintMsgs();
    var el = $('tkm' + hits[k]); if (el) el.scrollIntoView({ block: 'center' });
  }

  var urlCache = {};
  async function signed(path) {
    if (urlCache[path]) return urlCache[path];
    var r = await sb().storage.from('talk').createSignedUrl(path, 3600); if (r.error) return null;
    urlCache[path] = r.data.signedUrl; return r.data.signedUrl;
  }

  async function send() {
    var t = $('tkText'); var body = (t.value || '').trim(); if (!body) return;
    t.value = ''; var p = me();
    if (S.guest) { var gr = await sb().rpc('talk_guest', { p_token: S.guest, p_name: null, p_phone: null, p_action: 'text', p_value: body }); if (gr.error) { toast(gr.error.message); t.value = body; } loadMsgs(); return; }
    var r = await sb().from('talk_messages').insert({ room_id: S.room.id, sender_id: p.id, sender_name: p.name, kind: 'text', body: body });
    if (r.error) { toast('보내지 못했어요: ' + r.error.message); t.value = body; return; }
    loadMsgs(); setTimeout(scrollEnd, 120);
  }
  async function onFiles(e) {
    var files = Array.prototype.slice.call(e.target.files || []); e.target.value = ''; if (!files.length || !S.room) return;
    var p = me();
    for (var i = 0; i < files.length; i++) {
      var f = files[i]; if (f.size > 50 * 1048576) { toast(f.name + ': 50MB 를 넘어요'); continue; }
      toast('올리는 중… ' + f.name);
      var kind = /^image\//.test(f.type) ? 'image' : /^video\//.test(f.type) ? 'video' : 'file';
      var ext = (f.name.match(/\.[A-Za-z0-9]{1,8}$/) || [''])[0].toLowerCase();
      var path = S.room.id + '/' + Date.now() + '-' + Math.random().toString(36).slice(2, 8) + ext;
      var up = await sb().storage.from('talk').upload(path, f, { contentType: f.type || 'application/octet-stream' });
      if (up.error) { toast('올리지 못했어요: ' + up.error.message); break; }
      var w = null, hgt = null;
      if (kind === 'image') { try { var bm = await createImageBitmap(f); w = bm.width; hgt = bm.height; } catch (x) {} }
      await sb().from('talk_messages').insert({ room_id: S.room.id, sender_id: p.id, sender_name: p.name, kind: kind, body: kind === 'file' ? f.name : '', data: { path: path, name: f.name, mime: f.type, size: f.size, w: w, h: hgt } });
    }
    loadMsgs(); setTimeout(scrollEnd, 200);
  }

  // ── 연장 카드(학생이 답함) ──
  function renewalCard(m) {
    var id = Number((m.data || {}).ask_id); var isStu = String((m.data || {}).student_id) === me().id;
    setTimeout(function () {
      sb().rpc('talk_renewal_state', { p_id: id }).then(function (r) {
        var el = $('tkrn' + m.id); if (!el) return; var s = r.data || {}; var h = '';
        if (s.paid_at) h = '<b style="color:#12855C">결제 확인됨</b>';
        else if (s.answer === 'end') h = '<b style="color:#12855C">그만하기로 함</b>';
        else if (isStu) {
          if (!s.answer) h = '<button class="tk-btn main" data-rn="renew" data-id="' + id + '">이어서 들을게요</button><button class="tk-btn" data-rn="end" data-id="' + id + '">그만할게요</button>';
          else if (s.answer === 'renew' && !s.pay_method) h = '<div style="color:#6E6E78;margin-top:6px">결제 방법을 골라 주세요</div><button class="tk-btn" data-rn="card0" data-id="' + id + '">대면 카드 (다음 수업 때)</button><button class="tk-btn" data-rn="card1" data-id="' + id + '">비대면 카드 (결제 링크)</button><button class="tk-btn main" data-rn="transfer" data-id="' + id + '">계좌이체</button>';
          else if (s.pay_method === 'transfer' && !s.claimed_at) h = '<button class="tk-btn main" data-rn="claim" data-id="' + id + '">이체했어요</button>';
          else h = '<b style="color:#12855C">답해 주셔서 고마워요!</b>';
        }
        el.innerHTML = h;
      });
    }, 0);
    return '<div class="tk-card"><span class="tk-tag" style="color:#0E9384;background:#E4F6F4">연장 확인</span><br><b>' + esc(m.body) + '</b><br><span style="color:#6E6E78">회차가 없으면 다음 예약이 늦어져 원하는 시간에 못 들을 수 있어요.</span><div id="tkrn' + m.id + '"></div></div>';
  }
  async function renewalAct(kind, id) {
    var r;
    if (kind === 'renew') r = await sb().rpc('answer_renewal', { p_id: id, p_answer: 'renew' });
    else if (kind === 'end') { if (!confirm('그만하시겠어요? 남은 수업까지만 듣고 끝나요.')) return; r = await sb().rpc('answer_renewal', { p_id: id, p_answer: 'end' }); }
    else if (kind === 'card0') r = await sb().rpc('renewal_pay', { p_id: id, p_method: 'card', p_online: false });
    else if (kind === 'card1') r = await sb().rpc('renewal_pay', { p_id: id, p_method: 'card', p_online: true });
    else if (kind === 'transfer') r = await sb().rpc('renewal_pay', { p_id: id, p_method: 'transfer', p_online: null });
    else if (kind === 'claim') r = await sb().rpc('renewal_claim', { p_id: id });
    if (r && r.error) toast(r.error.message); loadMsgs();
  }

  // ── 상담 카드(신규 학생) ──
  function consultCard(m) {
    var d = m.data || {}; var step = d.consult; var can = m.id === S.lastConsult && me().role === 'student';
    var h = '<div class="tk-card' + (d.important ? ' tk-imp' : '') + '" data-cstep="' + step + '" data-cid="' + m.id + '">' + (d.important ? '<b style="color:#D2483C">' : '') + esc(m.body) + (d.important ? '</b>' : '') +
      (d.image ? '<img src="' + esc(d.image) + '" data-zoom="' + esc(d.image) + '">' : '');
    if (can && step === 'types') h += '<div class="tk-ops">' + ['대면 1:1', '비대면 1:1', '2:1 수업'].map(function (t) { return '<button class="tk-op" data-pick="' + t + '">' + t + '</button>'; }).join('') + '</div><button class="tk-btn main" data-cgo="types">수업료 보기</button>';
    if (can && step === 'next') h += '<button class="tk-btn main" data-cgo="form_open">규칙 다 읽었어요 · 상담 양식 쓰기</button><button class="tk-btn" data-cgo="human">상담원 연결</button>';
    if (can && step === 'form') h += formHtml();
    if (can && step === 'times') { var out = ''; for (var i = 1; i <= 7; i++) { var dd = new Date(Date.now() + 9 * 3600e3 + i * 86400e3).toISOString().slice(0, 10); ['10시', '14시', '19시', '20시'].forEach(function (x) { out += '<button class="tk-op" data-pick="' + sdate(dd) + ' ' + x + '">' + sdate(dd) + ' ' + x + '</button>'; }); } h += '<div class="tk-ops">' + out + '</div><button class="tk-btn main" data-cgo="times">고른 시간 보내기</button><button class="tk-btn" data-cgo="human">상담원 연결 (시간 맞추기)</button>'; }
    if (step === 'pay') h += '<div style="background:#F5F7FB;border-radius:12px;padding:10px;margin-top:8px">기업은행 043-133434-01-013 · 완벽한토익 · <b>60,000원</b> <button class="tk-op" data-copy="043-133434-01-013">복사</button></div>' + (can ? '<input id="tkPayer" placeholder="입금자 이름(본인이면 비워 두세요)" style="width:100%;box-sizing:border-box;margin-top:8px;border:0;background:#F5F7FB;border-radius:10px;padding:10px;font:14px Pretendard,sans-serif"><button class="tk-btn main" data-cgo="paid">이체했어요</button><button class="tk-btn" data-cgo="card">카드로 결제할게요</button>' : '');
    return h + '</div>';
  }
  function formHtml() {
    function f(id, label, ph) { return '<div style="margin-top:8px;font-size:12.5px;color:#6E6E78;font-weight:700">' + label + '</div><input data-ff="' + id + '" placeholder="' + ph + '" style="width:100%;box-sizing:border-box;border:0;background:#F5F7FB;border-radius:10px;padding:9px;font:14px Pretendard,sans-serif">'; }
    return f('score', '1. 최근 토익 점수 (없으면 수능 등급·영어 수준)', '예: LC 300 RC 250') + f('goal', '2. 목표 점수', '예: 800') + f('period', '3. 목표 기간', '예: 2개월') + f('study', '4. 기존 학습방식', '학원·인강·과외·독학') + f('area', '5. 거주지 (시간 조율용)', '예: 마포구') + f('mode', '6. 수업 형태', '1:1 대면·비대면·2:1') + f('call', '8. 유선 상담 원하면 연락처·통화 가능 시간', '선택') + f('route', '9. 완벽한토익을 알게 된 경로', '인스타·네이버·지인 추천 등') + f('etc', '10. 기타 궁금한 점', '선택') + '<button class="tk-btn main" data-cgo="form">보내기</button><button class="tk-btn" data-cgo="human">상담원 연결</button>';
  }
  function wireConsult(box) {
    box.querySelectorAll('[data-pick]').forEach(function (b) { b.onclick = function () { b.classList.toggle('on'); }; });
  }
  async function consultGo(btn) {
    var card = btn.closest('[data-cstep]'); var act = btn.getAttribute('data-cgo'); var val = null;
    if (act === 'types' || act === 'times') { val = Array.prototype.map.call(card.querySelectorAll('[data-pick].on'), function (x) { return x.getAttribute('data-pick'); }); if (!val.length) { toast('하나 이상 골라 주세요'); return; } }
    if (act === 'form') { val = {}; card.querySelectorAll('[data-ff]').forEach(function (i) { val[i.getAttribute('data-ff')] = i.value.trim(); }); }
    if (act === 'paid') { var pe = $('tkPayer'); val = pe ? pe.value.trim() : ''; }
    btn.disabled = true;
    var r = S.guest ? await sb().rpc('talk_guest', { p_token: S.guest, p_name: null, p_phone: null, p_action: act, p_value: val })
                    : await sb().rpc('talk_consult', { p_action: act, p_value: val });
    if (r.error) { toast(r.error.message); btn.disabled = false; return; }
    loadMsgs(); setTimeout(scrollEnd, 200);
  }

  // ── 메뉴·초대·나가기·프로필 ──
  function sheet(inner) { var root = document.querySelector('#tkPanel .tk-room') || $('tkPanel'); var s = document.createElement('div'); s.className = 'tk-sheet'; s.innerHTML = '<div>' + inner + '</div>'; s.onclick = function (e) { if (e.target === s) s.remove(); }; root.style.position = 'relative'; root.appendChild(s); return s; }
  async function roomMenu() {
    var r = await sb().rpc('talk_room_members', { p_room: S.room.id }); var mem = r.data || [];
    var h = '<h4>대화상대 ' + mem.length + '</h4>' + mem.map(function (m) { return '<div class="tk-mrow">' + face(m.name, m.role !== 'student' ? m.avatar_url : null, null, 34) + '<span>' + esc(m.name) + '</span></div>'; }).join('') +
      (isStaff(me()) ? '<button class="tk-btn" data-a="invite">대화상대 초대</button>' : '') + '<button class="tk-btn" style="color:#D2483C;background:#FDEFED" data-a="leave">채팅방 나가기</button>';
    var s = sheet(h); s.dataset.members = JSON.stringify(mem.map(function (m) { return m.user_id; }));
  }
  async function inviteSheet(prev) {
    var inRoom = JSON.parse(prev.dataset.members || '[]'); prev.remove();
    var r = await sb().rpc('talk_contacts'); var list = (r.data || []).filter(function (c) { return inRoom.indexOf(c.id) < 0; });
    sheet('<h4>초대할 사람 고르기</h4><div style="color:#6E6E78;font-size:13px;margin-bottom:6px">' + (S.room.kind === 'dm' ? '새 단체방이 생기고, 지금 1:1 톡은 그대로 남아요.' : '이 방에 추가돼요.') + '</div>' + list.map(function (c) { return '<label class="tk-mrow"><input type="checkbox" value="' + c.id + '" data-nm="' + esc(c.name) + '">' + face(c.name, c.grp === 'staff' ? c.avatar_url : null, null, 32) + '<span>' + esc(c.name) + '</span></label>'; }).join('') + '<button class="tk-btn main" data-a="doinvite">초대</button>');
  }
  async function doInvite(s) {
    var ids = Array.prototype.map.call(s.querySelectorAll('input:checked'), function (x) { return x.value; }); if (!ids.length) return;
    var r = await sb().rpc('talk_invite', { p_room: S.room.id, p_users: ids }); if (r.error) { toast(r.error.message); return; }
    s.remove(); if (Number(r.data) !== S.room.id) openRoom(Number(r.data), '단체 톡', 'group'); else loadMsgs();
  }
  async function leaveRoom(id) {
    if (!confirm('이 방에서 나갈까요?')) return;
    var r = await sb().rpc('talk_leave', { p_room: id }); if (r.error) { toast(r.error.message); return; }
    S.room = null; renderList(); loadRooms();
  }
  async function roomRowMenu(id) {
    var r = (S.rooms || []).filter(function (x) { return x.room_id === id; })[0]; if (!r) return;
    var canLeave = !(r.kind === 'wanto' || (r.kind === 'group' && r.title === '선생님방'));
    var s = sheet('<h4>' + esc(roomName(r)) + '</h4><button class="tk-btn" data-pref="pin">' + (r.pinned ? '고정 풀기' : '맨 위에 고정') + '</button><button class="tk-btn" data-pref="mute">' + (r.muted ? '알림 켜기' : '알림 끄기') + '</button>' + (r.unread ? '<button class="tk-btn" data-pref="read">읽음 처리</button>' : '') + (canLeave ? '<button class="tk-btn" style="color:#D2483C;background:#FDEFED" data-pref="leave">나가기</button>' : ''));
    s.onclick = async function (e) {
      if (e.target === s) { s.remove(); return; }
      var k = e.target.getAttribute('data-pref'); if (!k) return; s.remove();
      if (k === 'pin') await sb().rpc('talk_set_pref', { p_room: id, p_pinned: !r.pinned, p_muted: null });
      if (k === 'mute') await sb().rpc('talk_set_pref', { p_room: id, p_pinned: null, p_muted: !r.muted });
      if (k === 'read') await sb().rpc('talk_mark_read', { p_room: id });
      if (k === 'leave') return leaveRoom(id);
      loadRooms();
    };
  }
  async function profileCard(uid) {
    var r = await sb().rpc('talk_profile', { p_id: uid }); if (r.error || !r.data) { toast('프로필을 못 불러왔어요'); return; }
    var p = r.data; var stu = p.role === 'student'; var phone = (p.phone || '').replace(/[^0-9+]/g, '');
    function w(iso) { return iso ? sdate(ymd(iso)) + ' ' + hm(iso) : '없음'; }
    function left(v) { return v == null ? '-' : v >= 9999 ? '무제한' : v + '회'; }
    var info = stu ? '<div><b>남은 수업</b>' + left(p.left) + '</div><div><b>다음 수업</b>' + w(p.next_at) + (p.next_room ? ' · ' + esc(p.next_room) : '') + '</div>' + (p.score ? '<div><b>최근 성적</b>LC ' + (p.score.lc || '-') + ' · RC ' + (p.score.rc || '-') + '</div>' : '')
      : p.my_next_at !== undefined ? '<div><b>다음 수업</b>' + w(p.my_next_at) + '</div><div><b>남은 수업</b>' + left(p.my_left) + '</div>'
        : '<div><b>오늘 수업</b>' + ((p.today || []).join(' · ') || '없음') + '</div>';
    var s = sheet('<div class="tk-pcard">' + face(p.name, stu ? null : p.avatar_url, null, 96) + '<div class="nm">' + esc(p.name) + '</div><div class="sub">' + (stu ? (p.mode === 'online' ? '비대면' : p.mode === 'offline' ? '대면' : '') + (p.teacher ? ' · 담당 ' + esc(p.teacher) + ' 쌤' : '') : p.students != null ? '담당 학생 ' + p.students + '명 · 오늘 수업 ' + ((p.today || []).length) + '개' : '완벽한토익 1:1 토익') + '</div>' +
      '<div class="tk-pbtns"><button data-a="pdm" data-uid="' + uid + '" data-nm="' + esc(p.name) + '"><span style="background:' + BRAND + '">💬</span>1:1 톡</button>' + (phone ? '<a href="tel:' + phone + '"><span style="background:#12855C">📞</span>전화</a>' : '') + '</div><div class="tk-pinfo">' + info + '</div></div>');
  }
  async function dmWith(uid, name) {
    var r = await sb().rpc('talk_open_dm', { p_other: uid }); if (r.error) { toast(r.error.message); return; }
    openRoom(Number(r.data), name || '톡', 'dm');
  }

  // ── 클릭 한 곳에서 처리 ──
  document.addEventListener('click', async function (e) {
    var panel = $('tkPanel'); if (!panel || !panel.contains(e.target)) return;
    var t = e.target.closest('[data-a],[data-t],[data-f],[data-room],[data-user],[data-peek],[data-more],[data-del],[data-open],[data-path],[data-zoom],[data-cgo],[data-copy],[data-rn],[data-fs],[data-unmute]');
    if (!t) return;
    var a = t.getAttribute('data-a');
    if (a === 'close') return closePanel();
    if (a === 'back') { if (S.guest) return closePanel(); S.room = null; renderList(); loadRooms(); return; }
    if (a === 'send') return send();
    if (a === 'attach') return $('tkFile').click();
    if (a === 'find') { var fb = $('tkFind'); fb.style.display = fb.style.display === 'none' ? 'flex' : 'none'; if (fb.style.display === 'flex') { S.limit = 1000; await loadMsgs(); $('tkFindQ').focus(); } else { S.find = ''; paintMsgs(); } return; }
    if (a === 'fup') return jump(-1); if (a === 'fdn') return jump(1);
    if (a === 'menu') return roomMenu();
    if (a === 'invite') return inviteSheet(t.closest('.tk-sheet'));
    if (a === 'doinvite') return doInvite(t.closest('.tk-sheet'));
    if (a === 'leave') { t.closest('.tk-sheet').remove(); return leaveRoom(S.room.id); }
    if (a === 'pdm') { t.closest('.tk-sheet').remove(); return dmWith(t.getAttribute('data-uid'), t.getAttribute('data-nm')); }
    if (t.hasAttribute('data-t')) { S.tab = t.getAttribute('data-t'); S.q = ''; if (S.tab === 'friends') S.contacts = null; if (S.tab === 'all') S.all = null; return renderList(); }
    if (t.hasAttribute('data-f')) { S.filter = t.getAttribute('data-f'); return renderList(); }
    if (t.hasAttribute('data-more')) { e.stopPropagation(); return roomRowMenu(Number(t.getAttribute('data-more'))); }
    if (t.hasAttribute('data-room')) { var id = Number(t.getAttribute('data-room')); var r = (S.rooms || []).filter(function (x) { return x.room_id === id; })[0]; if (e.target.closest('.tk-face') && r && r.kind === 'dm' && r.other_id) return profileCard(r.other_id); return openRoom(id, r ? roomName(r) : '톡', r ? r.kind : 'dm'); }
    if (t.hasAttribute('data-user')) return profileCard(t.getAttribute('data-user'));
    if (t.hasAttribute('data-peek')) return openRoom(Number(t.getAttribute('data-peek')), t.getAttribute('data-title'), 'dm', true);
    if (t.hasAttribute('data-del')) { if (!confirm('이 메시지를 지울까요?')) return; var d = await sb().from('talk_messages').delete().eq('id', Number(t.getAttribute('data-del'))); if (d.error) toast(d.error.message); return loadMsgs(); }
    if (t.hasAttribute('data-open')) { e.preventDefault(); var u = await signed(t.getAttribute('data-open')); if (u) window.open(u, '_blank'); return; }
    if (t.hasAttribute('data-path')) { var u2 = await signed(t.getAttribute('data-path')); if (u2) window.open(u2, '_blank'); return; }
    if (t.hasAttribute('data-zoom')) { window.open(t.getAttribute('data-zoom'), '_blank'); return; }
    if (t.hasAttribute('data-cgo')) return consultGo(t);
    if (t.hasAttribute('data-copy')) { try { await navigator.clipboard.writeText(t.getAttribute('data-copy')); toast('계좌번호를 복사했어요'); } catch (x) {} return; }
    if (t.hasAttribute('data-rn')) return renewalAct(t.getAttribute('data-rn'), Number(t.getAttribute('data-id')));
    if (t.hasAttribute('data-fs')) { S.fs = Number(t.getAttribute('data-fs')); try { localStorage.setItem('talk_fs', String(S.fs)); } catch (x) {} return loadSettings(); }
    if (t.hasAttribute('data-unmute')) { await sb().rpc('talk_set_pref', { p_room: Number(t.getAttribute('data-unmute')), p_pinned: null, p_muted: false }); await loadRooms(); return loadSettings(); }
  });

  // ── 「수업 신청은 Talk 에서」 (2026-11-28 원장님) ──
  // 상담·수업 신청 카톡 버튼을 누르면 카톡 대신 안내창 → 웹 Talk 「완토 상담」 또는 앱
  // 회원이 아니면 이름·연락처만 받고 바로 상담 (2026-11-28 원장님 「회원 아닌 애들도 열게」)
  function guestStart() {
    mount();
    var tok = guestToken(); if (!tok) { toast('이 브라우저에서는 상담을 열 수 없어요'); return; }
    var known = null; try { known = localStorage.getItem('tk_guest_name'); } catch (e) {}
    S.open = true; $('tkPanel').classList.add('on'); var fab = $('tkFab'); if (fab) fab.style.display = 'none';
    if (known) return guestOpen(tok, null, null);
    $('tkPanel').innerHTML = '<div class="tk-head"><b>완토 상담</b><button class="tk-x" data-a="close">✕</button></div>' +
      '<div style="padding:10px 18px;color:#5A6478;font-size:14.5px;line-height:1.6">회원가입 없이 바로 상담할 수 있어요.<br>답장을 드릴 수 있게 이름과 연락처만 적어 주세요.</div>' +
      '<div style="padding:0 18px;display:flex;flex-direction:column;gap:10px"><input id="tkGName" placeholder="이름" style="border:0;background:#F5F5F5;border-radius:12px;padding:12px;font:15px Pretendard,sans-serif">' +
      '<input id="tkGPhone" placeholder="연락처 (010-0000-0000)" inputmode="tel" style="border:0;background:#F5F5F5;border-radius:12px;padding:12px;font:15px Pretendard,sans-serif">' +
      '<label style="font-size:13px;color:#6E6E78"><input type="checkbox" id="tkGAgree"> 상담을 위해 이름·연락처를 받는 것에 동의해요</label>' +
      '<button class="tk-btn main" id="tkGGo">상담 시작하기</button>' +
      '<div style="font-size:13px;color:#6E6E78;line-height:1.6;margin-top:6px">완토 앱을 설치하면 답장 알림도 받고 숙제·수업 일정까지 한곳에서 볼 수 있어 더 편리해요.</div></div>';
    $('tkGGo').onclick = function () {
      var nm = $('tkGName').value.trim(), ph = $('tkGPhone').value.trim();
      if (!nm || !ph) return toast('이름과 연락처를 적어 주세요');
      if (!$('tkGAgree').checked) return toast('동의에 체크해 주세요');
      guestOpen(tok, nm, ph);
    };
  }
  async function guestOpen(tok, nm, ph) {
    var r = await sb().rpc('talk_guest', { p_token: tok, p_name: nm, p_phone: ph, p_action: 'start', p_value: null });
    if (r.error) { toast(r.error.message); try { localStorage.removeItem('tk_guest_name'); } catch (e) {} return guestStart(); }
    try { if (nm) localStorage.setItem('tk_guest_name', nm); } catch (e) {}
    S.guest = tok; S.guestMe = { id: 'guest', role: 'student', name: nm || '손님' };
    S.room = { id: Number(r.data), title: '완토 상담', kind: 'group', peek: false };
    renderRoom(); await loadMsgs();
    if (S.guestTimer) clearInterval(S.guestTimer);
    S.guestTimer = setInterval(function () { if (S.open && S.guest) loadMsgs(); }, 6000);
  }

  async function openConsult() {
    var p = window.WT_REAL_PROFILE || window.WT_PROFILE || null;
    // 2026-11-28 원장님 시안 C — 비회원은 가입하고 Talk 로(가입 끝나면 바로 완토 상담이 열린다)
    if (!p) { try { sessionStorage.setItem('tk_after_login', '1'); } catch (e) {} if (window.waOpenSignupModal) window.waOpenSignupModal(); else if (window.waOpenLogin) window.waOpenLogin(); return; }
    await openPanel();
    if (p.role === 'student') {
      var r = await sb().rpc('talk_consult', { p_action: 'start', p_value: null });
      if (!r.error && r.data) openRoom(Number(r.data), '완토 상담', 'group');
    }
  }
  function applyModal() {
    if ($('tkApply')) return;
    var d = document.createElement('div'); d.id = 'tkApply';
    d.style.cssText = 'position:fixed;inset:0;background:rgba(20,28,45,.45);z-index:10001;display:flex;align-items:center;justify-content:center;padding:16px';
    var logged = !!(window.WT_REAL_PROFILE || window.WT_PROFILE);
    d.innerHTML = '<div style="width:380px;max-width:100%;background:#fff;border-radius:20px;padding:24px;text-align:center;font-family:Pretendard,sans-serif">' +
      '<div style="font-size:30px">💬</div><div style="font-size:21px;font-weight:800;margin:8px 0">어떻게 상담할까요?</div>' +
      '<div style="color:#5A6478;font-size:14.5px;line-height:1.6">완토 Talk에서는 수업료·사전 OT 안내부터<br>결제까지 한 번에 진행돼요.</div>' +
      '<button id="tkApGo" class="tk-btn main" style="box-sizing:border-box;height:48px;padding:0;margin-top:16px">' + (logged ? 'Talk로 상담하기' : '가입하고 Talk로 상담하기') + '</button>' +
      '<a href="https://pf.kakao.com/_JCLYG/chat" target="_blank" rel="noopener" id="tkApK" class="tk-btn" style="box-sizing:border-box;height:48px;line-height:48px;padding:0;margin-top:10px;background:#FEE500;color:#191919;text-decoration:none;text-align:center">카카오톡으로 상담하기</a>' +
      '<div style="margin-top:12px;font-size:13px;color:#6E6E78;line-height:1.6">완토 앱을 설치하면 답장 알림도 받고 숙제·수업 일정까지 한곳에서 볼 수 있어 더 편리해요.</div>' +
      '<button id="tkApX" style="margin-top:10px;border:0;background:none;color:#A3A3AD;font:14px Pretendard,sans-serif;cursor:pointer">닫기</button></div>';
    document.body.appendChild(d);
    if (!document.getElementById('tkCss')) { var st = document.createElement('style'); st.id = 'tkCss'; st.textContent = css; document.head.appendChild(st); }
    d.onclick = function (e) { if (e.target === d) d.remove(); };
    $('tkApX').onclick = function () { d.remove(); };
    $('tkApK').onclick = function () { setTimeout(function () { d.remove(); }, 50); };
    $('tkApGo').onclick = function () { d.remove(); openConsult(); };
  }
  // 상담·수업 신청 카톡 링크만 가로챈다(교재 구매·채용·제안 문의는 그대로 카톡)
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[href*="pf.kakao.com/_JCLYG"]');
    if (!a || a.id === 'tkApK') return;
    var txt = (a.textContent || '') + ' ' + (a.getAttribute('aria-label') || '');
    if (/교재|채용|제안|자료/.test(txt)) return;
    var p = me(); if (p && isStaff(p)) return; // 직원은 원래대로
    e.preventDefault(); e.stopPropagation(); applyModal();
  }, true);
  window.WTTalkApply = applyModal;

  function boot() {
    var p = me();
    if (!p || !window.sb) { unmount(); return; }
    mount(); refreshUnread(); startLive(); if (!staffIds) loadStaffIds();
    try { if (sessionStorage.getItem('tk_after_login') === '1') { sessionStorage.removeItem('tk_after_login'); setTimeout(openConsult, 600); } } catch (e) {}
  }
  window.addEventListener('wt-auth', boot);
  if (document.readyState !== 'loading') setTimeout(boot, 1500); else document.addEventListener('DOMContentLoaded', function () { setTimeout(boot, 1500); });
  window.WTTalk = { open: openPanel };
})();
