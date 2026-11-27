const http = require('http');
const https = require('https');
const zlib = require('zlib');

const USER_AGENT = 'changAnFan/4.6.3 (iPhone; iOS 26.5; Scale/3.00)';
const MAX_REDIRECTS = 5;
const TIMEOUT_MS = 20000;

const FN_VERSION = 'v4-netlog';

const LOG_MAX_CHARS = 4000;
function clipLog(s, n = LOG_MAX_CHARS) {
  if (s === undefined || s === null) return String(s);
  const t = typeof s === 'string' ? s : (() => { try { return JSON.stringify(s); } catch (e) { return String(s); } })();
  return t.length > n ? `${t.slice(0, n)}…(截断,共${t.length}字符)` : t;
}
function logLine(tag, obj) {
  try { console.log(`[changanProxy ${FN_VERSION}] ${new Date().toISOString()} ${tag} ${JSON.stringify(obj)}`); } catch (e) {  }
}

const AGENT = new https.Agent({ keepAlive: true, maxSockets: 1, keepAliveMsecs: 120000 });
AGENT.timeout = TIMEOUT_MS;

const ALLOWED_HOSTS = ['scrm.changan.com.cn', 'm.iov.changan.com.cn'];

function isAllowed(url) {
  try {
    const u = new URL(url);
    return ALLOWED_HOSTS.includes(u.hostname);
  } catch (e) {
    return false;
  }
}

function requestOnce(url, options, redirectsLeft, agent) {
  const conn = agent === undefined ? AGENT : agent;
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

    logLine('REQ', {
      conn: conn === AGENT ? '连接池' : '新连接',
      method,
      url,
      headers,
      body: body ? clipLog(body) : null
    });

    const req = lib.request(u, { method, headers, timeout: TIMEOUT_MS, agent: conn }, res => {
      const status = res.statusCode || 0;
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
        const diag = Object.assign({}, res.headers);
        diag['x-fn-version'] = FN_VERSION;
        try {
          const localAddr = req.socket && req.socket.localAddress;
          if (localAddr) diag['x-egress-ip'] = localAddr;
          const via = String(diag['via'] || '');
          const m = via.match(/ens-cache[\w.-]+/);
          if (m) diag['x-cdn-node'] = m[0];
        } catch (e) {  }
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

function isNoCaptchaRecord(body) {
  const text = body.toString('utf8').slice(0, 200);
  return text.indexOf('"msg":null') >= 0 && /"code"\s*:\s*500/.test(text);
}
function isCode500Only(body) {
  const text = body.toString('utf8').slice(0, 200);
  return !isNoCaptchaRecord(body) && /"code"\s*:\s*500/.test(text);
}

async function smsSendWithRetry(url, options) {
  let res = await requestOnce(url, options, MAX_REDIRECTS, AGENT);
  const MAX_NO_RECORD = 6;
  const MAX_CODE500 = 2;
  let noRecordLeft = MAX_NO_RECORD - 1;
  let code500Left = MAX_CODE500 - 1;
  for (let i = 0; i < MAX_NO_RECORD + MAX_CODE500; i++) {
    const noRecord = isNoCaptchaRecord(res.body);
    const code500 = !noRecord && isCode500Only(res.body);
    if (!noRecord && !code500) return res;
    if (noRecord && noRecordLeft <= 0) return res;
    if (code500 && code500Left <= 0) return res;
    if (noRecord) noRecordLeft--; else code500Left--;
    await new Promise(r => setTimeout(r, 120 + i * 160));
    res = await requestOnce(url, options, MAX_REDIRECTS, false);
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