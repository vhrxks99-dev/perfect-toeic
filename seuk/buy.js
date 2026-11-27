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
let user = null, busy = false;
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
  $('#paybtn').textContent = won(PLANS[plan].price) + ' 결제하기';
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

$('#paybtn').onclick = async () => {
  if (busy) return;
  if (!$('#f_agree').checked) { $('#w_agree').classList.add('bad'); return; }
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

sb.auth.onAuthStateChange(() => render());
(async () => {
  const sp = read('seuk.buy.plan');
  if (sp && PLANS[sp]) plan = sp;
  showPlan();
  await render();
  if (read(K_OPEN) === '1' && user) openBuy();
})();
