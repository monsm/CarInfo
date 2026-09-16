// fmt.js —— 字段访问与格式化辅助
// 桌面版用 System.Text.Json(PropertyNameCaseInsensitive) 反序列化，
// 服务端返回键的大小写无法预知，这里提供大小写不敏感的读取。

const viewCache = typeof WeakMap !== 'undefined' ? new WeakMap() : null;

// 返回对象的“大小写不敏感视图”：view(o).CarId 按真实键(忽略大小写)取值
function ci(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  if (viewCache && viewCache.has(obj)) return viewCache.get(obj);
  const lower = {};
  Object.keys(obj).forEach(k => { lower[k.toLowerCase()] = obj[k]; });
  const view = new Proxy(obj, {
    get(target, prop) {
      if (typeof prop !== 'string') return target[prop];
      if (prop in target) return target[prop];
      return lower[prop.toLowerCase()];
    }
  });
  if (viewCache) viewCache.set(obj, view);
  return view;
}

function s(v, dflt = '') { return v === null || v === undefined ? dflt : String(v); }
function num(v) { const n = Number(v); return isNaN(n) ? 0 : n; }
function num1(v) { return num(v).toFixed(1); }
function num2(v) { return num(v).toFixed(2); }
function num3(v) { return num(v).toFixed(3); }
function num0(v) { return String(Math.round(num(v))); }

const SEP = '═══════════════════════════════════════════════';
const SMALL = '───────────────────────────────────────────────';

// 桌面版字段值的常见释义
const CHRG_STATUS = { '1': '充电中', '2': '即将完成', '3': '充电完成' };
const TBOX_CMD = {
  LockDoor: '锁门', UnLockDoor: '解锁', OpenAir: '开启空调', CloseAir: '关闭空调',
  UpCarCondition: '刷新车辆状态', FlashLight: '闪灯', Whistle: '鸣笛', RemoteSearchCar: '远程寻车'
};
const GENDER = { f: '女', m: '男' };
const DIRECTION = ['正北', '东北', '正东', '东南', '正南', '西南', '正西', '西北'];

// 车载 heading 可能是累计角度（真实报文实测出现 460.8°），罗盘/显示前归一化到 [0,360)
function norm360(v) {
  const n = num(v) % 360;
  return n < 0 ? n + 360 : n;
}

function directionText(angle) {
  const idx = Math.round(norm360(angle) / 45) % 8;
  return DIRECTION[(idx + 8) % 8];
}

function cmdText(cmd) { return TBOX_CMD[cmd] || s(cmd); }

module.exports = {
  ci, s, num, num1, num2, num3, num0,
  SEP, SMALL, CHRG_STATUS, GENDER, directionText, cmdText, norm360
};
