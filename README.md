# ARM64 裸机汇编学习环境

用 QEMU + GDB 单步调试 ARM64 汇编指令，当前实验：**MMU 使能前后对比**。

## 文件说明

| 文件 | 作用 |
|------|------|
| `demo.S` | ARM64 汇编源码 —— MMU 使能前后对比实验 |
| `linker.lds` | 链接脚本，代码段放 0x40080000 |
| `run_gdb` | GDB 批处理脚本，自动设断点、逐条执行并显示寄存器 |
| `gdb_gef` | GDB + gef 可视化调试启动脚本 |
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

GDB 中常用命令：

| 命令 | 作用 | 示例 |
|------|------|------|
| `break _start` | 在入口设断点 | — |
| `break mmu_enabled` | 在 MMU 使能后设断点 | — |
| `continue` | 继续执行到断点 | — |
| `si` | 单步执行 1 条指令 | — |
| `p/x $x0` | 打印寄存器（十六进制） | `p/x $x4` |
| `display /x $x0` | 每步自动显示寄存器 | `display /x $x4` |
| `display /i $pc` | 每步显示当前指令 | — |
| `info registers` | 查看所有通用寄存器 | — |
| `x/gx <addr>` | 查看 8 字节内存 | `x/gx 0x40090000` |
| `x/4gx <addr>` | 查看连续 4x8 字节 | `x/4gx 0x400C0000` |

### 方式三：gef 可视化调试（推荐单步调试用）

[gef](https://github.com/hugsy/gef) 提供类 IDE 的可视化界面，每次单步自动刷新**寄存器 + 汇编 + 内存**。

```bash
# 终端1: 启动 QEMU
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S

# 终端2: 启动带 gef 的 GDB
./gdb_gef
```

进入后 gef 自动显示三栏布局：

```
+ registers ---------------------------------------------------+
| $x0  0x0000000000000000    $x10  0x0000000000000000           |
| $x1  0x0000000000000000    $x11  0x0000000000000000           |
| ...                                                           |
+ code ---------------------------------------------------------+
| -> 0x40080000 <_start>      ldr  x0, [pc, #192]              |
|    0x40080004 <_start+4>    ldr  x1, [pc, #192]              |
+ stack --------------------------------------------------------+
| (裸机无栈，此栏为空，可以关掉)                                   |
+---------------------------------------------------------------+
(gdb)
```

**gef 常用配置：**

```gdb
# 关掉无用的 stack 区域，加上 memory 区域（推荐）
gef config context.layout "regs code memory"

# 设置要监控的内存地址
gef config memory.page 0x40090000

# 设断点并跑到目标位置
break mmu_enabled
continue

# 单步执行，gef 自动刷新所有区域
si
si
```

每次 `si` 后 gef 自动刷新寄存器、代码和内存区域，不需要手动敲 `p/x` 或 `x/gx`。

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
