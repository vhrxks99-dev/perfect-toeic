// 스윽 웹 구매 (2026-11-25). 로그인 = 스윽 서버(perca) 카카오·구글, 결제 = 다날 V2 통합결제창.
// 승인은 perca Edge Function seuk-danal-return 이 하고, 성공하면 purchases 에 'set' 한 줄이 생긴다.
// ── 바꿀 곳 ── 다날 실제 키를 받으면 아래 둘을 바꾸고 TEST 를 false 로. Secret Key 는 절대 여기 넣지 말 것.
const DANAL_CLIENT_KEY = 'CL_NZbhSKdB5EePW6YCj2KVF7FDkLbi3V-w_ZQ0CjNSZ-A=';
const DANAL_MID = '9810030929';
const MOBILE_ITEM = '1270000000';
const TEST = true;
// 11/26 원장님: 스윽 앱이 스토어에 나오기 전까지 웹 결제를 막아 둔다(웹에서 사도 받을 앱이 없음).
//   앱 출시하면 OPEN = true. 시험할 때는 주소 끝에 ?open=1
const OPEN = false || new URLSearchParams(location.search).get('open') === '1';
// ────────────────────────────────────────────
const SB_URL = 'https://rdocmjqemozmykgkfvkp.supabase.co';
const SB_KEY = 'sb_publishable_UCqT5rdfWMhd3o-Yx5n4JQ_COQ6IB4e';
const RET = SB_URL + '/functions/v1/seuk-danal-return';
const sb = supabase.createClient(SB_URL, SB_KEY, { auth: { flowType: 'pkce', detectSessionInUrl: true, persistSession: true } });
const $ = (s) => document.querySelector(s);
const K_OPEN = 'seuk.buy.open';
let user = null, busy = false, pm = 'card';
const PLANS = {
  lv1: { name: '스윽 기초', price: 20300 },
  lv2: { name: '스윽 실전', price: 34300 },
  lv3: { name: '스윽 고득점', price: 27300 },
  set: { name: '스윽 완성 (세트)', price: 55300 },
};
let plan = 'set';
const won = (n) => n.toLocaleString('ko-KR') + '원';
function showPlan() {
  $('#pick').textContent = '고른 이용권: ' + PLANS[plan].name + ' · ' + won(PLANS[plan].price);
  $('#paybtn').textContent = won(PLANS[plan].price) + (pm === 'bank' ? ' 무통장입금 신청' : ' 결제하기');
}

if (TEST) $('#testband').hidden = false;

function store(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch (e) { /* 없음 */ } }
function read(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }

function nameOf(u) {
  const m = (u && u.user_metadata) || {};
  return m.full_name || m.name || m.nickname || m.preferred_username || (u && u.email) || '';
}

async function owned() {
  const { data } = await sb.from('purchases').select('product').eq('user_id', user.id);
  return (data || []).some((r) => r.product === 'set' || r.product === plan);
}

async function render() {
  const { data } = await sb.auth.getSession();
  user = data.session ? data.session.user : null;
  $('#b_login').hidden = !!user;
  $('#b_pay').hidden = true;
  $('#b_owned').hidden = true;
  if (!user) return;
  const prov = (user.app_metadata && user.app_metadata.provider) || '';
  const pv = { kakao: '카카오', google: '구글', apple: '애플' }[prov] || '';
  $('#who').textContent = (pv ? pv + ' · ' : '') + (nameOf(user) || '로그인됨');
  if (await owned()) { $('#b_owned').hidden = false; return; }
  $('#b_pay').hidden = false;
}

function openBuy(p) {
  if (!OPEN) { $('#soon').hidden = false; $('#soon').scrollIntoView({ behavior: 'smooth', block: 'center' }); return; }
  if (p && PLANS[p]) plan = p;
  store('seuk.buy.plan', plan);
  showPlan();
  render();
  $('#buy').hidden = false;
  store(K_OPEN, '1');
  $('#buy').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

document.querySelectorAll('button[data-plan]').forEach((b) => b.addEventListener('click', () => openBuy(b.dataset.plan)));

async function login(provider) {
  store(K_OPEN, '1');
  const { error } = await sb.auth.signInWithOAuth({
    provider,
    options: { redirectTo: location.origin + '/seuk/', scopes: provider === 'kakao' ? 'profile_nickname profile_image' : undefined },
  });
  if (error) alert('로그인을 시작하지 못했어요. 잠시 뒤 다시 해 주세요.');
}
$('#lg_kakao').onclick = () => login('kakao');
$('#lg_google').onclick = () => login('google');
$('#logout').onclick = async () => { await sb.auth.signOut(); render(); };
$('#f_agree').addEventListener('change', () => $('#w_agree').classList.remove('bad'));
document.querySelectorAll('.pmb').forEach((b) => b.addEventListener('click', () => {
  pm = b.dataset.pm;
  document.querySelectorAll('.pmb').forEach((x) => x.classList.toggle('on', x === b));
  $('#w_bname').hidden = pm !== 'bank';
  if (TEST) $('#testband').hidden = pm === 'bank';
  $('#pm_note').textContent = pm === 'bank'
    ? '신청하면 입금할 계좌와 입금자명이 나와요. 입금이 확인되면 이 계정에 이용권이 열려요(평일 낮에는 보통 몇 시간 안에 확인).'
    : '신용·체크카드, 휴대폰으로 결제할 수 있어요. 「결제하기」를 누르면 다날 결제창에서 고르면 돼요.';
  showPlan();
}));

async function bankOrder() {
  const nm = $('#f_bname').value.trim();
  if (!nm) { $('#f_bname').focus(); alert('입금하실 분 이름을 적어 주세요.'); return; }
  busy = true;
  const b = $('#paybtn'); b.disabled = true; b.textContent = '신청하는 중…';
  try {
    const { data: o, error } = await sb.rpc('web_order_new_bank', { p_product: plan, p_name: nm });
    if (error) throw new Error('신청을 만들지 못했어요.');
    if (o.error) {
      const m = { login: '다시 로그인해 주세요.', owned: '이미 가지고 있는 이용권이에요.', too_many: '오늘 신청이 이미 여러 번 있어요. 카톡으로 문의해 주세요.', bad_name: '이름을 다시 확인해 주세요.' };
      throw new Error(m[o.error] || '신청을 만들지 못했어요.');
    }
    const box = $('#bankdone'); box.hidden = false;
    const acct = o.account.replace(/-/g, '');
    box.innerHTML = `<h3>무통장입금 신청이 접수됐어요</h3>
      <div class="row"><span>은행</span><b>${o.bank}</b></div>
      <div class="row"><span>계좌번호</span><b>${o.account}<button class="cp" data-c="${acct}">복사</button></b></div>
      <div class="row"><span>예금주</span><b>${o.holder}</b></div>
      <div class="row"><span>입금 금액</span><b>${won(o.amount)}</b></div>
      <div class="row"><span>입금자명</span><b>${o.depositor}<button class="cp" data-c="${o.depositor}">복사</button></b></div>
      <p>· 입금자명을 위와 똑같이 적어 주세요. 다르면 확인이 늦어져요.<br>· 24시간 안에 입금해 주세요. 확인되면 지금 로그인한 계정에 「${o.order_name}」이 열려요.<br>· 현금영수증이 필요하면 카톡 채널로 번호를 알려 주세요.<br>· 신청번호 ${o.order_id}</p>`;
    box.querySelectorAll('.cp').forEach((c) => c.onclick = () => { navigator.clipboard && navigator.clipboard.writeText(c.dataset.c); c.textContent = '복사됨'; });
    $('#b_pay').hidden = true;
    box.scrollIntoView({ behavior: 'smooth', block: 'center' });
  } catch (e) {
    alert((e && e.message) || '신청하지 못했어요.');
  } finally {
    busy = false; b.disabled = false; showPlan();
  }
}

$('#paybtn').onclick = async () => {
  if (busy) return;
  if (!$('#f_agree').checked) { $('#w_agree').classList.add('bad'); return; }
  if (pm === 'bank') { await bankOrder(); return; }
  if (typeof DanalPayments !== 'function') { alert('결제창을 불러오지 못했어요. 새로고침해 보시고, 계속 안 되면 카톡으로 알려 주세요.'); return; }
  busy = true;
  const b = $('#paybtn'); b.disabled = true; b.textContent = '결제창 여는 중…';
  try {
    const nm = nameOf(user);
    const { data: o, error } = await sb.rpc('web_order_new', { p_product: plan, p_name: nm || null });
    if (error) throw new Error('주문을 만들지 못했어요.');
    if (o.error) {
      const m = { login: '다시 로그인해 주세요.', owned: '이미 가지고 있는 이용권이에요.', too_many: '주문이 너무 여러 번 만들어졌어요. 10분 뒤 다시 해 주세요.' };
      if (o.error === 'owned') { render(); }
      throw new Error(m[o.error] || '주문을 만들지 못했어요.');
    }
    await DanalPayments(DANAL_CLIENT_KEY).requestPayment({
      merchantId: DANAL_MID, orderId: o.order_id, orderName: o.order_name, amount: o.amount,
      userId: 's' + user.id.replace(/-/g, '').slice(0, 12), userName: nm || '스윽 회원',
      successUrl: RET + '?r=ok', failUrl: RET + '?r=fail',
      paymentsMethod: 'INTEGRATED',
      methods: { card: {}, mobile: { itemCode: MOBILE_ITEM } },   // 11/27 다날 계약: 카드·휴대폰만
    });
  } catch (e) {
    alert((e && e.message) || '결제를 시작하지 못했어요.');
  } finally {
    busy = false; b.disabled = false; showPlan();
  }
};

sb.auth.onAuthStateChange(() => setTimeout(render, 0));   // 콜백 안에서 바로 DB 호출하면 supabase-js 가 멈춤
(async () => {
  const sp = read('seuk.buy.plan');
  if (sp && PLANS[sp]) plan = sp;
  showPlan();
  await render();
  if (read(K_OPEN) === '1' && user) openBuy();
})();
