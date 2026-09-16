// pin-input —— 6 位控车码输入（液态玻璃弹层 + 内置数字键盘）
// 修复：不再使用隐藏 input 唤起系统键盘（系统键盘会与底部弹层重叠，
// 且 Android 上行为不稳定），改为弹层内自绘 3×4 数字键盘——彻底无重叠。
Component({
  options: { styleIsolation: 'apply-shared' },
  properties: {
    show: { type: Boolean, value: false }
  },
  data: {
    pin: '',
    boxes: ['', '', '', '', '', ''],
    keys: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del']
  },
  observers: {
    show(v) {
      // 每次打开重置，避免上次输入残留
      this.clearAuto();
      this.setData({ pin: '', boxes: ['', '', '', '', '', ''] });
    }
  },
  methods: {
    noop() {},
    renderBoxes(digits) {
      const boxes = ['', '', '', '', '', ''];
      for (let i = 0; i < digits.length; i++) boxes[i] = digits[i];
      return boxes;
    },
    clearAuto() {
      if (this._autoT) { clearTimeout(this._autoT); this._autoT = null; }
    },
    haptic(heavy) {
      try {
        wx.vibrateShort({ type: heavy ? 'heavy' : 'light' });
      } catch (e) { /* 低版本忽略 */ }
    },
    onKey(e) {
      const k = e.currentTarget.dataset.k;
      if (k === 'del') return this.backspace();
      if (k === '') return;
      this.clearAuto();
      const pin = (this.data.pin + k).replace(/\D/g, '').slice(0, 6);
      this.setData({ pin, boxes: this.renderBoxes(pin) });
      this.haptic(false);
      // 输满 6 位自动执行（350ms 内仍可回退）
      if (pin.length === 6) {
        this._autoT = setTimeout(() => this.onConfirm(), 350);
      }
    },
    backspace() {
      this.clearAuto();
      const pin = this.data.pin.slice(0, -1);
      this.setData({ pin, boxes: this.renderBoxes(pin) });
    },
    onCancel() {
      this.clearAuto();
      this.setData({ pin: '', boxes: ['', '', '', '', '', ''] });
      this.triggerEvent('cancel');
    },
    onConfirm() {
      const pin = this.data.pin;
      if (pin.length !== 6) return;
      this.clearAuto();
      this.setData({ pin: '', boxes: ['', '', '', '', '', ''] });
      this.haptic(true);
      this.triggerEvent('confirm', { pin });
    }
  }
});