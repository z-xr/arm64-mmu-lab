# ARM64 裸机汇编学习环境

用 QEMU + GDB 单步调试 ARM64 汇编指令，当前实验：**MMU 使能前后对比**。

## 快速开始（只需三步）

### 第一步：一次性环境配置

```bash
# 允许 GDB 自动加载项目目录下的 .gdbinit（否则每次都会报 safe-path 警告）
echo "set auto-load safe-path /" >> ~/.gdbinit
```

### 第二步：编译（修改 demo.S 后需要重新编译）

```bash
aarch64-linux-gnu-as -g -o demo.o demo.S
aarch64-linux-gnu-ld -T linker.lds -o demo.elf demo.o
```

### 第三步：启动调试

需要**两个终端**，分别运行：

**终端 1 — 启动 QEMU（模拟 ARM64 CPU）：**

```bash
cd /home/zhaoxr/share123/qemu_busybox_linux/arm64
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S
```

> 执行后 QEMU 会**卡住不动**，这是正常的——`-S` 参数让 CPU 暂停，等待 GDB 连接。

**终端 2 — 启动 GDB（TUI 可视化模式）：**

```bash
cd /home/zhaoxr/share123/qemu_busybox_linux/arm64
aarch64-linux-gnu-gdb -q demo.elf -tui
```

> `.gdbinit` 会自动完成：连接 QEMU → 在 `_start` 设断点 → 配置寄存器 display → 停在第一条指令。

**进入后直接输入 `si` 开始单步调试**，每次 `si` 寄存器窗口自动刷新。

---

## 文件说明

| 文件 | 作用 |
|------|------|
| `demo.S` | ARM64 汇编源码 —— MMU 使能前后对比实验 |
| `linker.lds` | 链接脚本，代码段放 0x40080000 |
| `run_gdb` | GDB 批处理脚本，自动设断点、逐条执行并显示寄存器 |
| `.gdbinit` | GDB 启动时自动执行的配置（断点、display 等） |
| `gdb_cmds` | GDB 交互式命令参考 |
| `cmd.txt` | QEMU 和 GDB 启动命令速查 |

## 编译和链接

```bash
# 汇编（-g 加上调试信息）
aarch64-linux-gnu-as -g -o demo.o demo.S

# 链接
aarch64-linux-gnu-ld -T linker.lds -o demo.elf demo.o

# 查看反汇编
aarch64-linux-gnu-objdump -d demo.elf
```

## 运行 QEMU

```bash
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S
```

参数说明：
- `-M virt` — virt 虚拟平台
- `-cpu cortex-a53` — Cortex-A53 处理器
- `-m 256` — 256MB 内存
- `-nographic` — 无图形窗口
- `-kernel demo.elf` — 加载 ELF 作为内核镜像
- `-s` — 开启 GDB stub，监听 `:1234`
- `-S` — 启动后暂停，等待 GDB 连接

## 连接 GDB 调试

需要**两个终端**配合。

### 方式一：批处理脚本（一键看结果）

```bash
# 终端1
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S

# 终端2
aarch64-linux-gnu-gdb -q -batch -x run_gdb demo.elf
```

### 方式二：交互式调试

```bash
# 终端1: QEMU
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S

# 终端2: GDB
aarch64-linux-gnu-gdb -q demo.elf -ex "target remote :1234"
```

GDB 三大需求对应三个命令：

#### 需求 1：当前执行到哪条指令、哪个文件哪一行

```gdb
# 每步自动显示（设置一次，之后每次 si 自动打印）
display /i $pc
```

输出示例：
```
=> 0x40080004 <_start+4>:  ldr  x1, 0x400800d0
```
`=>` 指的是**下一条要执行的指令**，`<_start+4>` 表示相对 `_start` 偏移 4 字节。

#### 需求 2：当前寄存器值

```gdb
# 每步自动显示关键寄存器（设置一次，之后每次 si 都刷新）
display /x $x0
display /x $x1
display /x $x4
display /x $x5
display /x $x8

# 手动查看全部寄存器
info registers
```

#### 需求 3：查看内存

```gdb
# 看 0x40090000 处的 8 字节
x/gx 0x40090000

# 看连续 4 个 8 字节（实验结束后结果存在 0x400C0000）
x/4gx 0x400C0000

# 每步自动显示某块内存
display/4gx 0x400C0000
```

`x/gx` 格式：`g` = giant（8 字节），`x` = 十六进制。换成 `x/wx` 就是 4 字节。

#### 完整实操示例

```gdb
# ---- 1. 跳到程序入口 ----
break _start
continue

# ---- 2. 配好自动显示（设置一次，之后不用再敲）----
display /i $pc
display /x $x0
display /x $x1
display /x $x4
display /x $x5

# ---- 3. 开始单步，每次 si 后自动打印上面所有信息 ----
si          # 执行 ldr x0, =0x40090000 → x0 变成 0x40090000
si          # 执行 ldr x1, =0xDEADBEEF → x1 变成 0xdeadbeef
si          # 执行 str x1, [x0]       → 内存写入

# ---- 4. 手动检查内存写入结果 ----
x/gx 0x40090000
# → 0x40090000: 0x00000000deadbeef

# ---- 5. 不想一步步走了，跳到后面 ----
break mmu_enabled
continue        # 直接跑到 MMU 使能之后

# ---- 6. 继续单步看 MMU 翻译效果 ----
si
si

# ---- 7. 跳到程序末尾看最终结果 ----
break *0x4008012c
continue
x/4gx 0x400C0000
```

#### 常用命令速查

| 命令 | 作用 |
|------|------|
| `break _start` | 在入口设断点 |
| `break mmu_enabled` | 在 MMU 使能后设断点 |
| `continue` | 继续执行到下一断点 |
| `si` | 单步执行 1 条指令 |
| `display /i $pc` | **每步显示当前指令**（需求 1） |
| `display /x $x0` | **每步显示 x0 寄存器**（需求 2） |
| `info registers` | 查看全部寄存器 |
| `x/gx <addr>` | **查看 8 字节内存**（需求 3） |
| `x/4gx <addr>` | 查看连续 4×8 字节 |

`display` 只需要设置一次，之后每次 `si` 后 GDB 自动打印，不需要再手敲。

### 方式三：GDB 自带 TUI 可视化调试

GDB 自带 **TUI 模式**（`-tui`），配合 `display` 命令可以实现类似 IDE 的可视化效果，每次单步自动刷新寄存器，不需要任何外部插件。

**启动：**

```bash
# 终端1: 启动 QEMU
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S

# 终端2: TUI 模式启动 GDB（会自动读取 .gdbinit 连接 QEMU、设断点、配 display）
aarch64-linux-gnu-gdb -q demo.elf -tui
```

注意：如果 GDB 报 "auto-load safe-path" 警告，先执行：
```bash
echo "set auto-load safe-path /" >> ~/.gdbinit
```

**进入后的界面：**

```
┌──寄存器窗口 (layout regs)─────────────────────────────────────────────┐
│ x0   0x40090000    x16  0x0                                           │
│ x1   0xdeadbeef    x17  0x0                                           │
│ x2   0x0           x18  0x0                                           │
│ x3   0x0           ...                                                │
│ ...                                                                   │
├──命令窗口─────────────────────────────────────────────────────────────┤
│ (gdb)                                                                 │
└───────────────────────────────────────────────────────────────────────┘
```

每次 `si` 后：
- 寄存器窗口**自动刷新**，变化的寄存器**高亮**
- `display` 设定的内容自动打印在命令窗口

**常用 TUI 快捷键：**

| 快捷键 | 作用 |
|--------|------|
| `Ctrl-x a` | 切换进入/退出 TUI 模式 |
| `Ctrl-x 1` | 只显示一个窗口 |
| `Ctrl-x 2` | 显示两个窗口 |
| `layout regs` | 切换到寄存器 + 命令窗口 |
| `layout asm` | 切换到汇编 + 命令窗口 |
| `layout split` | 源码 + 汇编 + 命令窗口 |
| `focus cmd` | 焦点切到命令窗口（可以输入命令） |
| `focus regs` | 焦点切到寄存器窗口（可以上下滚动） |
| `refresh` | 屏幕花掉时刷新 |

**调试流程：**

```gdb
# .gdbinit 已经帮你连好 QEMU、设好了 display
# 进入后直接开始单步：

si                         # 执行 1 条指令，自动看到寄存器变化

# 需要看内存时
x/gx 0x40090000            # 查看 8 字节内存

# 需要连续跑时
break mmu_enabled          # 在 MMU 使能后设断点
continue                   # 跑到断点
```

**TUI 模式下内存怎么观察？**

TUI 没有自带内存窗口，推荐两种方式：

```gdb
# 1. display 自动显示内存（和寄存器一样，每次 si 自动刷新）
display/4gx 0x40090000

# 2. 手动查看
x/4gx 0x40090000           # 4 个 8 字节
x/8wx 0x40090000           # 8 个 4 字节
```

**最推荐的 TUI 布局组合：**

```gdb
# 先 layout regs 看寄存器+源码
layout regs

# 加上 display 自动显示当前指令和关键内存
display /i $pc
display/4gx 0x40090000
```

这样 `si` 一次就能看到：寄存器变化（TUI 上部） + 当前指令 + 内存值（display 输出）。

---

## 当前实验：MMU 使能前后对比

### 实验流程

1. **开 MMU 前**：往物理地址 0x40090000/0x400A0000 写入 marker 值
2. **建立页表**：3 级页表 L0→L1→L2（2MB block）
   - L1[1] → L2_A：identity mapping（VA 0x40000000 → PA 0x40000000）
   - L1[2] → L2_B：non-identity mapping（VA 0x80000000 → PA 0x40000000）
3. **配置 MMU 寄存器**：MAIR_EL1, TCR_EL1, TTBR0_EL1
4. **使能 MMU**：置 SCTLR_EL1.M 位
5. **验证 MMU 翻译**：
   - 用 identity VA (0x40090000) 读取 → 0xDEADBEEF
   - 用 **不同的** VA (0x80090000) 通过页表读到**同一** PA → 也得到 0xDEADBEEF
6. **关 MMU**：方便 GDB 查看结果

### 页表结构

```
TCR_EL1.T0SZ = 16 (48-bit VA, 从 L0 开始)

L0[0]           → L1 表
L1[1]           → L2_A 表 (identity)
L1[2]           → L2_B 表 (non-identity)
L2_A[0]         → 2MB block @ PA 0x40000000 (VA 0x40000000-0x401FFFFF)
L2_B[0]         → 2MB block @ PA 0x40000000 (VA 0x80000000-0x801FFFFF)
```

### 关键结果

```
x4 (identity VA 0x40090000)  = 0xDEADBEEF
x5 (non-identity 0x80090000) = 0xDEADBEEF  ← 不同 VA，同一 PA!
x6 (non-identity 0x800A0000) = 0xCAFEBABE
x8 (cross-VA write verify)    = 0xFEEDFACE
```

**结论**：MMU 使能后，所有地址都是虚拟地址，通过页表翻译为物理地址访问内存。
