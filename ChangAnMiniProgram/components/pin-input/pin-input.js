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
      } catch (e) {  }
    },
    onKey(e) {
      const k = e.currentTarget.dataset.k;
      if (k === 'del') return this.backspace();
      if (k === '') return;
      this.clearAuto();
      const pin = (this.data.pin + k).replace(/\D/g, '').slice(0, 6);
      this.setData({ pin, boxes: this.renderBoxes(pin) });
      this.haptic(false);
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