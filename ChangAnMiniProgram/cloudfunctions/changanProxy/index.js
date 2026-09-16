// 云函数 changanProxy —— 长安接口反向代理
//
// 作用：微信小程序 wx.request 只能访问“request 合法域名”，而长安接口域名
// (scrm.changan.com.cn / m.iov.changan.com.cn) 无法加入你的白名单。
// 云函数在微信云端运行、出网不受域名白名单限制，因此把请求转发到长安接口即可。
// 同时云函数可以自由设置 User-Agent（小程序端无法自定义），正好补上 changAnFan 特征头。
//
// 客户端调用：wx.cloud.callFunction({ name: 'changanProxy', data: { url, method, data, headers } })
// 返回：
//   文本/JSON: { ok: true, statusCode, headers, text }
//   二进制:    { ok: true, statusCode, headers, base64, contentType }
//   失败:      { ok: false, error }
//
// ⚠️ 连接池（关键）：
// 长安服务端把“图形验证码记录”存在 CDN 边缘节点的内存里（实测 picSend 与 smsSend
// 走不同节点时必然返回 {"msg":null,"code":500}）。桌面版之所以正常，是因为 .NET
// HttpClient 复用同一个 TCP 连接，两次请求固定在同一节点。
// 这里用模块级 keep-alive Agent 模拟同样行为：同一个云函数实例（热实例）处理
// 的连续请求会复用同一条连接，picSend 存的验证码记录才能被随后的 smsSend 找到。
const http = require('http');
const https = require('https');
const zlib = require('zlib');

const USER_AGENT = 'changAnFan/4.6.3 (iPhone; iOS 26.5; Scale/3.00)';
const MAX_REDIRECTS = 5;
const TIMEOUT_MS = 20000;

// 云函数版本号：随响应头 x-fn-version 返回，登录页会显示，
// 用于确认线上部署的确实是带连接池/重试逻辑/原文日志的新版本。
const FN_VERSION = 'v4-netlog';

// ---------- 原文日志 ----------
// 每次转发都会打一条 REQ 和一条 RES（云开发控制台 → 云函数 → changanProxy → 日志 可查）。
// 日志内容 = 客户端发出的原始请求（方法/URL/头/正文）与长安返回的原始响应（状态码/头/正文），
// 正文超长会截断并标注，二进制（图片）只记录大小不 dump 内容。
const LOG_MAX_CHARS = 4000;
function clipLog(s, n = LOG_MAX_CHARS) {
  if (s === undefined || s === null) return String(s);
  const t = typeof s === 'string' ? s : (() => { try { return JSON.stringify(s); } catch (e) { return String(s); } })();
  return t.length > n ? `${t.slice(0, n)}…(截断,共${t.length}字符)` : t;
}
function logLine(tag, obj) {
  try { console.log(`[changanProxy ${FN_VERSION}] ${new Date().toISOString()} ${tag} ${JSON.stringify(obj)}`); } catch (e) { /* 日志失败不影响转发 */ }
}

// 连接池：与桌面版 HttpClient 的连接复用行为对齐。
// maxSockets=1：同一时刻只发一个请求，保证顺序请求尽量复用同一条连接。
const AGENT = new https.Agent({ keepAlive: true, maxSockets: 1, keepAliveMsecs: 120000 });
AGENT.timeout = TIMEOUT_MS;

// 只允许转发到长安官方域名，防止云函数被滥用为任意代理
const ALLOWED_HOSTS = ['scrm.changan.com.cn', 'm.iov.changan.com.cn'];

function isAllowed(url) {
  try {
    const u = new URL(url);
    return ALLOWED_HOSTS.includes(u.hostname);
  } catch (e) {
    return false;
  }
}

// 单次请求（跟随重定向）。
// agent=false 时表示“不要复用连接池、开一条全新连接”（用于 smsSend 换后端重试）。
function requestOnce(url, options, redirectsLeft, agent) {
  const conn = agent === undefined ? AGENT : agent; // undefined→默认池；false→全新连接
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const lib = u.protocol === 'http:' ? http : https;
    const method = (options.method || 'POST').toUpperCase();
    const headers = Object.assign({}, options.headers || {}, {
      'User-Agent': USER_AGENT,
      'Accept': '*/*'
    });
    let body = null;
    if (options.data !== undefined && options.data !== null) {
      body = typeof options.data === 'string' ? options.data : JSON.stringify(options.data);
      headers['Content-Type'] = headers['Content-Type'] || 'application/json';
      headers['Content-Length'] = Buffer.byteLength(body);
    }

    // REQ 日志：记录本次实际发出的原始请求（含头与正文原文）
    logLine('REQ', {
      conn: conn === AGENT ? '连接池' : '新连接',
      method,
      url,
      headers,
      body: body ? clipLog(body) : null
    });

    const req = lib.request(u, { method, headers, timeout: TIMEOUT_MS, agent: conn }, res => {
      const status = res.statusCode || 0;
      // 跟随重定向
      if ([301, 302, 303, 307, 308].includes(status) && res.headers.location) {
        res.resume();
        if (redirectsLeft <= 0) {
          reject(new Error('重定向次数过多'));
          return;
        }
        const next = new URL(res.headers.location, u).toString();
        requestOnce(next, options, redirectsLeft - 1, agent).then(resolve, reject);
        return;
      }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        let buf = Buffer.concat(chunks);
        const enc = (res.headers['content-encoding'] || '').toLowerCase();
        if (enc === 'gzip') {
          buf = zlib.gunzipSync(buf);
        } else if (enc === 'deflate') {
          buf = zlib.inflateSync(buf);
        }
        // 附加诊断头：出口 IP、命中的 CDN 节点、云函数版本（用于排查 picSend/smsSend 是否同节点）
        const diag = Object.assign({}, res.headers);
        diag['x-fn-version'] = FN_VERSION;
        try {
          const localAddr = req.socket && req.socket.localAddress;
          if (localAddr) diag['x-egress-ip'] = localAddr;
          const via = String(diag['via'] || '');
          const m = via.match(/ens-cache[\w.-]+/);
          if (m) diag['x-cdn-node'] = m[0];
        } catch (e) { /* 忽略诊断失败 */ }
        // RES 日志：记录长安返回的原始响应（状态码/头/正文，图片只记大小）
        const ctRaw = (res.headers['content-type'] || '').split(';')[0].toLowerCase();
        const binResp = /^image\//.test(ctRaw) || /^application\/octet-stream/.test(ctRaw);
        logLine('RES', {
          conn: conn === AGENT ? '连接池' : '新连接',
          url,
          status,
          headers: diag,
          body: binResp ? `[二进制 ${buf.length}B, ${ctRaw}]` : clipLog(buf.toString('utf8'))
        });
        resolve({ statusCode: status, headers: diag, body: buf });
      });
      res.on('error', reject);
    });
    req.on('timeout', () => {
      req.destroy(new Error('请求超时'));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

// 判断响应体是否为“找不到该手机号的图形验证码记录”（{"msg":null,"code":500}）。
// 与“验证码输错”（{"code":500}，无 msg）区分——两种都意味着短信绝未下发，重试均安全。
function isNoCaptchaRecord(body) {
  const text = body.toString('utf8').slice(0, 200);
  return text.indexOf('"msg":null') >= 0 && /"code"\s*:\s*500/.test(text);
}
// “有记录但码不匹配”：{"code":500} 且不含 msg:null。
// 实测表明这也可能是 smsSend 换连接后命中了另一节点上的历史旧记录导致，
// 短信同样未下发，允许安全地换节点补试一次。
function isCode500Only(body) {
  const text = body.toString('utf8').slice(0, 200);
  return !isNoCaptchaRecord(body) && /"code"\s*:\s*500/.test(text);
}

// smsSend 专用重试：长安把验证码记录与“命中它的那台后端/CDN 节点”绑定，
// picSend 与 smsSend 必须落到同一后端才能找到记录、且码一致才能通过。
// 第一次用默认连接池（同一实例热连接 = 与 picSend 同后端，最理想）；
// 若仍报“无记录”或“码不匹配”（两者都保证短信未下发），再用全新连接重试，
// 每次换连接都可能被调度到不同后端；直到拿到非 500 的成功/其它响应即停。
// 上限：无记录最多 6 次、码不匹配额外只补 1 次（防止用户真的输错码时无效狂发）。
async function smsSendWithRetry(url, options) {
  let res = await requestOnce(url, options, MAX_REDIRECTS, AGENT); // 第 1 次：连接池
  const MAX_NO_RECORD = 6;
  const MAX_CODE500 = 2;
  let noRecordLeft = MAX_NO_RECORD - 1;
  let code500Left = MAX_CODE500 - 1;
  for (let i = 0; i < MAX_NO_RECORD + MAX_CODE500; i++) {
    const noRecord = isNoCaptchaRecord(res.body);
    const code500 = !noRecord && isCode500Only(res.body);
    if (!noRecord && !code500) return res;      // 成功或其它业务响应 → 立即返回
    if (noRecord && noRecordLeft <= 0) return res;
    if (code500 && code500Left <= 0) return res;
    if (noRecord) noRecordLeft--; else code500Left--;
    await new Promise(r => setTimeout(r, 120 + i * 160));
    res = await requestOnce(url, options, MAX_REDIRECTS, false); // 全新连接换节点
  }
  return res;
}

exports.main = async (event) => {
  const { url, method, data, headers } = event || {};
  if (!url || typeof url !== 'string') {
    return { ok: false, error: '缺少 url 参数' };
  }
  if (!isAllowed(url)) {
    return { ok: false, error: '不允许访问的域名' };
  }
  try {
    const opts = { method, data, headers };
    // 仅对 smsSend 做“换连接重试”；picSend/其它接口原样转发，绝不多重试
    const res = /\/smsSend(\?|$)/.test(url) && (method || 'POST').toUpperCase() === 'POST'
      ? await smsSendWithRetry(url, opts)
      : await requestOnce(url, opts, MAX_REDIRECTS, AGENT);
    const ctype = (res.headers['content-type'] || '').split(';')[0].toLowerCase();
    const isBinary = /^image\//.test(ctype) || /^application\/octet-stream/.test(ctype) || /^audio\//.test(ctype);
    if (isBinary) {
      return {
        ok: true,
        statusCode: res.statusCode,
        headers: res.headers,
        base64: res.body.toString('base64'),
        contentType: ctype
      };
    }
    return {
      ok: true,
      statusCode: res.statusCode,
      headers: res.headers,
      text: res.body.toString('utf8')
    };
  } catch (err) {
    logLine('ERR', { url, method, error: String((err && err.message) || err) });
    return { ok: false, error: String((err && err.message) || err) };
  }
};