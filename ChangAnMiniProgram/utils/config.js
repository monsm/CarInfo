// config.js —— 与桌面版 ChangAnCarInfo 一致的常量与接口地址
//
// ⚠️ 重要说明（网络模式）：
// 微信小程序只能请求“已在小程序后台配置的 request 合法域名”，且必须是备案过的 HTTPS 域名，
// 而长安官方接口域名无法加入你的白名单。本项目提供两种网络模式：
//
// 1) 云函数模式（推荐，USE_CLOUD = true）：
//    请求经云函数 changanProxy 转发，云函数出网不受域名白名单限制，
//    真机、体验版、正式版都能用，无需勾选“不校验合法域名”。
//    首次使用需：开发者工具点击「云开发」开通 → 右键 cloudfunctions/changanProxy
//    → 「上传并部署：云端安装依赖」→ 把 CLOUD_ENV 填成你的环境 ID（留空用默认环境）。
//
// 2) 直连模式（USE_CLOUD = false）：
//    调试时在 详情 -> 本地设置 勾选“不校验合法域名…”，真机预览需打开“调试模式”；
//    正式发布必须自建反向代理并把代理域名加入 request 合法域名。
const USE_CLOUD = true;
const CLOUD_ENV = 'cloud1-d0gtnna7nb3b1f52f'; // 云开发环境 ID（控制台->云开发->设置 里查看），留空则使用默认环境
const CLOUD_FUNC = 'changanProxy'; // 云函数名

// ⚠️ 登录相关请求（图形验证码/短信/登录）是否绕过云函数、直接用 wx.request 直连。
// 背景：长安服务端把图形验证码记录存在 CDN 边缘节点内存中，picSend 和 smsSend 必须命中
// 同一节点才能找到记录；云函数出口 IP 来自腾讯机房，被 CDN 轮询调度到不同节点，导致
// 短信发送返回 {"msg":null,"code":500}（已通过 via 响应头实测证实）。
// 家里的宽带 IP（桌面版能正常用）会被 CDN 固定到同一节点，所以：
//   - 开发者工具调试：勾选「不校验合法域名…」后，把本开关改为 true，登录即可正常；
//   - 真机预览：把本开关改为 true，并在预览二维码窗口勾选「开启调试」，
//     手机走家里 WiFi 时和桌面版同 IP，验证码记录能找到；
//   - 正式发布（无调试模式）：保持 false，走云函数（依赖云函数连接池复用，成功率较高）。
// 其余数据接口（车辆状态等）不受此问题影响，始终走云函数。
const LOGIN_VIA_DIRECT = false;

// ⚠️ 必须以 /cac 结尾（与桌面版 AuthUrl 完全一致）！
// 桌面版请求的是 /app-m/prod-api/auth/cac/{picSend,smsSend,appLogin}；
// 不带 /cac 的是另一套网关，验证码记录互不互通——小程序此前“短信始终失败”的根源就在这里。
const AUTH_URL = 'https://scrm.changan.com.cn/app-m/prod-api/auth/cac';
const BASE_URL = 'https://m.iov.changan.com.cn';

// 模仿官方 App changAnFan/4.6.3 的请求特征（wx.request 无法自定义 User-Agent，仅供参考）
const USER_AGENT = 'changAnFan/4.6.3 (iPhone; iOS 26.5; Scale/3.00)';

const REGISTRATION_ID = '2c8735c5a6f753229aec45789dcd3a1f4';
const VERSION = '4.6.3';

const getPicCodeUrl = phone => `${AUTH_URL}/picSend?picKey=${encodeURIComponent(phone)}`;
const loginUrl = () => `${AUTH_URL}/appLogin`;
const smsSendUrl = () => `${AUTH_URL}/smsSend`;
const refreshUrl = () => `${AUTH_URL}/refresh`;

const getCarCheckUrl = carId => `${BASE_URL}/appserver/api/carcheck/getCheckResult?carId=${carId}&isNev=1&token=${TOKEN()}`;
const getCarPm25Url = carId => `${BASE_URL}/appserver/api/car/pm/getCarPm25ByCarId?carId=${carId}&token=${TOKEN()}`;
const getCarsUrl = () => `${BASE_URL}/appserver/api/car/getMyCars?isNev=1&token=${TOKEN()}`;
const getChargeUrl = carId => `${BASE_URL}/appserver/api/charge/info?carId=${carId}&token=${TOKEN()}`;
const getControlUrl = carId => `${BASE_URL}/api/car/getControlStatus?carId=${carId}&token=${TOKEN()}`;
const getControlInfoUrl = (carId, taskId) => `${BASE_URL}/api/car/getControlInfo?carId=${carId}&id=${taskId}&token=${TOKEN()}`;
const getLocationUrl = carId => `${BASE_URL}/appserver/api/cardata/getCarLocation?carId=${carId}&mapType=GCJ02&token=${TOKEN()}`;
const getMessagesUrl = () => {
  const fmt = d => {
    const p = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  };
  const now = new Date();
  const past = new Date(now.getTime() - 7 * 24 * 3600 * 1000);
  return `${BASE_URL}/appserver/api/information/pageReceiverInfoByTime?actionType=2&page=&limit=2000&startTime=${encodeURIComponent(fmt(past))}&endTime=${encodeURIComponent(fmt(now))}&token=${TOKEN()}`;
};
const getUserUrl = () => `${BASE_URL}/appserver/api/user/getUserInfoByToken?token=${TOKEN()}`;
const getControlCmdUrl = (cmd, carId, pin, temperature) => {
  let url = `${BASE_URL}/api/car/control?pin=${pin}&cmd=${cmd}&carId=${carId}&phoneType=&phoneId=&token=${TOKEN()}`;
  if (cmd === 'OpenAir') url += `&temperature=${temperature}`;
  return url;
};

// 与桌面版一致：URL 中拼 token 时从本地读取
function TOKEN() {
  try {
    const cfg = wx.getStorageSync('car_token_config');
    return cfg && cfg.accessToken ? cfg.accessToken : '';
  } catch (e) { return ''; }
}

module.exports = {
  USE_CLOUD, CLOUD_ENV, CLOUD_FUNC,
  AUTH_URL, BASE_URL, USER_AGENT, REGISTRATION_ID, VERSION,
  getPicCodeUrl, loginUrl, smsSendUrl, refreshUrl,
  getCarCheckUrl, getCarPm25Url, getCarsUrl, getChargeUrl, getControlUrl,
  getControlInfoUrl, getLocationUrl, getMessagesUrl, getUserUrl, getControlCmdUrl,
  TOKEN
};
