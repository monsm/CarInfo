const svc = require('../../utils/service');
const { loginSceneURI } = require('../../utils/scene');
const app = getApp();

Page({
  data: {
    phone: '',
    picCode: '',
    smsCode: '',
    captchaSrc: '',
    statusText: '',
    statusCls: '',
    busy: false,
    smsBtnDisabled: false,
    smsBtnText: '获取验证码',
    smsCountdown: 0,
    focusRow: '',
    sceneImg: loginSceneURI()
  },

  onLoad() {
    this.countdownTimer = null;
    this._noRecordRetried = false;
  },

  onShow() {
    const cfg = svc.getTokenCfg();
    if (cfg && cfg.accessToken) {
      wx.switchTab({ url: '/pages/home/home' });
      return;
    }
    this._noRecordRetried = false;
    if (this.data.phone) this.loadCaptcha(true);
  },

  onUnload() { this.stopCountdown(); },

  onPhoneInput(e) { this.setData({ phone: e.detail.value }); },
  onPicCodeInput(e) { this.setData({ picCode: e.detail.value }); },
  onSmsCodeInput(e) { this.setData({ smsCode: e.detail.value }); },

  onFocus(e) { this.setData({ focusRow: e.currentTarget.dataset.f || '' }); },
  onBlur(e) {
    this.setData({ focusRow: '' });
    if (e.currentTarget.dataset.f === 'phone') this.autoLoadCaptcha();
  },

  autoLoadCaptcha() {
    const phone = this.data.phone.trim();
    if (!phone) return;
    if (this._captchaPhone === phone) return;
    this._noRecordRetried = false;
    this.loadCaptcha(true);
  },

  onTapCaptcha() {
    this._noRecordRetried = false;
    this.loadCaptcha(true);
  },

  async loadCaptcha(silent) {
    const phone = this.data.phone.trim();
    if (!phone) {
      if (!silent) wx.showToast({ title: '请先输入手机号', icon: 'none' });
      return;
    }
    try {
      const src = await svc.getPicCode(phone);
      this._captchaPhone = phone;
      this.setData({ captchaSrc: src });
    } catch (err) {
      if (!silent) wx.showToast({ title: '获取验证码失败', icon: 'none' });
      this.showStatus('获取验证码失败：' + err.message, 'err');
    }
  },

  showStatus(msg, cls) { this.setData({ statusText: msg || '', statusCls: cls || '' }); },

  startCountdown() {
    this.stopCountdown();
    this.setData({ smsBtnDisabled: true, smsCountdown: 60, smsBtnText: '重新获取 (60)' });
    this.countdownTimer = setInterval(() => {
      const left = this.data.smsCountdown - 1;
      if (left <= 0) {
        this.stopCountdown();
        this.setData({ smsBtnDisabled: false, smsBtnText: '获取验证码' });
      } else {
        this.setData({ smsCountdown: left, smsBtnText: `重新获取 (${left})` });
      }
    }, 1000);
  },
  stopCountdown() {
    if (this.countdownTimer) { clearInterval(this.countdownTimer); this.countdownTimer = null; }
  },

  async sendSms() {
    if (this.data.smsBtnDisabled || this.data.busy) return;
    if (this._smsSending) return;
    this._smsSending = true;
    try {
      const phone = this.data.phone.trim();
      const picCode = this.data.picCode.trim();
      if (!phone || !picCode) {
        wx.showToast({ title: '请填写手机号和图形验证码', icon: 'none' });
        return;
      }
      if (this._captchaPhone !== phone) {
        this.showStatus('手机号已变更，正在重新加载验证码', '');
        this.loadCaptcha(true);
        return;
      }
      const r = await svc.smsSend(phone, picCode);
      if (r.ok) {
        this._noRecordRetried = false;
        this.showStatus(r.msg, 'ok');
        this.startCountdown();
        return;
      }
      if (r.noRecord) {
        if (!this._noRecordRetried) {
          this._noRecordRetried = true;
          this.setData({ picCode: '' });
          await this.loadCaptcha(true);
          this.showStatus('验证码已刷新，请重新输入图形验证码后重试', '');
        } else {
          this.showNoRecordGuidance();
        }
        return;
      }
      this.showStatus(r.msg, 'err');
    } catch (err) {
      this.showStatus('发送失败：' + err.message, 'err');
    } finally {
      this._smsSending = false;
    }
  },

  showNoRecordGuidance() {
    const ver = svc.getFnVersion();
    const verLine = ver ? `（云端通道 ${ver}）` : '（云端通道版本未知）';
    wx.showModal({
      title: '短信发送失败',
      content: `未找到该手机号的图形验证码记录${verLine}。请按序尝试：\n1. 重新部署云函数：cloudfunctions/changanProxy 右键上传并部署，再刷新验证码重试；\n2. 仍失败请把 utils/config.js 的 LOGIN_VIA_DIRECT 改为 true 直连登录（开发者工具勾选“不校验合法域名”）。\n详见「我的-开发者工具」中的排查指引。`,
      confirmText: '知道了',
      success: () => {}
    });
    this.showStatus('验证码记录未找到，已停止自动重试', 'err');
  },

  async doLogin() {
    if (this.data.busy) return;
    const phone = this.data.phone.trim();
    const smsCode = this.data.smsCode.trim();
    const picCode = this.data.picCode.trim();
    if (!phone || !smsCode || !picCode) {
      this.showStatus('请填写手机号、图形验证码与短信验证码', '');
      return;
    }
    this.setData({ busy: true });
    try {
      await svc.login(phone, smsCode, picCode);
      await this.bootstrapData();
    } catch (err) {
      this.showStatus(err.message || '登录失败', 'err');
    } finally {
      this.setData({ busy: false });
    }
  },

  async bootstrapData() {
    try {
      const [cars, user] = await Promise.all([svc.getCars().catch(() => []), svc.getUser().catch(() => null)]);
      app.globalData.user = user;
      app.globalData.cars = cars || [];
      if (cars && cars.length > 0) {
        app.globalData.car = cars[0];
        app.globalData.carId = cars[0].CarId || cars[0].carId || '';
        const data = await svc.fetchVehicleData(app.globalData.carId);
        app.saveCache(data);
      }
      wx.switchTab({ url: '/pages/home/home' });
    } catch (err) {
      wx.switchTab({ url: '/pages/home/home' });
    }
  },

  goDev() {
    wx.navigateTo({ url: '/pages/dev/dev?from=login' });
  }
});
