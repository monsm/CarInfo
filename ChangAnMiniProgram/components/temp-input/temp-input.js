// TemperatureInputDialog 组件 —— 空调温度设置(17-33℃)
Component({
  options: { styleIsolation: 'apply-shared' },
  properties: {
    show: { type: Boolean, value: false }
  },
  data: {
    temp: 25,
    min: 17,
    max: 33
  },
  observers: {
    show(v) { if (v) { this.setData({ temp: 25 }); } }
  },
  methods: {
    noop() {},
    minus() {
      const t = Math.max(this.data.min, this.data.temp - 1);
      this.setData({ temp: t });
    },
    plus() {
      const t = Math.min(this.data.max, this.data.temp + 1);
      this.setData({ temp: t });
    },
    onCancel() { this.triggerEvent('cancel'); },
    onConfirm() {
      this.triggerEvent('confirm', { temperature: this.data.temp });
    }
  }
});
