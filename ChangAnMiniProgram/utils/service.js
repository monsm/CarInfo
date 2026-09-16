// service.js —— 网络层与接口封装（对应桌面版 CarClient + MainForm 中的接口调用）
const md5 = require('./md5');
const C = require('./config');

const TOKEN_KEY = 'car_token_config';

// ---------- 原始请求/响应日志（调试用） ----------
// 每次网络请求都会记录【请求原文 + 响应原文】各一条，存本地（最近 RAW_LOG_MAX 条）
// 并同步 console.log 输出（开发者工具 Console / 真机 vConsole 可见）。
// 登录页底部有「查看最近请求日志」入口可直接阅读；排查短信/登录失败、
// 核对服务端到底回了什么原文时用得上。
const RAW_LOG_KEY = 'changan_raw_log';
const RAW_LOG_MAX = 60;       // 最多保留条数
const RAW_LOG_CHARS = 3000;   // 单条正文过长时截断，防 storage 爆

function _clipText(s, n = RAW_LOG_CHARS) {
  if (s === undefined || s === null) return String(s);
  const t = typeof s === 'string' ? s : (() => { try { return JSON.stringify(s); } catch (e) { return String(s); } })();
  return t.length > n ? `${t.slice(0, n)}…(截断,共${t.length}字符)` : t;
}
function _now() {
  const d = new Date();
  const p = x => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
function _rawLogPush(dir, method, url, body) {
  const entry = `[${_now()}] ${dir} ${method} ${url}\n${_clipText(body)}`;
  try { console.log('[changan] ' + entry); } catch (e) { /* ignore */ }
  try {
    let list = wx.getStorageSync(RAW_LOG_KEY);
    if (!Array.isArray(list)) list = [];
    list.unshift(entry);
    if (list.length > RAW_LOG_MAX) list.length = RAW_LOG_MAX;
    wx.setStorageSync(RAW_LOG_KEY, list);
  } catch (e) { /* ignore */ }
}
// 读最近日志（新→旧）。storage 可能因版本升级丢失，属正常。
function getRawLogs() {
  try { const l = wx.getStorageSync(RAW_LOG_KEY); return Array.isArray(l) ? l : []; } catch (e) { return []; }
}
function clearRawLogs() {
  try { wx.removeStorageSync(RAW_LOG_KEY); } catch (e) { /* ignore */ }
}

// 最近一次云函数响应里返回的 changanProxy 版本号（诊断用：确认线上部署的是否为带连接池/重试的新版）
let fnVersion = '';
function getFnVersion() { return fnVersion; }

function getTokenCfg() {
  try { return wx.getStorageSync(TOKEN_KEY) || null; } catch (e) { return null; }
}
function saveTokenCfg(cfg) {
  wx.setStorageSync(TOKEN_KEY, cfg);
  const app = getApp();
  if (app && app.globalData) {
    app.globalData.isLoggedIn = !!cfg.accessToken;
    app.globalData.phone = cfg.mobile || '';
  }
}

// ---------- 底层请求 ----------
// opts.forceDirect=true 时强制走 wx.request（登录相关接口可用，见 config.LOGIN_VIA_DIRECT）
// request() 负责记录原始报文（REQ/RES/ERR），实际转发逻辑在 requestCore()。
function request(opts) {
  const { url, method = 'POST', data, raw, token } = opts;
  const payload = raw !== undefined ? raw : data;
  // REQ 原文：请求体按原样记录；Authorization 打码避免 token 泄露到日志/存储
  const maskedHdr = { 'content-type': 'application/json' };
  if (token) maskedHdr['Authorization'] = 'Bearer ' + token.slice(0, 10) + '…(已打码)';
  _rawLogPush('REQ', method, url, `headers=${_clipText(maskedHdr, 400)}\nbody=${_clipText(payload, RAW_LOG_CHARS)}`);
  return requestCore(opts).then(
    res => {
      // RES 原文：文本按原样记录；二进制（图片）只记大小不 dump
      let bodyInfo;
      if (res && res.body instanceof ArrayBuffer) bodyInfo = `[二进制 ${res.body.byteLength} 字节]`;
      else if (res && typeof res.text === 'string') bodyInfo = res.text;
      else bodyInfo = res ? _clipText(res.body, RAW_LOG_CHARS) : '';
      const hdr = (res && res.header) ? _clipText(res.header, 800) : '';
      _rawLogPush('RES', method, url, `HTTP ${res && res.statusCode} headers=${hdr}\nbody=${bodyInfo}`);
      return res;
    },
    err => {
      // ERR 原文：云函数/服务端在错误里已附原始响应的截断（HTTP xxx: 正文）
      _rawLogPush('ERR', method, url, (err && (err.message || String(err))) || '未知错误');
      throw err;
    }
  );
}

// 底层转发（云函数模式 / 直连模式），不直接对外；由 request() 包裹记录原文日志。
function requestCore(opts) {
  const { url, method = 'POST', data, raw, token, responseType, forceDirect } = opts;
  const header = {};
  header['content-type'] = 'application/json';
  if (token) header['Authorization'] = 'Bearer ' + token;
  const payload = raw !== undefined ? raw : data;

  // 云函数模式：请求经 changanProxy 转发，不受 request 合法域名限制
  if (C.USE_CLOUD && !forceDirect) {
    return new Promise((resolve, reject) => {
      if (!wx.cloud || !wx.cloud.callFunction) {
        reject(new Error('云开发未初始化：请在开发者工具点击「云开发」开通，并部署 changanProxy 云函数（详见 README）'));
        return;
      }
      wx.cloud.callFunction({
        name: C.CLOUD_FUNC,
        data: { url, method, data: payload, headers: header },
        success(res) {
          const r = res.result || {};
          // 记录云函数版本头（changanProxy 在响应里附加 x-fn-version）
          const hdrs = r.headers || {};
          const ver = hdrs['x-fn-version'] || hdrs['X-Fn-Version'];
          if (ver) fnVersion = ver;
          if (!r.ok) {
            reject(new Error(`云函数转发失败：${r.error || '未知错误'}`));
            return;
          }
          // 二进制响应（验证码图片）
          if (r.base64) {
            let body;
            try { body = wx.base64ToArrayBuffer(r.base64); } catch (e) { body = r.base64; }
            resolve({ statusCode: r.statusCode, header: r.headers || {}, body });
            return;
          }
          const text = r.text || '';
          if (text && /token expired/i.test(text)) {
            const err = new Error('token expired');
            err.expired = true;
            reject(err);
            return;
          }
          if (r.statusCode < 200 || r.statusCode >= 300) {
            const err = new Error(`HTTP ${r.statusCode}: ${(text || '').slice(0, 200)}`);
            err.statusCode = r.statusCode;
            reject(err);
            return;
          }
          resolve({ statusCode: r.statusCode, header: r.headers || {}, text, body: text });
        },
        fail(err) {
          reject(new Error(`云函数调用失败：${(err && (err.errMsg || err.message)) || '未知错误'}（请确认已部署 changanProxy 云函数）`));
        }
      });
    });
  }

  // 直连模式（调试用）
  return new Promise((resolve, reject) => {
    wx.request({
      url,
      method,
      data: payload,
      header,
      responseType: responseType || 'text',
      timeout: 15000,
      success(res) {
        const body = res.data;
        // ArrayBuffer（验证码图片等）
        if (body instanceof ArrayBuffer) { resolve({ statusCode: res.statusCode, header: res.header, body }); return; }
        let text = body;
        if (typeof body !== 'string') {
          try { text = JSON.stringify(body); } catch (e) { text = String(body); }
        }
        if (text && /token expired/i.test(text)) {
          const err = new Error('token expired');
          err.expired = true;
          reject(err);
          return;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          const err = new Error(`HTTP ${res.statusCode}: ${(text || '').slice(0, 200)}`);
          err.statusCode = res.statusCode;
          reject(err);
          return;
        }
        resolve({ statusCode: res.statusCode, header: res.header, text, body });
      },
      fail(err) {
        reject(networkError(err));
      }
    });
  });
}

// 把 wx.request 的失败原因翻译成可操作的提示（否则用户只看到“网络请求失败”四个字）
function networkError(err) {
  const raw = (err && (err.errMsg || err.message)) || '';
  const low = String(raw).toLowerCase();
  if (/url not in domain|domain list/.test(low)) {
    return new Error('网络请求失败：域名未通过校验。请在开发者工具「详情 → 本地设置」勾选“不校验合法域名…”，真机预览需开启“调试模式”（详见 README）');
  }
  if (/timeout|timed out/.test(low)) {
    return new Error(`网络请求失败：请求超时（${raw}）。请检查网络后点击重试`);
  }
  if (/ssl|tls|certificate|证书|handshake/.test(low)) {
    return new Error(`网络请求失败：SSL/TLS 握手失败（${raw}），服务器证书或 TLS 版本可能不满足微信要求`);
  }
  if (/getaddrinfo|dns|resolve|notfound|找不到/.test(low)) {
    return new Error(`网络请求失败：域名解析失败（${raw}），请检查网络连接`);
  }
  if (/refused|connection|connect/.test(low)) {
    return new Error(`网络请求失败：无法建立连接（${raw}），请检查网络后重试`);
  }
  return new Error(`网络请求失败：${raw || '未知原因（errMsg 为空）'}`);
}

const sleep = ms => new Promise(res => setTimeout(res, ms));

// 判断响应是否为「找不到该手机号的图形验证码记录」（{"msg":null,"code":500}）。
// 与验证码输错（{"code":500}，无 msg）区分：无记录 = 短信绝未下发 → 重试安全。
function isNoRecordResp(text) {
  const t = text || '';
  return t.indexOf('"msg":null') >= 0 && /"code"\s*:\s*500/.test(t);
}

// 对“可安全重试”的请求（仅 GET 等幂等请求）做一次自动重试；
// 注意：发短信/登录等 POST 请求不在此重试（smsSend 内部仅对“无记录”做一次安全重试）。
async function requestWithRetry(opts, retries = 1) {
  let lastErr;
  for (let i = 0; i <= retries; i++) {
    try {
      return await request(opts);
    } catch (err) {
      lastErr = err;
      if (err.expired || err.statusCode) throw err; // 业务类错误不重试
      if (i < retries) await new Promise(r => setTimeout(r, 600 * (i + 1)));
    }
  }
  throw lastErr;
}

function parseJson(text) {
  try { return text ? JSON.parse(text) : null; } catch (e) { return null; }
}

// 解析响应对象：返回 { data, ok, msg }
// 与桌面版 JsonOptions.AllowReadingFromString 对齐：code 可能是数字也可能是字符串（如 "200"）
function unpack(text, expectData = true) {
  const json = parseJson(text);
  if (!json) return { ok: false, data: null, msg: '响应解析失败' };
  const rawCode = json.Code !== undefined ? json.Code : json.code;
  const code = (rawCode === null || rawCode === undefined || rawCode === '') ? NaN : Number(rawCode);
  const ok = json.Success === true || code === 200 || code === 0;
  return { ok, data: json.Data || json.data || null, msg: json.Msg || json.msg || json.Message || json.message || '', raw: json };
}

// 大小写不敏感取值（对齐桌面版 JsonOptions.PropertyNameCaseInsensitive）：
// 服务端登录/刷新响应的键是小写的 access_token / refresh_token（桌面版日志实测），
// 但个别版本/网关可能返回 access_Token / accessToken 等写法，这里统一兼容。
function ciPick(obj, ...names) {
  if (!obj || typeof obj !== 'object') return undefined;
  const lower = {};
  Object.keys(obj).forEach(k => { lower[k.toLowerCase()] = obj[k]; });
  for (const n of names) {
    const v = lower[String(n).toLowerCase()];
    if (v !== undefined && v !== null) return v;
  }
  return undefined;
}

// 带 token 过期自动刷新的调用
let refreshInFlight = null;
async function refreshTokenOnce() {
  const cfg = getTokenCfg();
  if (!cfg || !cfg.refreshToken) { const e = new Error('未找到刷新凭证，请重新登录'); e.noRefresh = true; throw e; }
  if (!refreshInFlight) {
    refreshInFlight = (async () => {
      try {
        const res = await request({ url: C.refreshUrl(), data: { refreshToken: cfg.refreshToken } });
        const u = unpack(res.text);
        if (!u.ok || !u.data) { throw new Error(`Token 刷新失败: ${u.msg || '未知错误'}`); }
        const d = u.data;
        const newAccess = ciPick(d, 'access_token', 'accessToken', 'access_Token');
        if (!newAccess) { throw new Error('Token 刷新失败：响应中未找到 access_token'); }
        saveTokenCfg({
          accessToken: newAccess,
          refreshToken: ciPick(d, 'refresh_token', 'refreshToken') || cfg.refreshToken,
          mobile: cfg.mobile,
          updateTime: new Date().toString()
        });
      } finally { refreshInFlight = null; }
    })();
  }
  return refreshInFlight;
}

async function withRefresh(fn) {
  try {
    return await fn();
  } catch (err) {
    if (!err || !err.expired) throw err;
    await refreshTokenOnce();
    return fn();
  }
}

// 通用 JSON POST（不带重试）
function post(url, { data, token } = {}) {
  return request({ url, method: 'POST', data, token });
}

// ---------- 认证接口（模仿官方 App 的签名） ----------
function signF(uuid, tt) {
  return md5(`WDNH${md5(C.VERSION)}SEOB${md5('1')}WEBV${md5('1.0')}ZXOYX${md5(uuid)}OHJHQ${md5(tt)}BGJM`);
}
function deviceId() {
  return `9999999723755${30 + Math.floor(Math.random() * 7)}`;
}
function buildParams(phone, extra) {
  const uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
  const tt = String(Date.now());
  return Object.assign({
    picKey: 'null', code: 'null', a: '1.0', b: '1', c: C.VERSION,
    d: tt, e: uuid, f: signF(uuid, tt), id: deviceId(),
    smsCode: 'null', pageSize: 'null', type: '1', pageNum: 'null',
    picCode: 'null', labelList: 'null', biz: '0', password: 'null',
    csrfToken: 'null', registrationId: C.REGISTRATION_ID, tel: 'null',
    modulus: 'null', username: phone
  }, extra);
}

// 发送短信验证码：返回 { ok, noRecord, msg }
// 注意：picKey 必须填手机号（不是 'null'）！服务端用 picKey 找到该手机号对应的图形验证码并校验，
// 填 'null' 会导致校验失败、返回 code=500（桌面版 SmsSendAsync 就是这么传的）。
// 安全重试：仅当服务端明确返回「无验证码记录」（短信绝未下发）时客户端再试一次；
// 验证码错误 / 其它失败绝不自动重试，避免重复下发短信。
async function smsSend(phone, picCode) {
  const params = buildParams(phone, { smsCode: 'null', picCode, code: picCode, biz: 'null', tel: phone, picKey: phone });
  const sendOnce = () => post(C.smsSendUrl(), { data: params, forceDirect: C.LOGIN_VIA_DIRECT });
  let res = await sendOnce();
  if (isNoRecordResp(res.text)) {
    await sleep(600);
    res = await sendOnce();
  }
  const u = unpack(res.text, false);
  if (u.ok) return { ok: true, noRecord: false, msg: '短信发送成功' };
  const raw = (res.text || '').slice(0, 160);
  // 判别失败类型，给出可操作提示：
  //  - {"msg":null,"code":500}：无记录（已在上方安全重试过；仍无记录则交给页面自动换图）
  //  - {"code":500}（无 msg）：服务端有记录但图形验证码不匹配/已失效
  // 注意：码不匹配绝不计入 noRecord，不会触发重试（避免重复发短信）。
  const noRecord = isNoRecordResp(res.text);
  const isCodeMismatch = !noRecord && /"code"\s*:\s*500/.test(res.text || '');
  let msg;
  if (isCodeMismatch) {
    msg = '图形验证码不正确或已失效：请点击验证码图片刷新后，立即重新输入发送（不要隔太久）';
  } else if (u.msg) {
    msg = u.msg;
  } else {
    msg = '发送失败';
  }
  return { ok: false, noRecord, msg: `${msg}（服务端响应: ${raw}）` };
}

// 图形验证码：返回 dataURL（可 <image> 直接展示）。GET 请求，网络抖动时自动重试一次。
// 注意：服务端返回的 Content-Type 是 application/octet-stream（实际是 JPEG），
// 若直接用该 MIME 拼 dataURL，微信 <image> 组件无法识别，表现为“验证码空白”。
// 因此按图片文件头嗅探真实类型（base64 前缀）。
async function getPicCode(phone) {
  const res = await requestWithRetry({ url: C.getPicCodeUrl(phone), method: 'GET', responseType: 'arraybuffer', forceDirect: C.LOGIN_VIA_DIRECT }, 1);
  const b64 = typeof res.body === 'string' ? res.body : bytesToBase64(res.body);
  return `data:${sniffImageMime(b64)};base64,${b64}`;
}

// 根据 base64 文件头判断真实图片格式（服务端 Content-Type 不可信）
function sniffImageMime(b64) {
  const head = (b64 || '').slice(0, 32);
  if (head.startsWith('/9j/')) return 'image/jpeg';        // JPEG
  if (head.startsWith('iVBORw0KGgo')) return 'image/png';  // PNG
  if (head.startsWith('R0lGOD')) return 'image/gif';       // GIF
  if (head.startsWith('UklGR')) return 'image/webp';       // WebP
  return 'image/jpeg';
}

// 登录：成功返回 accessToken
async function login(phone, smsCode, picCode) {
  const params = buildParams(phone, { smsCode, picCode, picKey: 'null', code: 'null' });
  const res = await post(C.loginUrl(), { data: params, forceDirect: C.LOGIN_VIA_DIRECT });
  const u = unpack(res.text);
  if (!u.ok || !u.data) { throw new Error(`登录失败：${u.msg || '接口返回无效Token'}`); }
  const d = u.data;
  // 服务端键是小写 access_token（桌面版日志实测）；部分版本可能是 access_Token/accessToken，统一兼容
  const token = ciPick(d, 'access_token', 'accessToken', 'access_Token');
  if (!token) { throw new Error('登录失败：接口返回无效Token'); }
  saveTokenCfg({
    accessToken: token,
    refreshToken: ciPick(d, 'refresh_token', 'refreshToken') || '',
    mobile: phone,
    updateTime: new Date().toString()
  });
  return token;
}

// ---------- 数据接口 ----------
async function getCars() {
  return withRefresh(async () => {
    const res = await post(C.getCarsUrl(), { token: currentToken() });
    const u = unpack(res.text);
    if (!u.ok) { throw new Error(u.msg || '获取车辆列表失败'); }
    return u.data || [];
  });
}

async function getUser() {
  return withRefresh(async () => {
    const res = await post(C.getUserUrl(), { token: currentToken() });
    const u = unpack(res.text);
    if (!u.ok) { throw new Error(u.msg || '获取用户信息失败'); }
    return u.data;
  });
}

async function getCarCheck(carId) {
  return withRefresh(async () => {
    const res = await post(C.getCarCheckUrl(carId), { token: currentToken() });
    const u = unpack(res.text);
    return u.ok ? u.data : null;
  });
}
async function getCarPm25(carId) {
  return withRefresh(async () => {
    const res = await post(C.getCarPm25Url(carId), { token: currentToken() });
    const u = unpack(res.text);
    return u.ok ? u.data : null;
  });
}
async function getCharge(carId) {
  return withRefresh(async () => {
    const res = await post(C.getChargeUrl(carId), { token: currentToken() });
    const u = unpack(res.text);
    return u.ok ? u.data : null;
  });
}
async function getControl(carId) {
  return withRefresh(async () => {
    const res = await post(C.getControlUrl(carId), { token: currentToken() });
    const u = unpack(res.text);
    return u.ok ? u.data : null;
  });
}
async function getControlInfo(carId, taskId) {
  return withRefresh(async () => {
    const res = await post(C.getControlInfoUrl(carId, taskId), { token: currentToken() });
    const u = unpack(res.text);
    return { ok: u.ok, data: u.data, msg: u.msg };
  });
}
async function getLocation(carId) {
  return withRefresh(async () => {
    const res = await post(C.getLocationUrl(carId), { token: currentToken() });
    const u = unpack(res.text);
    return u.ok ? u.data : null;
  });
}
async function getMessages() {
  return withRefresh(async () => {
    const res = await post(C.getMessagesUrl(), { token: currentToken() });
    const json = parseJson(res.text);
    if (!json) return [];
    const content = json.Data && json.Data.Content ? json.Data.Content : (json.data && json.data.content ? json.data.content : []);
    const list = Array.isArray(content) ? content : [];
    // 真实报文里 realReceiverId 是该消息关联的车辆/用户 ID（实测为 carId 而非车牌号）。
    // 若命中当前账号已加载的车辆，则替换为车牌号，展示更有意义；未命中保持原文。
    try {
      const app = getApp();
      const cars = (app && app.globalData && app.globalData.cars) || [];
      const plateOf = {};
      cars.forEach(c => {
        const id = c && (c.carId || c.CarId);
        const plate = c && (c.plateNumber || c.PlateNumber);
        if (id && plate) plateOf[id] = plate;
      });
      if (Object.keys(plateOf).length) {
        return list.map(m => {
          const id = m && (m.realReceiverId || m.RealReceiverId);
          const p = plateOf[id];
          if (p) return Object.assign({}, m, { realReceiverId: p, RealReceiverId: p });
          return m;
        });
      }
    } catch (e) { /* 映射失败保持原文 */ }
    return list;
  });
}

// 高频核心数据：首页 30s 自动刷新只用这些（不拉消息/健康报告，省流量限频）
async function fetchCore(carId) {
  const results = await Promise.all([
    getCharge(carId).catch(() => null),
    getCarPm25(carId).catch(() => null),
    getLocation(carId).catch(() => null),
    getControl(carId).catch(() => null)
  ]);
  return { charge: results[0], pm25: results[1], location: results[2], control: results[3] };
}

// 并发拉取车辆全部数据（对应桌面版 RefreshCarDataCoreAsync）
async function fetchVehicleData(carId) {
  const results = await Promise.all([
    getCharge(carId).catch(() => null),
    getCarPm25(carId).catch(() => null),
    getLocation(carId).catch(() => null),
    getControl(carId).catch(() => null),
    getMessages().catch(() => []),
    getCarCheck(carId).catch(() => null)
  ]);
  return {
    charge: results[0],
    pm25: results[1],
    location: results[2],
    control: results[3],
    messages: results[4],
    check: results[5]
  };
}

// 下发车控指令（对应 ExecuteCarControlAsync）
async function sendControlCommand(cmd, carId, pin, temperature = 17) {
  return withRefresh(async () => {
    const res = await post(C.getControlCmdUrl(cmd, carId, pin, temperature), { token: currentToken() });
    const u = unpack(res.text);
    if (!u.ok) { throw new Error(u.msg || '执行失败'); }
    return u.data;
  });
}

function currentToken() {
  const cfg = getTokenCfg();
  return cfg ? cfg.accessToken : '';
}

// ArrayBuffer -> base64
function bytesToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  const CHUNK = 0x8000;
  const b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  for (let i = 0; i < bytes.length; i += CHUNK) {
    const end = Math.min(i + CHUNK, bytes.length);
    const chunk = bytes.subarray(i, end);
    for (let j = 0; j < chunk.length; j += 3) {
      const b1 = chunk[j];
      const b2 = j + 1 < chunk.length ? chunk[j + 1] : NaN;
      const b3 = j + 2 < chunk.length ? chunk[j + 2] : NaN;
      result += b64chars[b1 >> 2];
      result += b64chars[((b1 & 3) << 4) | (isNaN(b2) ? 0 : b2 >> 4)];
      result += isNaN(b2) ? '=' : b64chars[((b2 & 15) << 2) | (isNaN(b3) ? 0 : b3 >> 6)];
      result += isNaN(b3) ? '=' : b64chars[b3 & 63];
    }
  }
  return result;
}

module.exports = {
  smsSend, getPicCode, login, getCars, getUser,
  getCarCheck, getCarPm25, getCharge, getControl, getControlInfo,
  getLocation, getMessages, fetchVehicleData,  sendControlCommand, fetchCore,
  refreshTokenOnce, getTokenCfg, saveTokenCfg, currentToken,
  getFnVersion, getRawLogs, clearRawLogs
};
