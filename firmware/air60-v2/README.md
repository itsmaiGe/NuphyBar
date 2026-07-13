# NuphyBar Air60 V2 firmware / 固件

[中文](#中文) · [English](#english)

## 中文

这里保存当前经过实机验证的 **NuPhy Air60 V2 ANSI stable-v7** 固件修改源码、可复现构建器和测试。

> [!CAUTION]
> 这里生成的固件只适用于 Air60 V2 ANSI。不要刷到 Air75 V2、Air96 V2 或其他键盘。确认型号、备份 VIA 键位并准备官方恢复固件后再进入 DFU。

### 为什么采用官方二进制最小补丁

NuPhy 公开 QMK 仓库可以编译 Air60 V2，但实测其构建结果与官方 v2.1.5 发布二进制并不完全一致。官方版本包含重要的 Bluetooth/2.4G 稳定性修复。为避免重新引入早期“灯条冻结并停止输入”的问题，stable-v7 保留官方二进制，仅改变一个经过审计的调用点，并把独立灯效 Hook 放入原固件末尾的空白 Flash。

### 精确布局

| 项目 | 值 |
|---|---:|
| MCU | STM32F072 |
| Flash 基地址 | `0x08000000` |
| 原 `sys_led_show()` 调用地址 | `0x080028EA` |
| 原始调用字节 | `ff f7 5b fd` |
| Hook 地址 | `0x08010E00` |
| 新调用字节 | `0e f0 89 fa` |
| 原 `sys_led_show()` | `0x080023A4` |
| 原 RGB 单灯函数 | `0x08007E38` |
| 原 32 位定时器 | `0x0800B2E8` |
| 无线 `dev_info` | `0x20000C80` |
| Hook 二进制大小 | 332 bytes |

`build_candidate.py` 在写入前会验证官方固件 SHA-256、DFU 后缀、调用点和多个关键函数签名。`verify_candidate.py` 会证明：

1. 调用点以前与官方文件完全一致；
2. 只有 4 字节调用被替换；
3. 调用点之后至官方载荷结尾完全一致；
4. 官方载荷与 Hook 之间只有 `0xFF` 空白；
5. 末尾内容与新编译 Hook 完全一致。

### 状态与灯效

| `rf_led & 0x05` | 状态 | 效果 |
|---:|---|---|
| `0x00` | 空闲 | 不绘制，保留原厂右灯 |
| `0x01` | 工作中 | 蓝色明暗波浪连续循环 |
| `0x04` | 等待/错误 | 琥珀色五格双脉冲 |
| `0x05` | 完成 | 绿色五格呼吸 |

Hook 先调用官方 `sys_led_show()`，所以 Caps Lock 的 `0x02` 与左侧青色灯不变。USB 模式直接返回。调用 Hook 后，官方侧灯刷新流程继续执行。

### 文件

```text
src/agent_light_hook.c       读取官方状态并写入右侧五颗灯
src/effect_model.c           无状态、基于定时器的三种灯效
src/effect_model.h           灯效数据结构和接口
src/agent_light_hook.ld      固定地址与官方符号映射
build_candidate.py           对官方 v2.1.5 应用最小补丁并添加 DFU 后缀
verify_candidate.py          证明候选只包含允许的变化
tests/                       Thumb 跳转和灯效行为测试
test.sh                      在 Mac 主机运行测试
build.sh                     编译、生成并验证固件
```

### 构建

安装依赖：

```bash
brew install arm-none-eabi-gcc@8 arm-none-eabi-binutils dfu-util
```

从 [NuPhy QMK 固件页面](https://nuphy.com/pages/qmk-firmwares) 下载 Air60 V2 ANSI v2.1.5 官方固件。构建器要求官方文件 SHA-256 为：

```text
cd0425f548a01416d1c3c25208ff74867fffd20165520c7c2eaa56000ff347bf
```

运行：

```bash
./firmware/air60-v2/build.sh \
  /path/to/QMK_firmware_nuphy_air60_v2_ansi_v2.1.5.bin
```

默认输出：

```text
firmware/air60-v2/build/NuphyBar-Air60-V2-stable-v7.bin
```

GCC 8.5.0 生成的正式文件 SHA-256：

```text
c573c7939a53994b50f29313744f27f9af30b90cd064f13fc019f87710b89ac0
```

只运行测试：

```bash
./firmware/air60-v2/test.sh
```

### 刷写

推荐使用 [QMK Toolbox](https://github.com/qmk/qmk_toolbox/releases)：

1. 在 VIA 导出键位配置；
2. 下载并校验 NuphyBar 固件；
3. 下载官方 v2.1.5 作为恢复文件；
4. USB 连接键盘；
5. 按住左上角 Esc 插线进入 STM32 DFU，或按 [NuPhy 官方说明](https://nuphy.com/pages/update-instructions) 操作；
6. 确认 QMK Toolbox 检测到目标 DFU 设备；
7. 选择 NuphyBar `.bin` 并刷写，过程中不拔线；
8. 重启后先测试输入、Caps Lock 和蓝牙，再运行 NuphyBar。

高级命令：

```bash
dfu-util -l
dfu-util -a 0 -s 0x08000000:leave \
  -D NuphyBar-Air60-V2-stable-v7.bin
```

执行 `-D` 前必须人工确认准确型号和 DFU 设备。恢复时使用 NuPhy 官方 v2.1.5 文件执行同样流程。

### 限制

- Agent 活跃时会覆盖右侧电量显示；空闲恢复。
- 等待与错误共用 `0x04`，无法从两位标准 HID 通道中再分出第四种状态。
- 固件只对 BLE/2.4G 的无线主机 LED 字段生效；NuphyBar App 当前只发送 BLE。
- 固定函数地址只对经过哈希和签名验证的官方 v2.1.5 基线有效。

## English

This directory contains the source, reproducible builder, and tests for the physically verified **NuPhy Air60 V2 ANSI stable-v7** firmware.

> [!CAUTION]
> The generated image is only for the Air60 V2 ANSI. Never flash it to an Air75 V2, Air96 V2, or another keyboard. Confirm the model, export the VIA layout, and keep the official recovery image before entering DFU.

### Why a minimal patch on the official binary

NuPhy's public QMK tree can build an Air60 V2 image, but the result does not exactly match the official v2.1.5 release. That official release contains important Bluetooth/2.4G stability fixes. `stable-v7` therefore preserves the official binary, redirects one audited function call, and places a self-contained lighting hook in unused flash after the original payload.

### Exact layout

| Item | Value |
|---|---:|
| MCU | STM32F072 |
| Flash base | `0x08000000` |
| original `sys_led_show()` call | `0x080028EA` |
| original call bytes | `ff f7 5b fd` |
| hook address | `0x08010E00` |
| replacement call bytes | `0e f0 89 fa` |
| original `sys_led_show()` | `0x080023A4` |
| original per-LED RGB function | `0x08007E38` |
| original 32-bit timer | `0x0800B2E8` |
| wireless `dev_info` | `0x20000C80` |
| hook binary size | 332 bytes |

The builder validates the official SHA-256, DFU suffix, call site, and critical function signatures. The verifier proves that only the four-byte call site and appended hook differ from the official payload.

### Build

```bash
brew install arm-none-eabi-gcc@8 arm-none-eabi-binutils dfu-util

./firmware/air60-v2/build.sh \
  /path/to/QMK_firmware_nuphy_air60_v2_ansi_v2.1.5.bin
```

Official input SHA-256:

```text
cd0425f548a01416d1c3c25208ff74867fffd20165520c7c2eaa56000ff347bf
```

Release output SHA-256 with GCC 8.5.0:

```text
c573c7939a53994b50f29313744f27f9af30b90cd064f13fc019f87710b89ac0
```

Run tests only:

```bash
./firmware/air60-v2/test.sh
```

### Flash

Use [QMK Toolbox](https://github.com/qmk/qmk_toolbox/releases), keep NuPhy's official recovery image nearby, and follow [NuPhy's update instructions](https://nuphy.com/pages/update-instructions). Advanced users can flash a confirmed STM32 DFU device with:

```bash
dfu-util -l
dfu-util -a 0 -s 0x08000000:leave \
  -D NuphyBar-Air60-V2-stable-v7.bin
```

The exact model and DFU device must be confirmed by a human before the `-D` command.

### Limits

- Agent lighting temporarily replaces the right-side battery indication.
- Waiting and error share `0x04`; the safe two-bit channel cannot encode another distinct state.
- Fixed official addresses are valid only for the hash- and signature-checked v2.1.5 baseline.

Firmware code in this directory is licensed under GPL-2.0-or-later.
