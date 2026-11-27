const TOKEN_KEY = 'car_token_config';
const CACHE_KEY = 'car_data_cache';
const C = require('./utils/config');

App({
  globalData: {
    isLoggedIn: false,
    phone: '',
    cars: [],
    carId: '',
    car: null,
    user: null,
    caches: {
      charge: null,
      pm25: null,
      location: null,
      control: null,
      check: null,
      messages: null
    },
    statusText: ''
  },

  onLaunch() {
    if (C.USE_CLOUD && wx.cloud) {
      wx.cloud.init({ env: C.CLOUD_ENV || undefined, traceUser: true });
    }
    const cfg = wx.getStorageSync(TOKEN_KEY);
    if (cfg && cfg.accessToken) {
      this.globalData.isLoggedIn = true;
      this.globalData.phone = cfg.mobile || '';
    }
    const cache = wx.getStorageSync(CACHE_KEY);
    if (cache && typeof cache === 'object') {
      this.globalData.caches = Object.assign(this.globalData.caches, cache);
    }
  },

  getTokenConfig() {
    return wx.getStorageSync(TOKEN_KEY) || null;
  },

  saveTokenConfig(cfg) {
    cfg.updateTime = new Date().toString();
    wx.setStorageSync(TOKEN_KEY, cfg);
    this.globalData.isLoggedIn = !!cfg.accessToken;
    this.globalData.phone = cfg.mobile || '';
  },

  clearTokenConfig() {
    wx.removeStorageSync(TOKEN_KEY);
    this.globalData.isLoggedIn = false;
    this.globalData.cars = [];
    this.globalData.carId = '';
    this.globalData.car = null;
    this.globalData.user = null;
    this.globalData.caches = {
      charge: null, pm25: null, location: null, control: null, check: null, messages: null
    };
    wx.removeStorageSync(CACHE_KEY);
  },

  saveCache(caches) {
    this.globalData.caches = Object.assign(this.globalData.caches, caches);
    wx.setStorageSync(CACHE_KEY, this.globalData.caches);
  }
});
