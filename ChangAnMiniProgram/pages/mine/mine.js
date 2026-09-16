// mine.js —— 我的 v3：极简 · 工程入口下沉到页脚
const svc = require('../../utils/service');
const VM = require('../../utils/vm');
const C = require('../../utils/config');
const { ic } = require('../../utils/icons');
const { carSideURI } = require('../../utils/scene');
const app = getApp();

Page({
  data: {
    enter: false,
    user: { avatar: '', name: '', mobile: '', authed: false },
    car: { name: '', plate: '', model: '', color: '' },
    carCount: 0,
    carList: [],
    sceneImg: carSideURI(),
    icons: {
      chevR: ic('chevR', '#8E8E93', 1.8),
      tiles: {
        health: ic('shield', '#8E8E93', 1.7),
        batt: ic('bolt', '#8E8E93', 1.7),
        an: ic('doc', '#8E8E93', 1.7),
        loc: ic('pin', '#8E8E93', 1.7),
        acc: ic('user', '#8E8E93', 1.7)
      },
      dev: ic('gear', '#8E8E93', 1.6),
      data: ic('doc', '#8E8E93', 1.6),
      about: ic('info', '#8E8E93', 1.6),
      logout: ic('logout', '#FF6B5E', 1.7)
    }
  },

  async onShow() {
    // tab 切换入场：每次 onShow 重放淡入上浮
    this.setData({ enter: false });
    wx.nextTick(() => this.setData({ enter: true }));
    if (this.getTabBar && this.getTabBar()) this.getTabBar().setData({ selected: 3 });
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    if (!app.globalData.user) {
      svc.getUser().then(u => { app.globalData.user = u; this.render(); }).catch(() => {});
    }
    if (!app.globalData.cars || !app.globalData.cars.length) {
      svc.getCars().then(cars => {
        app.globalData.cars = cars || [];
        if (!app.globalData.car && cars.length) {
          app.globalData.car = cars[0];
          app.globalData.carId = cars[0].CarId || cars[0].carId || '';
        }
        this.render();
      }).catch(() => {});
    }
    this.render();
  },

  render() {
    const user = VM.userModel(app.globalData.user);
    const car = VM.vehicleSummary(app.globalData.car);
    const ins = car && car.insuranceDays !== null && car.insuranceDays !== undefined ? car.insuranceDays : null;
    this.setData({
      user,
      car,
      insExpired: ins !== null && ins < 0,
      insWarn: ins !== null && ins >= 0 && ins <= 30,
      carCount: (app.globalData.cars || []).length,
      carList: (app.globalData.cars || []).map(c => `${c.CarName || ''} ${c.PlateNumber || ''}`.trim())
    });
  },

  go(e) {
    const url = e.currentTarget.dataset.url;
    if (url) wx.navigateTo({ url });
  },

  onSwitchCar(e) {
    const idx = Number(e.detail.value);
    const car = app.globalData.cars[idx];
    if (!car) return;
    app.globalData.car = car;
    app.globalData.carId = car.CarId || car.carId || '';
    this.render();
  },

  goDev() { wx.navigateTo({ url: '/pages/dev/dev' }); },
  goData() { wx.navigateTo({ url: '/pages/data/data?kind=status' }); },

  showAbout() {
    const ver = svc.getFnVersion();
    const mode = C.USE_CLOUD ? `云函数${C.LOGIN_VIA_DIRECT ? ' · 登录直连' : ''}` : '直连';
    wx.showModal({
      title: '长安车管家',
      content: `版本 v3\n网络通道：${mode}${ver ? ' · ' + ver : ''}\n\n车况数据实时来自车辆车联网服务，仅用于本人车辆管理。`,
      showCancel: false,
      confirmText: '关闭'
    });
  },

  logout() {
    wx.showModal({
      title: '退出登录',
      content: '退出后将清除本地车辆数据缓存，确定退出当前账号吗？',
      confirmText: '退出',
      confirmColor: '#FF453A',
      success: res => {
        if (!res.confirm) return;
        app.clearTokenConfig();
        wx.reLaunch({ url: '/pages/login/login' });
      }
    });
  }
});
