#!/usr/bin/env python3
"""
gpio_control.py — 通过 USB 远程控制 Raspberry Pi Debug Probe 的 GPIO 引脚
================================================================================

功能概述
--------
通过 debugprobe 的 USB vendor control transfer 控制 RP2040/RP2350 的全部 GPIO
引脚 (0-47)。输出模式自动配置为 12mA 强驱动 + fast slew，确保电平可靠。

硬件要求
--------
  - Raspberry Pi Debug Probe (或基于 RP2040 的兼容 debugprobe)
  - PC 通过 USB 连接 debugprobe
  - debugprobe 已烧写支持远程 GPIO 控制的自定义固件 (vendor request 0x02)

引脚接线
--------
  以 GPIO1 为例:
    debugprobe Pin 2 (GP1)  -->  目标信号
    debugprobe Pin 3  (GND)  -->  目标 GND

  参考: Raspberry Pi Pico pinout (https://pico.pinout.xyz/)


环境配置
--------

  Windows
  ~~~~~~~
  1. pip install pyusb libusb-package

  2. 用 Zadig 替换驱动为 WinUSB
     a. 下载 https://zadig.akeo.ie/
     b. Options → List All Devices
     c. 选择 "Debug Probe" / "CMSIS-DAP v2" (VID=2E8A PID=000C)
     d. 选择 WinUSB → Replace Driver

  Linux
  ~~~~~~~
  1. pip install pyusb
  2. sudo apt install libusb-1.0-0   # Debian/Ubuntu
  3. 可能需要 root 权限或 udev 规则


命令参考
--------

  GPIO 输出 (自动配强驱动: 12mA + fast slew + 禁用上下拉)
    high      输出高电平
    low       输出低电平
    pulse     低脉冲 100ms (拉低 100ms 后释放为高)
    square    输出方波, 默认 1Hz (Ctrl+C 停止, 停止时自动拉低)
    square N  输出方波, 自定义频率 N Hz (如 0.5 即 2 秒一轮)
    op        设为输出模式 (不改变电平)

  GPIO 输入
    ip        设为输入模式
    pu        启用内部上拉 (~50k)
    pd        启用内部下拉 (~50k)
    pn        禁用上下拉 (高阻/浮空)

  状态查询
    get       读取 GPIO 完整状态 (电平/功能/方向/上下拉/驱动强度/压摆率)
    list      列出全部 GPIO (0-47) 一览表


使用示例
--------
  python gpio_control.py 1 high       # GPIO1 输出高电平
  python gpio_control.py 1 low        # GPIO1 输出低电平
  python gpio_control.py 1 square     # GPIO1 输出 1Hz 方波
  python gpio_control.py 1 square 10  # GPIO1 输出 10Hz 方波
  python gpio_control.py 1 pulse      # GPIO1 输出 100ms 低脉冲
  python gpio_control.py 1 get        # 读取 GPIO1 完整状态
  python gpio_control.py 1 pu         # GPIO1 输入模式 + 上拉
  python gpio_control.py list         # 列出所有 GPIO 状态


输出方波示例 (典型场景)
-------------------------
  # 1Hz 方波 — 万用表测频率 / 示波器观察
  python gpio_control.py 1 square

  # 慢速方波 — 万用表观察电压跳变
  python gpio_control.py 1 square 0.5

  # 10kHz 方波 — 注意: USB 延迟会限制精度
  python gpio_control.py 1 square 10000


故障排查
--------
  "找不到 USB 后端库"
    → Windows: pip install libusb-package
    → Linux:   sudo apt install libusb-1.0-0

  "未找到 debugprobe 设备"
    → 检查 USB 连接, 确认 Zadig 已替换为 WinUSB 驱动

  "Pipe error" / 固件不支持
    → 需要烧写支持远程 GPIO 的自定义固件到 debugprobe

  "Access denied" (设备忙)
    → 有其他进程(如另一个 gpio_control.py 实例)正占用设备, 终止后重试

  低电平偏高 (如 ~2.4V 而不是 ~0V)
    → 旧版脚本未配置 pad 驱动强度, 更新脚本后重试
    → 如果更新后仍偏高, 检查外部电路是否有强上拉
"""

import sys
import time
import struct

IS_WINDOWS = sys.platform == 'win32'
IS_LINUX = sys.platform.startswith('linux')

try:
    import usb.core
    import usb.util
except ImportError as e:
    sys.exit(
        "错误: 缺少 pyusb 依赖。\n\n"
        "请安装 pyusb:\n"
        "  pip install pyusb\n\n"
        "Linux 还需要 libusb-1.0:\n"
        "  sudo apt install libusb-1.0-0     # Debian/Ubuntu\n"
        "  sudo pacman -S libusb              # Arch\n\n"
        "Windows: 除了 pyusb 还需要用 Zadig 安装 WinUSB 驱动。\n"
        f"原始错误: {e}"
    )

# On Windows, try to use libusb-package for the backend DLL
_usb_backend = None
if IS_WINDOWS:
    try:
        from libusb_package import get_libusb1_backend
        _usb_backend = get_libusb1_backend()
    except ImportError:
        pass  # Will fall back to system libusb or fail with clear error

DEBUGPROBE_VID = 0x2E8A
DEBUGPROBE_PID = 0x000C

# bmRequestType: direction=Host-to-Device/Device-to-Host, type=Vendor, recipient=Device
BMREQUEST_GPIO_SET = 0x40  # Host to Device
BMREQUEST_GPIO_GET = 0xC0  # Device to Host

# bRequest: vendor control request number for remote GPIO
CTRL_REMOTE_GPIO_REQ = 0x02

# GPIO get functions (from include/remote_gpio.h)
GPIO_GET_FUNCTION = 0
GPIO_GET_PULLS = 1
GPIO_GET_INPUT_ENABLED = 2
GPIO_GET_INPUT_HYST_ENABLED = 3
GPIO_GET_SLEW_RATE = 4
GPIO_GET_DRIVE_STRENGTH = 5
GPIO_GET = 6
GPIO_GET_ALL = 7
GPIO_GET_OUT_LEVEL = 8
GPIO_GET_DIR = 9

# GPIO set functions (from include/remote_gpio.h)
GPIO_SET_FUNCTION = 0
GPIO_SET_PULLS = 1
GPIO_SET_INPUT_ENABLED = 2
GPIO_SET_INPUT_HYST_ENABLED = 3
GPIO_SET_SLEW_RATE = 4
GPIO_SET_DRIVE_STRENGTH = 5
GPIO_PUT = 6
GPIO_PUT_ALL = 7
GPIO_SET_MASK = 8
GPIO_CLR_MASK = 9
GPIO_XOR_MASK = 10
GPIO_SET_DIR_OUT_MASKED = 11
GPIO_SET_DIR_IN_MASKED = 12
GPIO_SET_DIR_ALL_BITS = 13
GPIO_SET_DIR = 14
GPIO_INIT = 15
GPIO_INIT_MASK = 16
GPIO_DEINIT = 17

# RP2040/2350 default GPIO function (SIO = software I/O)
GPIO_FUNC_SIO = 5

PULL_NAMES = ["NONE", "UP", "DOWN", "KEEPER"]
DIR_NAMES = ["INPUT", "OUTPUT"]

# Maximum GPIO on RP2040/RP2350 (GPIO0-GPIO27 for RP2040, up to GPIO47 for RP2350)
NR_GPIOS = 48


# ============================================================
# Device discovery & setup
# ============================================================

def find_device():
    """查找 debugprobe USB 设备 (跨平台)。"""
    try:
        dev = usb.core.find(idVendor=DEBUGPROBE_VID, idProduct=DEBUGPROBE_PID,
                            backend=_usb_backend)
    except usb.core.NoBackendError:
        if IS_WINDOWS:
            sys.exit(
                "错误: 找不到 USB 后端库 (libusb)。\n\n"
                "Windows 下请用 Zadig 安装 WinUSB 驱动:\n"
                "  1. 下载 Zadig: https://zadig.akeo.ie/\n"
                "  2. 插入 debugprobe\n"
                "  3. Options → List All Devices\n"
                "  4. 选择 Debug Probe (VID=2E8A, PID=000C)\n"
                "  5. 选择 WinUSB 驱动, 点击 Replace Driver\n"
                "  6. 重新运行本脚本\n\n"
                "如果问题仍然存在, 请尝试将 libusb-1.0.dll\n"
                "放到本脚本同目录下。"
            )
        else:
            sys.exit(
                "错误: 找不到 USB 后端库 (libusb)。\n\n"
                "Linux:\n"
                "  sudo apt install libusb-1.0-0\n\n"
                "macOS:\n"
                "  brew install libusb"
            )

    if dev is None:
        if IS_WINDOWS:
            sys.exit(
                "错误: 未找到 debugprobe 设备 (VID:0x2E8A PID:0x000C)。\n\n"
                "请检查:\n"
                "  1. USB 连接是否正常\n"
                "  2. 是否已用 Zadig 安装 WinUSB 驱动\n"
                "     下载: https://zadig.akeo.ie/\n"
                "     选择 Debug Probe 设备 → WinUSB → Replace Driver\n"
            )
        else:
            sys.exit(
                "错误: 未找到 debugprobe 设备 (VID:0x2E8A PID:0x000C)。\n"
                "请检查 USB 连接。\n"
                "Linux: 请确认 libusb-1.0 已安装且有设备权限。"
            )
    return dev


def prepare_device(dev):
    """跨平台设备准备: 断开内核驱动, 设置配置。

    在 Linux 上断开内核驱动 (hidraw, usbhid) 以允许用户态访问。
    在 Windows 上通常不需要此操作, 但如果驱动是 WinUSB 则无影响。
    """
    # Step 1: detach kernel driver
    # On Linux, kernel drivers like usbhid may claim the interface,
    # preventing user-space access. We detach them here.
    # On Windows, is_kernel_driver_active typically returns False
    # or the method may not be implemented (AttributeError).
    try:
        for cfg in dev:
            for intf in cfg:
                try:
                    if dev.is_kernel_driver_active(intf.bInterfaceNumber):
                        dev.detach_kernel_driver(intf.bInterfaceNumber)
                except (usb.core.USBError, NotImplementedError):
                    pass
    except (usb.core.USBError, AttributeError):
        pass

    # Step 2: activate configuration
    # On Windows, the device may already be configured by the driver.
    # On Linux, set_configuration() is usually required.
    try:
        dev.set_configuration()
    except usb.core.USBError:
        pass  # Already configured or not needed


def verify_remote_gpio_support(dev):
    """验证固件是否支持远程 GPIO 命令。"""
    try:
        dev.ctrl_transfer(BMREQUEST_GPIO_GET, CTRL_REMOTE_GPIO_REQ,
                          GPIO_GET_FUNCTION, 0, 4, timeout=500)
    except usb.core.USBError:
        sys.exit(
            "错误: probe 固件不支持 REMOTE_GPIO 功能。\n"
            "请更新 debugprobe 固件到支持远程 GPIO 的版本。"
        )


# ============================================================
# Low-level GPIO control transfer
# ============================================================

def gpio_ctrl_transfer(dev, is_read, gpio_fn, gpio_num, data=0):
    """发送 GPIO vendor control transfer。

    Uses USB control endpoint 0 with bmRequestType=Vendor+Device.
    All GPIO values are 4-byte uint32 little-endian.

    Args:
        dev: USB device handle
        is_read: True=GET (Device→Host), False=SET (Host→Device)
        gpio_fn: GPIO function enum (e.g. GPIO_GET, GPIO_PUT, GPIO_SET_DIR)
        gpio_num: GPIO pin number (0-47)
        data: for SET operations, the uint32 value to send

    Returns:
        uint32 data for GET, None for SET
    """
    bm_request = BMREQUEST_GPIO_GET if is_read else BMREQUEST_GPIO_SET

    if is_read:
        result = dev.ctrl_transfer(bm_request, CTRL_REMOTE_GPIO_REQ,
                                   gpio_fn, gpio_num, 4, timeout=3000)
        return struct.unpack('<I', result)[0]
    else:
        data_bytes = struct.pack('<I', data)
        dev.ctrl_transfer(bm_request, CTRL_REMOTE_GPIO_REQ,
                          gpio_fn, gpio_num, data_bytes, timeout=3000)
        return None


def gpio_get(dev, gpio_num, gpio_fn):
    """读取 GPIO 属性 (包装 gpio_ctrl_transfer)。"""
    return gpio_ctrl_transfer(dev, True, gpio_fn, gpio_num)


def gpio_set(dev, gpio_num, gpio_fn, data):
    """设置 GPIO 属性 (包装 gpio_ctrl_transfer)。"""
    return gpio_ctrl_transfer(dev, False, gpio_fn, gpio_num, data)


def ensure_gpio_init(dev, gpio_num):
    """如果 GPIO 的 function 不是 SIO (5), 则先执行 gpio_init()。

    这是与 probe_gpio_api.c 保持一致的行为:
    从其他外设功能切换回 GPIO 时需要先初始化。
    """
    func = gpio_get(dev, gpio_num, GPIO_GET_FUNCTION)
    if func != GPIO_FUNC_SIO:
        gpio_set(dev, gpio_num, GPIO_INIT, 0)
        print(f"GPIO{gpio_num}: 已初始化 (原功能: {func})")


def configure_gpio_od_assert(dev, gpio_num):
    """配置 GPIO 为开漏输出 + 拉低 (assert)。

    关键技巧: 先写输出寄存器为 0, 再切方向为输出。
    这样 GPIO 在方向切换瞬间就是低电平, 不会有毛刺。
    适用于驱动 nRESET 等有强外部上拉的信号。
    """
    ensure_gpio_init(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_SET_PULLS, 0)              # no pull
    gpio_set(dev, gpio_num, GPIO_SET_DRIVE_STRENGTH, 3)     # 12mA (RP2040 max)
    gpio_set(dev, gpio_num, GPIO_SET_SLEW_RATE, 1)          # fast slew
    gpio_set(dev, gpio_num, GPIO_SET_INPUT_ENABLED, 0)      # disable input
    gpio_set(dev, gpio_num, GPIO_PUT, 0)                    # pre-set output=0 (pin still input)
    gpio_set(dev, gpio_num, GPIO_SET_DIR, 1)                # NOW switch to output → drives low


def configure_gpio_od_release(dev, gpio_num):
    """释放开漏信号: 切为输入模式 (高阻), 由外部上拉回到高电平。"""
    gpio_set(dev, gpio_num, GPIO_SET_DIR, 0)                # input = high-Z
    gpio_set(dev, gpio_num, GPIO_SET_PULLS, 0)              # no internal pull


def _reset_assert(dev, pins):
    """将所有 reset 引脚设为输出低 (开漏 assert)。"""
    for p in pins:
        configure_gpio_od_assert(dev, p)


def _reset_release(dev, pins):
    """释放所有 reset 引脚 (高阻)。"""
    for p in pins:
        configure_gpio_od_release(dev, p)


def cmd_reset(dev, gpio_num, duration_ms=100, aux_pins=None):
    """推挽复位: 拉低 → 等待 → 拉高。

    与 low + sleep + high 等效，使用 12mA 强驱动推挽输出。
    支持多 GPIO 并联以增强驱动能力:
      python gpio_control.py 1 reset       # 单 GPIO1, 100ms
      python gpio_control.py 1 reset 200   # GPIO1, 200ms
      python gpio_control.py 1 reset 100 2 # GPIO1+GPIO2 并联
    """
    pins = [gpio_num]
    if aux_pins:
        pins.extend(aux_pins)
    pins = list(dict.fromkeys(pins))

    pin_list = ",".join(f"GPIO{p}" for p in pins)
    total_ma = len(pins) * 12
    print(f"{pin_list}: RESET 拉低 ({duration_ms}ms, {total_ma}mA 推挽)...")
    for p in pins:
        configure_gpio_output_strong(dev, p)
        gpio_set(dev, p, GPIO_PUT, 0)
    time.sleep(duration_ms / 1000.0)
    for p in pins:
        gpio_set(dev, p, GPIO_PUT, 1)
    print(f"{pin_list}: RESET 释放 (高电平)")


def configure_gpio_output_strong(dev, gpio_num):
    """配置 GPIO pad 为强驱动推挽输出 (12mA, fast slew, no pull)。

    用于驱动普通负载: 高电平推 3.3V, 低电平拉 GND。
    """
    ensure_gpio_init(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_SET_DIR, 1)                # output mode
    gpio_set(dev, gpio_num, GPIO_SET_DRIVE_STRENGTH, 3)     # 12mA (RP2040 max)
    gpio_set(dev, gpio_num, GPIO_SET_SLEW_RATE, 1)          # fast slew
    gpio_set(dev, gpio_num, GPIO_SET_PULLS, 0)              # no pull
    gpio_set(dev, gpio_num, GPIO_SET_INPUT_ENABLED, 0)      # disable input


# ============================================================
# High-level commands (user-facing)
# ============================================================

def cmd_set_high(dev, gpio_num):
    """设置 GPIO 输出高电平。"""
    configure_gpio_output_strong(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_PUT, 1)       # drive high
    print(f"GPIO{gpio_num}: 输出高电平")


def cmd_set_low(dev, gpio_num):
    """设置 GPIO 输出低电平。"""
    configure_gpio_output_strong(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_PUT, 0)       # drive low
    print(f"GPIO{gpio_num}: 输出低电平")


def gpio_get_safe(dev, gpio_num, gpio_fn, default="?"):
    """安全读取 GPIO 属性, 如果固件不支持则返回 default。"""
    try:
        return gpio_get(dev, gpio_num, gpio_fn)
    except usb.core.USBError:
        return default


def cmd_get(dev, gpio_num):
    """读取并显示 GPIO 完整状态 (电平, 功能, 方向, 上下拉, 驱动强度, 压摆率)。"""
    level = gpio_get_safe(dev, gpio_num, GPIO_GET)
    func = gpio_get_safe(dev, gpio_num, GPIO_GET_FUNCTION)
    ddir = gpio_get_safe(dev, gpio_num, GPIO_GET_DIR)
    pull = gpio_get_safe(dev, gpio_num, GPIO_GET_PULLS)
    drive = gpio_get_safe(dev, gpio_num, GPIO_GET_DRIVE_STRENGTH)
    slew = gpio_get_safe(dev, gpio_num, GPIO_GET_SLEW_RATE)
    in_en = gpio_get_safe(dev, gpio_num, GPIO_GET_INPUT_ENABLED)

    dir_str = DIR_NAMES[ddir] if isinstance(ddir, int) and ddir <= 1 else f"UNK({ddir})"
    pull_str = PULL_NAMES[pull] if isinstance(pull, int) and pull <= 3 else f"UNK({pull})"
    if isinstance(drive, int) and drive <= 3:
        drive_ma = [2, 4, 8, 12][drive]
        drive_str = f"{drive} ({drive_ma}mA)"
    else:
        drive_str = str(drive)

    print(f"GPIO{gpio_num}: level={level} function={func} "
          f"dir={dir_str} pull={pull_str}")
    print(f"         drive={drive_str} slew={slew} input_en={in_en}")


def cmd_pulse(dev, gpio_num):
    """输出一个低脉冲: 拉低 → 等待 100ms → 释放为高。"""
    configure_gpio_output_strong(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_PUT, 0)
    print(f"GPIO{gpio_num}: 拉低...")
    time.sleep(0.1)
    gpio_set(dev, gpio_num, GPIO_PUT, 1)
    print(f"GPIO{gpio_num}: 释放 (高电平)")


def cmd_square(dev, gpio_num, freq=1.0):
    """输出方波: 按指定频率 (Hz) 切换 GPIO 高低电平。Ctrl+C 停止。"""
    configure_gpio_output_strong(dev, gpio_num)

    half_period = 1.0 / (2.0 * freq)
    state = 1  # 从高电平开始
    count = 0

    print(f"GPIO{gpio_num}: 输出 {freq}Hz 方波 (半周期={half_period * 1000:.0f}ms)")
    print("按 Ctrl+C 停止...")

    try:
        while True:
            gpio_set(dev, gpio_num, GPIO_PUT, state)
            state ^= 1  # 翻转
            count += 1
            time.sleep(half_period)
    except KeyboardInterrupt:
        # 退出时拉低 GPIO
        gpio_set(dev, gpio_num, GPIO_PUT, 0)
        print(f"\nGPIO{gpio_num}: 方波已停止 (共输出 {count} 个边沿)")


def cmd_set_output(dev, gpio_num):
    """设为输出模式 (不改变电平)。"""
    configure_gpio_output_strong(dev, gpio_num)
    print(f"GPIO{gpio_num}: 设为输出模式 (12mA, fast slew)")


def cmd_set_input(dev, gpio_num):
    """设为输入模式。"""
    ensure_gpio_init(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_SET_DIR, 0)
    print(f"GPIO{gpio_num}: 设为输入模式")


def cmd_pull_up(dev, gpio_num):
    """启用内部上拉电阻 (~50kΩ)。"""
    ensure_gpio_init(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_SET_PULLS, 1)  # 0x1 = up
    print(f"GPIO{gpio_num}: 启用上拉")


def cmd_pull_down(dev, gpio_num):
    """启用内部下拉电阻 (~50kΩ)。"""
    ensure_gpio_init(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_SET_PULLS, 2)  # 0x2 = down
    print(f"GPIO{gpio_num}: 启用下拉")


def cmd_pull_none(dev, gpio_num):
    """禁用上下拉 (高阻态 / floating)。"""
    ensure_gpio_init(dev, gpio_num)
    gpio_set(dev, gpio_num, GPIO_SET_PULLS, 0)
    print(f"GPIO{gpio_num}: 禁用上下拉")


def cmd_list_all(dev):
    """列出所有 GPIO 的状态 (快速一览)。"""
    print(f"{'GPIO':>4}  {'level':>5}  {'func':>5}  {'dir':>6}  {'pull':>6}")
    print("-" * 38)
    for gpio_num in range(NR_GPIOS):
        try:
            level = gpio_get(dev, gpio_num, GPIO_GET)
            func = gpio_get(dev, gpio_num, GPIO_GET_FUNCTION)
            ddir = gpio_get(dev, gpio_num, GPIO_GET_DIR)
            pull = gpio_get(dev, gpio_num, GPIO_GET_PULLS)

            dir_str = DIR_NAMES[ddir] if ddir <= 1 else "UNK"
            pull_str = PULL_NAMES[pull] if pull <= 3 else "UNK"
            print(f"{gpio_num:>4}  {level:>5}  {func:>5}  {dir_str:>6}  {pull_str:>6}")
        except usb.core.USBError:
            print(f"{gpio_num:>4}  {'--':>5}  {'--':>5}  {'--':>6}  {'--':>6}")


# ============================================================
# Command dispatch
# ============================================================

COMMANDS = {
    "high":    (cmd_set_high,    "输出高电平 (推挽)"),
    "low":     (cmd_set_low,     "输出低电平 (推挽)"),
    "get":     (cmd_get,         "读取状态"),
    "pulse":   (cmd_pulse,       "低脉冲 100ms (推挽)"),
    "reset":   (cmd_reset,       "开漏复位脉冲 (默认 100ms, 可选时长)"),
    "op":      (cmd_set_output,  "设为输出"),
    "ip":      (cmd_set_input,   "设为输入"),
    "pu":      (cmd_pull_up,     "上拉"),
    "pd":      (cmd_pull_down,   "下拉"),
    "pn":      (cmd_pull_none,   "悬空"),
    "square":  (cmd_square,      "输出方波 (默认 1Hz, 可选参数)"),
}


def print_usage():
    print(__doc__)
    print("可用命令:")
    for name, (fn, desc) in COMMANDS.items():
        print(f"  {name:<8} {desc}")


def main():
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)

    # "list" command: no GPIO number needed
    if sys.argv[1] == "list":
        dev = find_device()
        prepare_device(dev)
        try:
            cmd_list_all(dev)
        finally:
            usb.util.dispose_resources(dev)
        return

    # All other commands need: <gpio> <command>
    if len(sys.argv) < 3:
        print_usage()
        sys.exit(1)

    try:
        gpio_num = int(sys.argv[1])
    except ValueError:
        sys.exit(f"错误: GPIO 编号必须是数字，收到: {sys.argv[1]}")

    if gpio_num < 0 or gpio_num >= NR_GPIOS:
        sys.exit(f"错误: GPIO 编号超出范围 (0-{NR_GPIOS - 1}): {gpio_num}")

    cmd = sys.argv[2]
    if cmd not in COMMANDS:
        sys.exit(f"错误: 未知命令 '{cmd}'\n"
                 f"可用: {', '.join(COMMANDS.keys())}")

    cmd_fn, _ = COMMANDS[cmd]

    # Parse optional args for "square" and "reset"
    if cmd == "square":
        freq = 1.0
        if len(sys.argv) >= 4:
            try:
                freq = float(sys.argv[3])
            except ValueError:
                sys.exit(f"错误: 频率必须是数字，收到: {sys.argv[3]}")
        if freq <= 0:
            sys.exit(f"错误: 频率必须大于 0: {freq}")
    elif cmd == "reset":
        duration_ms = 100
        aux_pins = []
        # Syntax: <gpio> reset [duration_ms] [aux_gpio1] [aux_gpio2] ...
        if len(sys.argv) >= 4:
            # Try to parse arg as duration first
            try:
                duration_ms = int(sys.argv[3])
                extra_start = 4
            except ValueError:
                # Not a number — might be a GPIO pin (backward compat)
                duration_ms = 100
                extra_start = 3
            # Parse remaining args as auxiliary GPIO pins
            for arg in sys.argv[extra_start:]:
                try:
                    p = int(arg)
                    if p < 0 or p >= NR_GPIOS:
                        sys.exit(f"错误: GPIO 编号超出范围 (0-{NR_GPIOS - 1}): {p}")
                    aux_pins.append(p)
                except ValueError:
                    sys.exit(f"错误: 参数必须是数字 (时长 ms 或 GPIO 编号)，收到: {arg}")
        if duration_ms <= 0:
            sys.exit(f"错误: 脉冲时长必须大于 0: {duration_ms}")

    dev = find_device()
    prepare_device(dev)

    try:
        if cmd == "square":
            cmd_fn(dev, gpio_num, freq)
        elif cmd == "reset":
            cmd_fn(dev, gpio_num, duration_ms, aux_pins)
        else:
            cmd_fn(dev, gpio_num)
    finally:
        usb.util.dispose_resources(dev)


if __name__ == '__main__':
    main()
