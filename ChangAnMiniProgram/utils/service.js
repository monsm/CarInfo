const md5 = require('./md5');
const C = require('./config');

const TOKEN_KEY = 'car_token_config';

const RAW_LOG_KEY = 'changan_raw_log';
const RAW_LOG_MAX = 60;
const RAW_LOG_CHARS = 3000;

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
  try { console.log('[changan] ' + entry); } catch (e) {  }
  try {
    let list = wx.getStorageSync(RAW_LOG_KEY);
    if (!Array.isArray(list)) list = [];
    list.unshift(entry);
    if (list.length > RAW_LOG_MAX) list.length = RAW_LOG_MAX;
    wx.setStorageSync(RAW_LOG_KEY, list);
  } catch (e) {  }
}
function getRawLogs() {
  try { const l = wx.getStorageSync(RAW_LOG_KEY); return Array.isArray(l) ? l : []; } catch (e) { return []; }
}
function clearRawLogs() {
  try { wx.removeStorageSync(RAW_LOG_KEY); } catch (e) {  }
}

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

function request(opts) {
  const { url, method = 'POST', data, raw, token } = opts;
  const payload = raw !== undefined ? raw : data;
  const maskedHdr = { 'content-type': 'application/json' };
  if (token) maskedHdr['Authorization'] = 'Bearer ' + token.slice(0, 10) + '…(已打码)';
  _rawLogPush('REQ', method, url, `headers=${_clipText(maskedHdr, 400)}\nbody=${_clipText(payload, RAW_LOG_CHARS)}`);
  return requestCore(opts).then(
    res => {
      let bodyInfo;
      if (res && res.body instanceof ArrayBuffer) bodyInfo = `[二进制 ${res.body.byteLength} 字节]`;
      else if (res && typeof res.text === 'string') bodyInfo = res.text;
      else bodyInfo = res ? _clipText(res.body, RAW_LOG_CHARS) : '';
      const hdr = (res && res.header) ? _clipText(res.header, 800) : '';
      _rawLogPush('RES', method, url, `HTTP ${res && res.statusCode} headers=${hdr}\nbody=${bodyInfo}`);
      return res;
    },
    err => {
      _rawLogPush('ERR', method, url, (err && (err.message || String(err))) || '未知错误');
      throw err;
    }
  );
}

function requestCore(opts) {
  const { url, method = 'POST', data, raw, token, responseType, forceDirect } = opts;
  const header = {};
  header['content-type'] = 'application/json';
  if (token) header['Authorization'] = 'Bearer ' + token;
  const payload = raw !== undefined ? raw : data;

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
          const hdrs = r.headers || {};
          const ver = hdrs['x-fn-version'] || hdrs['X-Fn-Version'];
          if (ver) fnVersion = ver;
          if (!r.ok) {
            reject(new Error(`云函数转发失败：${r.error || '未知错误'}`));
            return;
          }
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

function isNoRecordResp(text) {
  const t = text || '';
  return t.indexOf('"msg":null') >= 0 && /"code"\s*:\s*500/.test(t);
}

async function requestWithRetry(opts, retries = 1) {
  let lastErr;
  for (let i = 0; i <= retries; i++) {
    try {
      return await request(opts);
    } catch (err) {
      lastErr = err;
      if (err.expired || err.statusCode) throw err;
      if (i < retries) await new Promise(r => setTimeout(r, 600 * (i + 1)));
    }
  }
  throw lastErr;
}

function parseJson(text) {
  try { return text ? JSON.parse(text) : null; } catch (e) { return null; }
}

function unpack(text, expectData = true) {
  const json = parseJson(text);
  if (!json) return { ok: false, data: null, msg: '响应解析失败' };
  const rawCode = json.Code !== undefined ? json.Code : json.code;
  const code = (rawCode === null || rawCode === undefined || rawCode === '') ? NaN : Number(rawCode);
  const ok = json.Success === true || code === 200 || code === 0;
  return { ok, data: json.Data || json.data || null, msg: json.Msg || json.msg || json.Message || json.message || '', raw: json };
}

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

function post(url, { data, token } = {}) {
  return request({ url, method: 'POST', data, token });
}

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

async function getPicCode(phone) {
  const res = await requestWithRetry({ url: C.getPicCodeUrl(phone), method: 'GET', responseType: 'arraybuffer', forceDirect: C.LOGIN_VIA_DIRECT }, 1);
  const b64 = typeof res.body === 'string' ? res.body : bytesToBase64(res.body);
  return `data:${sniffImageMime(b64)};base64,${b64}`;
}

function sniffImageMime(b64) {
  const head = (b64 || '').slice(0, 32);
  if (head.startsWith('/9j/')) return 'image/jpeg';
  if (head.startsWith('iVBORw0KGgo')) return 'image/png';
  if (head.startsWith('R0lGOD')) return 'image/gif';
  if (head.startsWith('UklGR')) return 'image/webp';
  return 'image/jpeg';
}

async function login(phone, smsCode, picCode) {
  const params = buildParams(phone, { smsCode, picCode, picKey: 'null', code: 'null' });
  const res = await post(C.loginUrl(), { data: params, forceDirect: C.LOGIN_VIA_DIRECT });
  const u = unpack(res.text);
  if (!u.ok || !u.data) { throw new Error(`登录失败：${u.msg || '接口返回无效Token'}`); }
  const d = u.data;
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
    } catch (e) {  }
    return list;
  });
}

async function fetchCore(carId) {
  const results = await Promise.all([
    getCharge(carId).catch(() => null),
    getCarPm25(carId).catch(() => null),
    getLocation(carId).catch(() => null),
    getControl(carId).catch(() => null)
  ]);
  return { charge: results[0], pm25: results[1], location: results[2], control: results[3] };
}

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
