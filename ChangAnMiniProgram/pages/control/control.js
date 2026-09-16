// control.js —— 车控 v3：锁车/解锁 + 极简指令列表 + 安静执行反馈
const svc = require('../../utils/service');
const VM = require('../../utils/vm');
const { ic } = require('../../utils/icons');
const app = getApp();

const { ci, s } = require('../../utils/fmt');

const HERO = [
  { key: 'LockDoor', name: '锁车', cls: 'solid' },
  { key: 'UnLockDoor', name: '解锁', cls: 'ghost' }
];
const LIST = [
  { key: 'OpenAir', name: '开启空调', note: '需设置温度' },
  { key: 'CloseAir', name: '关闭空调' },
  { key: 'FlashLight', name: '闪灯' },
  { key: 'Whistle', name: '鸣笛' },
  { key: 'RemoteSearchCar', name: '远程寻车' }
];
const ICON = { LockDoor: 'lock', UnLockDoor: 'unlock', OpenAir: 'snow', CloseAir: 'snowOff', FlashLight: 'bulb', Whistle: 'horn', RemoteSearchCar: 'find' };
const NAME_OF = {};
[HERO, LIST].forEach(arr => arr.forEach(x => { NAME_OF[x.key] = x.name; }));

Page({
  data: {
    enter: false,
    carOptions: [],
    carIndex: 0,
    carName: '',
    hero: [],
    list: [],
    busy: false,
    running: null,
    latest: null,
    history: [],
    statusText: '',
    statusCls: '',
    showPin: false,
    showTemp: false,
    body: { has: false, summary: { text: '--', cls: 'na' }, doorRows: [], extraRows: [], windowRows: [], lampRows: [], lit: [] },
    icons: {
      chevD: ic('chevD', '#8E8E93', 1.8),
      trash: ic('trash', '#9BA3B2', 1.6)
    }
  },

  onLoad() {
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    this.pollTimer = null;
    this.pollIndex = 0;
    this.pollCanceled = false;
    this.seq = 0;
    this.pendingCmd = null;
    this.pendingTemp = 25;
    this.busy = false;
    this.visible = false;
    const hero = HERO.map(x => ({ ...x, img: ic(ICON[x.key], x.cls === 'solid' ? '#000000' : '#FFFFFF', 1.7) }));
    const list = LIST.map(x => ({ ...x, img: ic(ICON[x.key], '#C7C7CC', 1.6) }));
    this.setData({ hero, list });
  },

  onShow() {
    // tab 切换入场：每次 onShow 重放淡入上浮
    this.setData({ enter: false });
    wx.nextTick(() => this.setData({ enter: true }));
    if (this.getTabBar && this.getTabBar()) this.getTabBar().setData({ selected: 1 });
    // 若上次停留在弹层上被切走，回来时确保导航坞状态正确
    if (!this.data.showPin && !this.data.showTemp) this.showBar();
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    this.visible = true;
    if (!app.globalData.cars || !app.globalData.cars.length) {
      this.ensureCars();
    } else {
      this.syncCarSel();
    }
    // 车身状态矩阵（与首页/详情同源建模：门/舱盖/窗/灯）
    this.renderBody();
    // 首页快控圆钮带来的意图：空调→温度弹层，锁/解锁→控车码弹层
    const qk = app.globalData.pendingQuickCtrl;
    if (qk && !this.data.busy && !this.running && app.globalData.carId) {
      app.globalData.pendingQuickCtrl = null;
      if (qk === 'air') this.openTemp();
      else if (qk === 'lock' || qk === 'unlock') {
        this.pendingCmd = qk === 'lock' ? 'LockDoor' : 'UnLockDoor';
        this.openPin();
      }
    }
    if (this.running && this.running.taskId && this.visible) this.resumePoll();
  },
  onHide() { this.visible = false; this.cancelPoll(); this.showBar(); },
  onUnload() { this.visible = false; this.cancelPoll(); this.showBar(); },

  async ensureCars() {
    try {
      const cars = await svc.getCars();
      app.globalData.cars = cars || [];
      if (cars && cars.length > 0 && !app.globalData.car) {
        app.globalData.car = cars[0];
        app.globalData.carId = cars[0].CarId || cars[0].carId || '';
      }
      this.syncCarSel();
    } catch (err) {
      this.showStatus(err.message, 'err');
    }
  },

  syncCarSel() {
    const sel = VM.carSel(app.globalData.cars, app.globalData.carId);
    const cv = sel.car ? ci(sel.car) : null;
    this.setData({
      carOptions: sel.options,
      carIndex: sel.index,
      carName: cv ? `${cv.CarName || ''} ${s(cv.PlateNumber)}`.trim() : '未选择车辆'
    });
  },

  onCarChange(e) {
    const idx = Number(e.detail.value);
    const car = app.globalData.cars[idx];
    if (!car) return;
    app.globalData.car = car;
    app.globalData.carId = car.CarId || car.carId || '';
    this.syncCarSel();
  },

  showStatus(msg, cls) { this.setData({ statusText: msg || '', statusCls: cls || '' }); },

  renderBody() {
    const cache = app.globalData.caches || {};
    const bd = VM.bodyDetailModel(cache);
    this.setData({ body: bd });
  },

  // ---------- 指令入口 ----------
  onCmd(e) {
    if (this.data.busy || this.data.running) return;
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    if (!app.globalData.carId) { wx.showToast({ title: '请先选择车辆', icon: 'none' }); return; }
    const cmd = e.currentTarget.dataset.cmd;
    this.pendingCmd = cmd;
    if (cmd === 'OpenAir') this.openTemp();
    else this.openPin();
  },

  // 弹层打开时隐藏底部导航坞（自定义 tab bar 在原生层，page 的 z-index 压不住它），
  // 所有弹层统一走 open/close，保证每次打开都 hide、每次关闭都 show。
  // 注意：custom:true 下绝不能调 wx.showTabBar/wx.hideTabBar —— showTabBar 会把
  // 原生 tabBar 复显出来，与自定义玻璃坞叠成两组导航（点一次车控就复现）。
  hideBar() {
    try { if (this.getTabBar && this.getTabBar()) this.getTabBar().setData({ hidden: true }); } catch (e) {}
  },
  showBar() {
    try { if (this.getTabBar && this.getTabBar()) this.getTabBar().setData({ hidden: false }); } catch (e) {}
  },
  openPin() {
    this.hideBar();
    this.setData({ showPin: true });
  },
  openTemp() {
    this.hideBar();
    this.setData({ showTemp: true });
  },
  onTempCancel() {
    this.pendingCmd = null;
    this.setData({ showTemp: false });
    this.showBar();
  },
  onTempConfirm(e) {
    this.pendingTemp = e.detail.temperature;
    this.setData({ showTemp: false });
    this.openPin();
  },
  onPinCancel() {
    this.pendingCmd = null;
    this.setData({ showPin: false });
    this.showBar();
  },
  async onPinConfirm(e) {
    const pin = e.detail.pin;
    const cmd = this.pendingCmd;
    this.pendingCmd = null;
    this.setData({ showPin: false });
    this.showBar();
    if (!cmd) return;
    await this.execute(cmd, pin, cmd === 'OpenAir' ? this.pendingTemp : 17);
  },

  async execute(cmd, pin, temperature) {
    if (this.busy) return;
    this.busy = true;
    const startedAt = VM.nowText();
    const run = { cmd, name: NAME_OF[cmd] || cmd, startedAt, taskId: '', status: 'run' };
    this.setData({ busy: true, running: run, statusText: '', statusCls: '' });
    try {
      const data = await svc.sendControlCommand(cmd, app.globalData.carId, pin, temperature);
      const taskId = (data && (data.TaskId || data.taskId)) || '';
      if (taskId) {
        run.taskId = taskId;
        this.setData({ running: run, statusText: `已下发 · 等待车辆执行`, statusCls: '' });
        this.pollIndex = 0;
        this.pollCanceled = false;
        this.resumePoll();
      } else {
        this.finishRun(run, { status: 'ok', statusText: '执行成功', desc: '服务端已受理' });
      }
    } catch (err) {
      this.finishRun(run, { status: 'bad', statusText: '执行失败', desc: err.message });
    } finally {
      this.busy = false;
    }
  },

  resumePoll() {
    this.cancelPoll();
    this.pollCanceled = false;
    const run = this.running;
    if (!run) return;
    const tick = async () => {
      if (this.pollCanceled || !this.visible || !this.running) return;
      this.pollIndex++;
      const i = this.pollIndex;
      try {
        const r = await svc.getControlInfo(app.globalData.carId, run.taskId);
        if (r.ok && r.data) {
          const d = ci(r.data);
          const status = s(d.HandleStatus);
          if (['Success', 'Completed', 'RunFailure', 'Failed', 'Timeout'].indexOf(status) >= 0) {
            const okEnd = status === 'Success' || status === 'Completed';
            this.finishRun(run, {
              status: okEnd ? 'ok' : 'bad',
              statusText: okEnd ? '执行成功' : '执行失败',
              desc: d.HandleStatusDesc || r.msg || status,
              handleCode: s(d.HandleCode),
              finish: s(d.CmdFinishTime),
              taskId: s(d.TaskId) || run.taskId
            });
            return;
          }
          this.setData({
            'running.progress': `第 ${i} 次查询`,
            statusText: `执行中 · ${run.name}`,
            statusCls: ''
          });
        } else {
          this.setData({ statusText: `查询异常，重试中…`, statusCls: 'err' });
        }
      } catch (err) {
        this.setData({ statusText: '网络异常，重试中…', statusCls: 'err' });
      }
      if (i >= 12) {
        this.finishRun(run, { status: 'warn', statusText: '结果待确认', desc: '60 秒内未收到车辆终态，请稍后查看车辆状态', taskId: run.taskId });
        return;
      }
      this.pollTimer = setTimeout(tick, 5000);
    };
    tick();
  },

  finishRun(run, outcome) {
    this.cancelPoll();
    const finish = outcome.finish || VM.nowText();
    const item = {
      id: String(++this.seq),
      time: finish,
      timeShort: finish.length > 10 ? finish.slice(5, 16) : finish,
      name: run.name,
      cls: outcome.status,
      statusText: outcome.statusText,
      desc: outcome.desc || '',
      handleCode: outcome.handleCode || '',
      taskId: outcome.taskId || ''
    };
    const history = [item].concat(this.data.history.filter(h => h.id !== item.id)).slice(0, 6);
    this.setData({
      running: null,
      latest: item,
      history,
      busy: false,
      statusText: '',
      statusCls: ''
    });
    wx.showToast({
      title: item.statusText,
      icon: item.cls === 'ok' ? 'success' : 'none',
      duration: 2000
    });
    // 指令完成后静默回刷车辆状态
    if (app.globalData.carId) {
      svc.getControl(app.globalData.carId).then(ctrl => {
        if (ctrl) app.saveCache({ control: ctrl });
        this.renderBody();
      }).catch(() => {});
    }
  },

  cancelPoll() {
    this.pollCanceled = true;
    if (this.pollTimer) { clearTimeout(this.pollTimer); this.pollTimer = null; }
  },

  clearHistory() { this.setData({ history: [], latest: null }); },

  onLogTap(e) {
    const item = this.data.history[Number(e.currentTarget.dataset.idx)];
    if (!item) return;
    const lines = [];
    if (item.desc) lines.push(item.desc);
    lines.push(`状态：${item.statusText}`);
    lines.push(`时间：${item.time}`);
    if (item.taskId) lines.push(`任务ID：${item.taskId}`);
    if (item.handleCode) lines.push(`错误码：${item.handleCode}`);
    wx.showModal({
      title: item.name,
      content: lines.join('\n'),
      showCancel: false,
      confirmText: '关闭'
    });
  }
});
