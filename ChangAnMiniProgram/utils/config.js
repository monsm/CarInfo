const USE_CLOUD = true;
const CLOUD_ENV = 'cloud1-d0gtnna7nb3b1f52f';
const CLOUD_FUNC = 'changanProxy';

const LOGIN_VIA_DIRECT = false;

const AUTH_URL = 'https://scrm.changan.com.cn/app-m/prod-api/auth/cac';
const BASE_URL = 'https://m.iov.changan.com.cn';

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
