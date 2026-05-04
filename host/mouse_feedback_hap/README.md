# mouse_feedback_hap — 鼠标位置实时反馈（HAP 版）

在被控 HarmonyOS 设备上运行，通过原生 API `OH_Input_AddMouseEventMonitor` 监听全局鼠标移动，然后通过 UDP 发送给 BtGamePad App。

## 与 CLI 版的区别

| | CLI 版 | HAP 版 |
|------|--------|--------|
| 权限 | shell 进程无权限模型 | HAP 可声明 `INPUT_MONITORING` 权限 |
| UI | 无 | 有完整的设置界面 |
| 部署 | `hdc file send` | 可通过 hdc install / DevEco Studio 部署 |
| 运行 | 命令行 | 桌面图标启动 |

## 构建

在 DevEco Studio 中打开 `host/mouse_feedback_hap/` 目录，点击 Build → Build HAP。

或使用命令行：

```powershell
hvigorw assembleHap
```

## 部署

```powershell
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

## 使用

1. 在被控设备上启动"鼠标位置反馈"应用
2. 输入 BtGamePad App 所在设备的 IP 地址和端口
3. 调整发送频率（默认 60 Hz）
4. 点击"开始发送"

## 权限

本应用需要以下权限：
- `ohos.permission.INPUT_MONITORING` — 监听全局鼠标事件
- `ohos.permission.INTERNET` — UDP 网络通信

首次启动时系统会弹窗请求授权。在开发者模式下通常可正常获取。

## 数据协议

与 CLI 版相同：8 字节小端序二进制（int32 x, int32 y）。

## 配合 BtGamePad 使用

1. 在 App 执行模式的"模拟鼠标"面板中，开启"鼠标位置反馈"
2. 设置端口号与本应用一致（默认 21345）
3. 在本应用中输入 App 设备的 IP 地址
4. 点击"开始发送"，App 端状态指示灯变为绿色即表示正常工作
