const { ci, s, num, num1, num2, num3, num0, SEP, SMALL, CHRG_STATUS, GENDER, directionText, cmdText, norm360 } = require('./fmt');

const CHECK_STATUS_CN = { normal: '正常', fault: '故障', warning: '预警', risk: '风险', abnormal: '异常', ok: '正常' };
function checkStatus(v) {
  const k = String(v == null ? '' : v).toLowerCase();
  return CHECK_STATUS_CN[k] || (v == null ? '' : String(v));
}

function buildTitle(title) { return `${title}\n${SEP}\n`; }

const lines = [];
function L(v) { lines.push(s(v)); }

function userText(raw) {
  const u = ci(raw);
  lines.length = 0;
  L(buildTitle('👤 USER INFORMATION'));
  L('🔑 CORE ACCOUNT'); L(SMALL);
  L(`用户ID : ${u.UserId}`); L(`用户昵称 : ${u.UserNickname}`); L(`真实姓名 : ${u.UserFullname}`);
  L(`手机号码 : ${u.Mobile}`); L(`性别 : ${GENDER[u.Gender] || '未知'}`);
  L(`实名认证 : ${u.RealnameAuthed ? '✅ 已认证' : '❌ 未认证'}`); L();
  L('📇 ID & CONTACT'); L(SMALL);
  L(`证件类型 : ${u.IdcardType}`); L(`证件号码 : ${u.Idcard}`); L(`出生日期 : ${u.Birthday}`);
  L(`邮箱 : ${u.Email || '无'}`); L(`联系地址 : ${u.Address || '无'}`); L(`座机 : ${u.Telephone || '无'}`);
  L(`紧急联系人 : ${u.ContactsName || '无'}`); L(`紧急联系电话 : ${u.ContactsMobile || '无'}`); L();
  L('📊 ACCOUNT STATUS'); L(SMALL);
  L(`OpenID : ${u.OpenId}`); L(`注册时间 : ${u.RegisterTime}`); L(`最后登录时间 : ${u.LastLoginTime}`);
  L(`账号状态 : ${u.Status === '1' ? '正常' : '异常'}`); L(`账号锁定 : ${num(u.Locked) === 0 ? '未锁定' : '已锁定'}`);
  L(`账号删除 : ${num(u.Deleted) === 0 ? '未删除' : '已删除'}`); L(`注册来源 : ${u.Source}`); L();
  L('🌍 REGION & PLATFORM'); L(SMALL);
  L(`所在地区 : ${s(u.Country)}${s(u.Province)}${s(u.City)}${s(u.Dist)}`); L(`社区 : ${u.Community || '无'}`);
  L(`租户ID : ${u.TenantId || '无'}`); L(`绑定车辆ID : ${u.CarId || '无'}`); L(`绑定车牌号 : ${u.PlateNumber || '无'}`);
  L(`品牌名称 : ${u.BrandName || '无'}`); L(`IM用户ID : ${u.ImUserId || '无'}`);
  L(`头像状态 : ${u.FaceImg ? '已设置' : '未设置'}`); L(`激活时间 : ${u.ActiveTime || '无'}`);
  L(`认证类型 : ${u.AuthenticationType || '无'}`);
  return lines.join('\n');
}

function carText(raw) {
  const c = ci(raw);
  lines.length = 0;
  L(buildTitle('🚗 VEHICLE INFORMATION'));
  L('🔑 CORE IDENTIFICATION'); L(SMALL);
  L(`车辆ID : ${c.CarId}`); L(`VIN车架号 : ${c.Vin}`); L(`车辆名称 : ${c.CarName}`);
  L(`车牌号 : ${c.PlateNumber}`); L(`是否新能源 : ${num(c.IsNev) === 1 ? '是' : '否'}`);
  const pinCN = { exist: '已设置', none: '未设置' };
  L(`PIN码状态 : ${pinCN[String(c.Pin == null ? '' : c.Pin).toLowerCase()] || s(c.Pin) || '无'}`); L();
  L('📋 BASIC CONFIGURATION'); L(SMALL);
  L(`车型代码 : ${c.ModelCode}`); L(`配置代码 : ${c.ConfCode}`); L(`配置名称 : ${c.ConfName}`);
  L(`品牌代码 : ${c.BrandCode}`); L(`车系代码 : ${c.SeriesCode}`); L(`当前设备类型 : ${c.CurrentDeviceType}`);
  L(`车辆类型 : ${c.CarType}`); L(`颜色 : ${c.Color ? c.Color : '未设置'}`); L(`图片 : ${c.Img}`); L();
  L('📅 REGISTRATION & INSURANCE'); L(SMALL);
  L(`注册时间 : ${c.RegisterTime}`); L(`产品时间 : ${c.ProductTime}`); L(`保险到期 : ${c.InsuranceEndDate}`);
  L(`保险公司 : ${c.InsuranceCompany}`); L(`保险电话 : ${c.InsurancePhone}`); L();
  L('👤 USER & SERVICE INFO'); L(SMALL);
  L(`用户ID : ${c.UserId}`); L(`租户ID : ${c.TenantId}`); L(`服务状态 : ${c.TserviceStatus}`);
  L(`服务结束时间 : ${c.TserviceEndtime}`);
  const authCN = { authed: '已认证', unauth: '未认证', none: '未认证' };
  L(`实名认证 : ${authCN[String(c.RealnameAuthStatus == null ? '' : c.RealnameAuthStatus).toLowerCase()] || s(c.RealnameAuthStatus) || '无'}`);
  L(`是否CA车辆 : ${(c.IsCaCar === true || c.IsCaCar === 'true') ? '是' : '否'}`);
  L(`绑定京东 : ${(c.BindedJd === true || c.BindedJd === 'true') ? '是' : '否'}`); L(`激活时间 : ${c.ActiveTime}`); L();
  L('🔧 MAINTENANCE & EXTENDED'); L(SMALL);
  L(`保养间隔里程 : ${num0(c.MaintainSpaceMileage)} km`); L(`上次保养里程 : ${num0(c.LastMaintainMileage)} km`);
  L(`隐私驾驶历史 : ${num(c.IsPrivacyDrvingHistory) === 1 ? '启用' : '禁用'}`); L(`功能权限配置 : ${c.FunCode}`);
  L(`最后检查时间 : ${c.LastCheckTime}`); L(`最后在线时间 : ${c.LastOnlineTime || '未知'}`);
  L(`来源 : ${c.Source}`); L(`车辆名称(显示) : ${c.CarNameForCar}`); L(`发动机号 : ${c.EngineNo}`);
  return lines.join('\n');
}

function statusText(raw) {
  const d = ci(raw);
  lines.length = 0;
  L(buildTitle('🎛️ FULL VEHICLE STATUS'));
  L('🔋 CORE STATUS'); L(SMALL);
  const carStatus = num(d.CarStatus);
  L(`车辆总状态 : ${carStatus} (${carStatus === 2 ? '熄火' : (carStatus === 1 ? '启动' : '未知')})`);
  L(`车辆状态码 : ${d.Status || '未知'}`);
  const fire = d.FireStatus || '未知';
  L(`点火状态 : ${fire} (${fire === '2' ? '熄火' : '启动'})`);
  L(`车速 : ${num1(d.VehicleSpeed)} km/h | Tbox车速：${num1(d.Speed)} km/h`);
  L(`总里程 : ${num1(d.TotalOdometer)} km`);
  L(`定位有效 : ${d.ValidGps ? '✅ 是' : '❌ 否'} | 合法定位：${d.IsValidGps ? '✅ 是' : '❌ 否'}`);
  L(`GPS无效标记 : ${num(d.IsInValidGps)} | 历史定位点：${num(d.IsHistoryPoi)} (${num(d.IsHistoryPoi) === 0 ? '当前位置' : '历史位置'})`);
  L(`经纬度 : ${num6(d.Lat)} , ${num6(d.Lng)} | 海拔高度：${num1(d.Alti)} m`);
  L(`航向角度 : ${num1(norm360(d.Heading))}° | 卫星数量：${num(d.SatNum)} 颗`);
  L(`GPS时间 : ${d.GpsTime || '未知'}`); L();
  L('🚪 DOORS / WINDOWS / LIGHTS'); L(SMALL);
  L(`整车车门 : ${num(d.Door)} (${num(d.Door) === 0 ? '全部关闭' : '存在开启'})`);
  const win = d.Window !== null && d.Window !== undefined ? d.Window : '0';
  L(`整车车窗 : ${win} (${win === '0' ? '全部关闭' : '存在开启'})`);
  L(`引擎盖 : ${num(d.Hood)} (${num(d.Hood) === 0 ? '关闭' : '开启'}) | 后备箱：${num(d.Trunk)} (${num(d.Trunk) === 0 ? '关闭' : '开启'})`);
  L(`天窗 : ${num(d.Sunroof)} (${num(d.Sunroof) === 0 ? '关闭' : '开启'})`);
  L(`驾驶位门 : ${num(d.DriverDoor)} | 锁：${num(d.DriverDoorLock)} (${num(d.DriverDoorLock) === 0 ? '上锁' : '未锁'})`);
  L(`副驾位门 : ${num(d.PassengerDoor)} | 锁：${num(d.PassengerDoorLock)} (${num(d.PassengerDoorLock) === 0 ? '上锁' : '未锁'})`);
  L(`左前门 : ${num(d.LeftFrontDoor)} | 状态：${num(d.LeftFrontDoorStatus)} | 锁：${num(d.LeftFrontDoorLock)}`);
  L(`右前门 : ${num(d.RightFrontDoor)} | 状态：${num(d.RightFrontDoorStatus)} | 锁：${num(d.RightFrontDoorLock)}`);
  L(`左后门 : ${num(d.LeftRearDoor)} | 状态：${num(d.LeftRearDoorStatus)} | 锁：${num(d.LeftRearDoorLock)}`);
  L(`右后门 : ${num(d.RightRearDoor)} | 状态：${num(d.RightRearDoorStatus)} | 锁：${num(d.RightRearDoorLock)}`);
  L(`左前窗开度 : ${num0(d.LeftAnteriorWindowDegree)}° | 状态：${num(d.LeftFrontDoorrWindow)}`);
  L(`右前窗开度 : ${num0(d.RightAnteriorWindowDegree)}° | 状态：${num(d.RightFrontDoorrWindow)}`);
  L(`左后窗开度 : ${num0(d.LeftRearWindowDegree)}° | 状态：${num(d.LeftRearDoorrWindow)}`);
  L(`右后窗开度 : ${num0(d.RightRearWindowDegree)}° | 状态：${num(d.RightRearWindow)}`);
  L(`整车灯光总状态 : ${num(d.Light)}`);
  L(`近光灯 : ${num(d.LowBeam)} | 远光灯：${num(d.HighBeam)}`);
  L(`前雾灯 : ${num(d.FrontFoglamp)}/${num(d.FrontFogLight)} | 后雾灯：${num(d.RearFoglamp)}/${num(d.RearFogLight)}`);
  L(`示廓灯/位置灯 : ${num(d.PositionLamp)}/${num(d.PositionLight)}`);
  L(`左转向灯 : ${num(d.LeftTurnSignal)}/${num(d.TurnLndicatorLeft)} | 右转向灯：${num(d.RightTurnSignal)}/${num(d.TurnLndicatorRight)}`);
  L(`转向灯总状态 : ${num(d.TurnLndicator)}`); L();
  L('🕹️ PEDALS & CLIMATE'); L(SMALL);
  L(`油门踏板 : ${num(d.AccPedal)} (${num(d.AccPedal) === 0 ? '未踩下' : '已踩下'})`);
  L(`刹车踏板 : ${num(d.BrakePedal)} (${num(d.BrakePedal) === 0 ? '未踩下' : '已踩下'})`);
  L(`离合踏板 : ${num(d.CutchPedal)} (${num(d.CutchPedal) === 0 ? '未踩下' : '已踩下'} 电车无离合)`);
  const air = ci(d.Air || {});
  const airStatus = s(air.Status, '0');
  L(`空调状态 : ${airStatus} (${airStatus === '0' ? '关闭' : '开启'})`);
  L(`空调温度 : ${s(air.Temperature, '26')}℃ | 风量：${s(air.Wind, '0')}档`);
  L(`空气净化器 : ${num(d.AirPurifierStatus)} (${num(d.AirPurifierStatus) === 0 ? '关闭' : '开启'}) | 车内PM2.5：${num(d.Pm25)}`);
  L(`主驾座椅 : 通风${num(d.DriverSeatAirStatus)} | 加热${num(d.DriverSeatHeatStatus)}`);
  L(`副驾座椅 : 通风${num(d.PassengerSeatAirStatus)} | 加热${num(d.PassengerSeatHeatStatus)}`); L();
  L('🔋 BATTERY CORE'); L(SMALL);
  L(`SOC电量 : ${num(d.Soc)}% | 剩余电量：${num(d.RemainPower)}% | 当前电量：${num(d.CurrentElectricity)}%`);
  L(`续航里程 : ${num1(d.RemainedPowerMile)} km`);
  L(`电池总电压 : ${num1(d.TotalVoltage)} V | 电池总电流：${num1(d.TotalCurrent)} A`);
  L(`绝缘电阻 : ${num0(d.InsulateResistance)} Ω`);
  L(`电池状态 : ${num(d.PowerBatteryStatus)} | 电池电源系统：${num(d.BatteryPowerSystemStatus)}`);
  L(`电池加热 : ${num(d.BatteryHeatingStatus)} (${num(d.BatteryHeatingStatus) === 0 ? '关闭' : '开启'})`);
  L(`充电状态 : ${num(d.BatteryChargeStatus)} | 充电指示灯：${num(d.BatteryChargeLightStatus)}`); L();
  L('📊 BATTERY CELL EXTREMES'); L(SMALL);
  L(`单体最高电压 : ${num3(d.MaxVoltageBattery)}V (编号：${num(d.MaxVoltageBatteryNum)})`);
  L(`单体最低电压 : ${num3(d.MinVoltageBattery)}V (编号：${num(d.MinVoltageBatteryNum)})`);
  L(`电池最高温度 : ${num(d.MaxTemperatureValue)}℃ (探针：${num(d.MaxTemperatureProbe)})`);
  L(`电池最低温度 : ${num(d.MinTemperatureValue)}℃ (探针：${num(d.MinTemperatureProbe)})`);
  L(`最高电压子系统 : ${num(d.MaxVoltageBatterySubSystemNum)} | 最低电压子系统：${num(d.MinVoltageBatterySubSystemNum)}`);
  L(`最高温度子系统 : ${num(d.MaxTemperatureSubSystemNum)} | 最低温度子系统：${num(d.MinTemperatureSubSystemNum)}`); L();
  L('🔋 BATTERY VOLTAGE CELLS');
  const voltList = d.NevChargeSystemVoltageDtoList;
  if (voltList && voltList.length > 0) {
    voltList.forEach(item => {
      const it = ci(item);
      L(`子系统编号 : ${num(it.ChildSystemNum)}`);
      L(`电池总串数 : ${num(it.BatteryCount)} | 当前采集：${num(it.CurrentBatteryCount)}`);
      L(`总电压 : ${num(it.ChargeSystemVoltage)}V | 总电流：${num(it.ChargeSystemCurrent)}A`);
      const cells = (it.BatteryVoltage || []).map(x => num3(x)).join(' | ');
      L(`单体电压列表 : ${cells || '无'} V`);
    });
  } else { L('无电池电压数据'); }
  L(); L('🌡️ BATTERY TEMPERATURE PROBES');
  const tempList = d.NevChargeSystemTemperatureDtoList;
  if (tempList && tempList.length > 0) {
    tempList.forEach(item => {
      const it = ci(item);
      L(`子系统编号 : ${num(it.ChildSystemNum)}`);
      L(`探针总数 : ${num(it.ChargeTemperatureProbeNum)}`);
      const temps = (it.ProbeTemperatures || []).map(x => s(x)).join(' | ');
      L(`探针温度列表 : ${temps} ℃`);
    });
  } else { L('无电池温度探针数据'); }
  L(); L('🔌 CHARGING SYSTEM'); L(SMALL);
  const chg = num(d.ChargeStatus);
  L(`充电状态 : ${chg} (${chg === 3 ? '完成' : (chg === 1 ? '充电中' : '未充电')})`);
  L(`预约充电 : ${num(d.ChargeReservationStatus)} (${num(d.ChargeReservationStatus) === 0 ? '未开启' : '已开启'})`);
  L(`充电时长 : ${num(d.ChargDeltMins)} 分钟 | 充电开始：${d.ChargeStarttime || '无'} | 充电结束：${d.ChargeStoptime || '无'}`);
  L(`电源线路状态 : ${num(d.PowerLineStatus)} | 电源状态反馈：${num(d.PowerStatusFeedBack)}`); L();
  L('⚙️ DRIVE MOTOR SYSTEM'); L(SMALL);
  L(`电机数量 : ${num(d.DriveMotorNum)} | 电机系统状态：${num(d.MotorSystemStatus)}`);
  L(`DC状态 : ${num(d.DcStatus)} | DCDC状态报警：${num(d.DcdcStatusAlarm)} | DCDC温度报警：${num(d.DcdcTemperatureAlarm)}`);
  const motors = d.DriveMotorData || d.MotorData;
  if (motors && motors.length > 0) {
    motors.forEach(motor => {
      const m = ci(motor);
      L(`电机编号 : ${num(m.Num)} | 状态：${num(m.State)} | 转速：${num(m.RevolutionSpeed)} rpm`);
      L(`电机温度 : ${num(m.Temperature)}℃ | 控制器温度：${num(m.ControllerTemperature)}℃`);
      L(`扭矩 : ${num(m.Torque)} N·m | 输入电压：${num(m.ControllerInputVoltage)}V`);
      L(`控制器母线电流 : ${num(m.ControllerDcBusCurrent)} A`);
    });
  }
  L(); L('🛞 TYRE PRESSURE'); L(SMALL);
  L(`左前 : ${num(d.LfTyrePressure)}kPa | 温度：${num(d.LeftFrontTireTemperature)}℃ | 报警：${num(d.LfPressureWarning)}`);
  L(`右前 : ${num(d.RfTyrePressure)}kPa | 温度：${num(d.RightFrontTireTemperature)}℃ | 报警：${num(d.RfPressureWarning)}`);
  L(`左后 : ${num(d.LrTyrePressure)}kPa | 温度：${num(d.LeftRearTireTemperature)}℃ | 报警：${num(d.LrPressureWarning)}`);
  L(`右后 : ${num(d.RrTyrePressure)}kPa | 温度：${num(d.RightRearTireTemperature)}℃ | 报警：${num(d.RrPressureWarning)}`);
  L(`轮胎温度状态 : ${num(d.TireTemperatureStatus)}`); L();
  L('🛡️ SAFETY & FAULTS'); L(SMALL);
  L(`安全气囊系统 : ${num(d.AirbagSystemStatus)} (${num(d.AirbagSystemStatus) === 0 ? '正常' : '故障'})`);
  L(`制动系统报警 : ${num(d.BrakeSystemAlarm)} | 钥匙报警：${num(d.KeyAlarm)} | 钥匙低电量：${num(d.KeyLowPower)}`);
  L(`最高报警等级 : ${num(d.MaxAlarmLevel)}`);
  L(`电池总报警 : ${num(d.BatteryAlarm)} | 电池一致性报警：${num(d.BatteryConsistencyDifferenceAlarm)}`);
  L(`绝缘报警 : ${num(d.InsulationAlarm)} | 高压互锁报警：${num(d.HighVoltageInterlockStateAlarm)}`);
  L(`单体过压报警 : ${num(d.SingleBatteryOverVoltageAlarm)} | 单体欠压报警 : ${num(d.SingleBatteryUnderVoltageAlarm)}`);
  L(`SOC低报警 : ${num(d.SocLowAlarm)} | SOC高报警：${num(d.SocHighAlarm)} | SOC跳变报警：${num(d.SocJumpAlarm)}`);
  L(`温度差异报警 : ${num(d.TemperatureDifferenceAlarm)}`);
  L(`电机温度报警 : ${num(d.DriveMotorTemperatureAlarm)} | 电机控制器温度报警：${num(d.DriveMotorControllerTemperatureAlarm)}`);
  L(`储能设备过压 : ${num(d.VehicleStorageDeviceOvervoltageAlarm)} | 储能设备欠压：${num(d.VehicleStorageDeviceUndervoltageAlarm)}`);
  L(`储能设备不匹配 : ${num(d.RechargeableStorageDeviceMismatchAlarm)} | 设备过充报警：${num(d.VehiclePureDeviceTypeOvercharge)}`); L();
  L('⚠️ FAULT CODES'); L(SMALL);
  L(`发动机故障数 : ${num(d.EngineFaultCount)} | 故障码：${d.EngineFaultCodes || '无'}`);
  L(`驱动电机故障数 : ${num(d.DriveMotorFaultCount)} | 故障码：${d.DriveMotorFaultCodes || '无'}`);
  L(`储能设备故障数 : ${num(d.RechargeableStorageDevicesFaultCount)} | 故障码：${d.RechargeableStorageDevicesFaultCodes || '无'}`);
  L(`其他故障数 : ${num(d.OtherFaultCount)} | 故障码：${d.OtherFaultCodes || '无'}`); L();
  L('🏎️ EXTENDED RUNNING PARAMS'); L(SMALL);
  L(`档位 : ${num(d.ShiftPosition)} (${num(d.ShiftPosition) === 0 ? 'P档（驻车）' : '行驶档'}) | 档位状态：${num(d.ShiftPositionStatus)}`);
  L(`驱动力 : ${num(d.GearDriveForce)} | 怠速状态：${num(d.Conditionidle)} (${num(d.Conditionidle) === 0 ? '非怠速' : '怠速'})`);
  L(`车辆模式 : ${num(d.CarMode)} | 前进标记：${num(d.ForwardFlag)}`);
  L(`断油标志 : ${num(d.EngineFuelCutOffFlag)}（电车无效） | 短期燃油修正：${num(d.ShortTermFuelTrim)}（电车无效）`); L();
  L('📟 SYSTEM IDENTIFIERS'); L(SMALL);
  L(`VIN车架号 : ${d.Vin || '未知'}`);
  L(`车辆ID：${d.CarId || '未知'}`);
  L(`用户ID：${d.UserId || '未知'}`);
  L(`TUID设备号：${d.Tuid || '未知'}`);
  L(`车型系列 : ${d.SeriesCode || '未知'} | 车辆配置码：${d.CarConfCode || '未知'} | 设备类型：${d.DeviceType || '未知'}`);
  L(`协议版本 : ${num(d.ProtocolVer)} | SID&MID：${d.SidAndMid || '未知'} | 容器名称：${d.ContainerName || '服务器内部标识'} | 请求ID：${d.RequestId || '未知'}`);
  L(`终端时间 : ${d.TerminalTime || '未知'}`);
  L(`设备时间：${d.DeviceTime || '未知'}`);
  L(`服务器时间：${d.ServerTime || '未知'}`);
  L(`点火时间 : ${d.IgnitionTime || '未知'}`);
  L(`记录时间：${d.RecordTime || '未知'}`);
  L(`最后登录时间：${d.LastLoginTime || '未知'}`);
  L(`最后更新时间：${d.LastUpdatedTime || '未知'}`);
  return lines.join('\n');
}

function num6(v) {
  const n = num(v);
  return n.toFixed(6);
}

function chargeText(raw) {
  const d = ci(raw);
  lines.length = 0;
  L(buildTitle('🔋 CHARGING STATUS'));
  const st = CHRG_STATUS[d.ChrgStatus] || '未充电';
  L(`充电状态 : ${st}`);
  L(`当前电量 : ${num(d.RemainPower)}%`);
  L(`续航里程 : ${num(d.RemainedPowerMile)} km`);
  L(`充电时长 : ${num(d.ChargDeltMins)} 分钟`);
  L(`开始时间 : ${d.ChargeStarttime}`);
  L(`结束时间 : ${d.ChargeStoptime}`);
  L(`电源状态 : ${num(d.PowerLineStatus) === 0 ? '正常' : '异常'}`);
  L(`电池加热 : ${num(d.BatteryHeatingStatus) === 1 ? '开启' : '关闭'}`);
  L(`预约充电 : ${num(d.ChargeReservationStatus) === 1 ? '已开启' : '未开启'}`);
  L(`预约电池加热 : ${d.ReservationBatteryHeatingStatus}`);
  L(`预约用车时间 : ${d.ReservationUseVehicleTime}`);
  return lines.join('\n');
}

function locationText(raw) {
  const d = ci(raw);
  lines.length = 0;
  L(buildTitle('📍 VEHICLE LOCATION'));
  L(`车辆ID : ${d.CarId}`);
  L(`经度 : ${d.Lng}`);
  L(`纬度 : ${d.Lat}`);
  L(`详细地址 : ${d.AddrDesc}`);
  L(`GPS时间 : ${d.GpsTime}`);
  L(`车速 : ${num1(d.Speed)} km/h`);
  L(`方向角 : ${num1(norm360(d.Heading))} °`);
  const st = num(d.Status);
  L(`车辆状态 : ${st} (${st === 2 ? '熄火' : '行驶'})`);
  L(`GPS有效 : ${d.ValidGps ? '✅ 是' : '❌ 否'}`);
  L(`加速度 : ${d.Accel || '无'}`);
  L(`位置图片时间 : ${d.LocationImgActionTime}`);
  L(`位置图片URL : ${d.LocationImgurl}`);
  L(`缩略图URL : ${d.ThumbnailLocationImgUrl}`);
  return lines.join('\n');
}

function envText(raw) {
  const d = ci(raw);
  lines.length = 0;
  L(buildTitle('🌬️ ENVIRONMENT & LOCATION'));
  L(`车内PM2.5 : ${s(d.Pm25InnnerCarValue) === '-1' ? '暂无数据' : `${d.Pm25InnnerCarValue} μg/m³`}`);
  L(`车外PM2.5 : ${d.Pm25OuterCarValue || '暂无数据'}`);
  L(`车内温度 : ${d.VehicleTemperature} ℃`);
  L(`环境温度 : ${d.EnvironmentalTemperature} ℃`);
  L(`更新时间 : ${d.UpdateTime}`);
  const loc = ci(d.CarLocationResp || {});
  L(`定位地址 : ${loc.AddrDesc || '暂无定位'}`);
  L(`经度 : ${loc.Lng}`);
  L(`纬度 : ${loc.Lat}`);
  L(`定位状态 : ${num(loc.Status) === 0 ? '有效' : '无效'}`);
  return lines.join('\n');
}

function checkText(raw) {
  const d = ci(raw);
  lines.length = 0;
  L(buildTitle('🩺 VEHICLE HEALTH REPORT'));
  L('📊 DETECTION OVERVIEW');
  L(`检测ID : ${d.CheckHistoryId}`);
  L(`用户ID : ${d.UserId}`);
  L(`车辆ID : ${d.CarId}`);
  L(`检测时间 : ${d.CheckTime}`);
  L(`数据更新时间 : ${d.CarDataUpdateTime}`);
  L(`车辆状态 : ${checkStatus(d.Status)}`);
  L(`健康评分 : ${d.Score} 分`);
  L(`正常项 : ${d.NormalCount} 项`);
  L(`风险项 : ${d.RiskCount} 项`);
  L(`故障项 : ${d.FaultCount} 项`); L();
  if (d.Details && d.Details.length > 0) {
    d.Details.forEach(sys => {
      const s2 = ci(sys);
      L(`🔧 【${s2.ItemName}】`);
      if (s2.Child && s2.Child.length > 0) {
        s2.Child.forEach(item => {
          const it = ci(item);
          L(`▸ ${it.ItemName}`);
          L(` 状态 : ${checkStatus(it.Status) || '正常'}`);
          L(` 描述 : ${it.Description || '无'}`);
          L(` 检测值 : ${it.DetectValue || '无'}`);
          L(` 标准 : ${it.Suggest || '无'}`); L();
        });
      }
      L(SMALL);
    });
  }
  return lines.join('\n');
}

function messagesText(list) {
  lines.length = 0;
  L(buildTitle('📩 MESSAGE CENTER'));
  (list || []).forEach(m => {
    const it = ci(m);
    L(`📬 【${it.Title}】`);
    L(`车牌号 : ${it.RealReceiverId}`);
    L(`时间 : ${it.CreatedAt}`);
    L(`地点 : ${it.Content}`);
    L(`消息ID : ${it.Id}`);
    L(`状态 : ${num(it.ReadStatus) === 0 ? '未读' : '已读'}`);
    L(SMALL);
  });
  return lines.join('\n');
}

function controlLogText(data, pollCount, responseMsg) {
  const d = ci(data);
  lines.length = 0;
  L(buildTitle(`🔄 指令轮询查询 - 第${pollCount}次`));
  L(`指令名称 : ${cmdText(d.TboxCmd)}`);
  L(`任务ID : ${d.TaskId}`);
  L(`车辆ID : ${d.CarId}`);
  L(`下发时间 : ${d.CmdSendTime || '无'}`);
  L(`完成时间 : ${d.CmdFinishTime || '执行中'}`);
  L(`执行状态 : ${d.HandleStatus || '未知'}`);
  L(`状态描述 : ${d.HandleStatusDesc || responseMsg || '无'}`);
  L(`错误码 : ${d.HandleCode || '无'}`);
  L(SMALL); L();
  return lines.join('\n');
}

module.exports = {
  userText, carText, statusText, chargeText, locationText, envText, checkText,
  messagesText, controlLogText, buildTitle, directionText
};
