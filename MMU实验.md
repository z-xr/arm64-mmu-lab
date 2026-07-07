# ARM64 MMU 实验：使能前后虚拟地址翻译对比

## 实验目的

通过一个最小化的裸机程序，直观观察 ARM64 MMU（内存管理单元）使能前后的差异：

- **开 MMU 前**：所有地址都是物理地址（PA），访存直接操作物理内存
- **开 MMU 后**：所有地址都是虚拟地址（VA），CPU 发出的每个地址都通过页表翻译为物理地址

核心验证：将两个不同的虚拟地址（`0x40090000` 和 `0x80090000`）映射到同一个物理地址（`0x40090000`），证明 MMU 地址翻译机制正常工作。

## 环境

- **交叉编译器**: `aarch64-linux-gnu-as/ld/objcopy/gdb`（Linaro 7.5.0）
- **模拟器**: `qemu-system-aarch64`（QEMU 9.0.0）
- **平台**: `-M virt -cpu cortex-a53`

## 文件说明

| 文件 | 作用 |
|------|------|
| `demo.S` | ARM64 汇编源码，完整的 MMU 使能/关闭 + 内存读写验证 |
| `linker.lds` | 链接脚本，代码段放在 `0x40080000` |
| `run_gdb` | GDB 批处理脚本，一键运行并查看实验结果 |
| `gdb_cmds` | GDB 交互式调试命令参考 |
| `cmd.txt` | QEMU 和 GDB 启动命令速查 |

---

## 一、编译和链接

```bash
# 汇编（-g 加上调试信息）
aarch64-linux-gnu-as -g -o demo.o demo.S

# 链接
aarch64-linux-gnu-ld -T linker.lds -o demo.elf demo.o

# 可选：查看反汇编
aarch64-linux-gnu-objdump -d demo.elf
```

编译产物：`demo.o` → `demo.elf`

---

## 二、运行 QEMU

```bash
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S
```

参数说明：

| 参数 | 含义 |
|------|------|
| `-M virt` | 使用 virt 虚拟平台 |
| `-cpu cortex-a53` | 模拟 Cortex-A53 处理器（ARMv8-A） |
| `-m 256` | 256MB 内存 |
| `-nographic` | 无图形窗口，纯终端输出 |
| `-kernel demo.elf` | 加载 ELF 文件作为内核镜像 |
| `-s` | 开启 GDB stub，监听 TCP 端口 `:1234` |
| `-S` | 启动后立即暂停 CPU，等待 GDB 连接 |

---

## 三、调试方式

### 方式一：一键批处理（推荐）

```bash
aarch64-linux-gnu-gdb -q -batch -x run_gdb demo.elf
```

自动完成：连接 QEMU → 设断点 → 跑完全程 → 打印 `0x400C0000` 处结果。

### 方式二：交互式调试

需要两个终端配合：

**终端 1 — 启动 QEMU：**

```bash
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S
# QEMU 启动后阻塞，等待 GDB 连接
```

**终端 2 — 启动 GDB：**

```bash
aarch64-linux-gnu-gdb -q demo.elf -ex "target remote :1234"
```

进入 GDB 后的常用命令：

```gdb
break _start              # 在程序入口设断点
break page_table_ready    # 在页表建完后设断点
break mmu_enabled         # 在 MMU 使能后设断点
continue                  # 继续执行到下一断点
si                        # 单步执行一条指令（step instruction）
p/x $x4                  # 以十六进制打印 x4 寄存器
p/x $x5                  # 打印 x5 寄存器
display /x $x4            # 每步自动显示 x4
info registers            # 查看所有通用寄存器
x/4gx 0x400C0000         # 查看内存中保存的实验结果
```

---

## 四、程序执行流程

```
阶段1: 开 MMU 前
  ├── 往 PA 0x40090000 写入 0xDEADBEEF
  ├── 往 PA 0x400A0000 写入 0xCAFEBABE
  └── 读回确认 (x7)

阶段2: 建立 3 级页表
  ├── 清零 4 张表 (L0/L1/L2_A/L2_B, 共 16KB)
  ├── L0[0] → L1 表
  ├── L1[1] → L2_A 表 (identity)
  ├── L1[2] → L2_B 表 (non-identity)
  ├── L2_A[0]: VA 0x40000000-0x401FFFFF → PA 0x40000000 (identity)
  └── L2_B[0]: VA 0x80000000-0x801FFFFF → PA 0x40000000 (non-identity)

阶段3: 配置 MMU 寄存器
  ├── MAIR_EL1: Attr0 = 0xFF (Normal memory, Write-Back)
  ├── TCR_EL1: T0SZ=16 (48-bit VA), EPD1=1 (禁用 TTBR1)
  └── TTBR0_EL1 → 指向 L0 表 @ 0x400B0000

阶段4: 使能 MMU
  ├── SCTLR_EL1.M = 1
  └── isb (从此之后所有地址经 MMU 翻译)

阶段5: MMU 使能后验证
  ├── 5a: identity VA 0x40090000 读取 → x4
  ├── 5b: non-identity VA 0x80090000 读取 → x5
  ├── 5c: non-identity VA 0x800A0000 读取 → x6
  ├── 5d: 用 non-identity VA 写, identity VA 读 → x8
  └── 5e: 保存 x4/x5/x6/x8 到 0x400C0000

阶段6: 关闭 MMU
  ├── SCTLR_EL1.M = 0
  └── 死循环
```

---

## 五、页表结构详解

### 5.1 页表在内存中的布局

```
物理地址          大小    内容
────────────────  ─────  ──────────────────────────────
0x40080000         ~200B  程序代码 (.text)
0x40090000           8B  写入的 marker: 0xDEADBEEF
0x400A0000           8B  写入的 marker: 0xCAFEBABE
0x400B0000          4KB  L0 表 (512 项 × 8B, 只用 1 项)
0x400B1000          4KB  L1 表 (512 项 × 8B, 只用 2 项)
0x400B2000          4KB  L2_A 表 — identity 映射
0x400B3000          4KB  L2_B 表 — non-identity 映射
0x400C0000          32B  实验结果 (4 个 8B 值)
```

### 5.2 各级页表存的数据

#### L0 表 (@ PA 0x400B0000)

| 表项 | 内存地址 | 存储的值 | 含义 |
|------|----------|----------|------|
| L0[0] | `0x400B0000` | `0x400B1003` | 指向 L1 表 @ PA `0x400B1000` |
| L0[1..511] | `0x400B0008` ~ | `0` | 无效（清零） |

`0x400B1003` 二进制解析（Table Descriptor）：

```
bit[0]   = 1  有效
bit[1]   = 1  Table descriptor（继续往下查）
bit[47:12] = 0x400B1  下一级表物理地址的高 36 位
          完整 PA = 0x400B1000 (低 12 位固定为 0)
```

#### L1 表 (@ PA 0x400B1000)

| 表项 | 内存地址 | 存储的值 | 含义 |
|------|----------|----------|------|
| L1[1] | `0x400B1008` | `0x400B2003` | VA 0x40xxxxxx → L2_A (identity) |
| L1[2] | `0x400B1010` | `0x400B3003` | VA 0x80xxxxxx → L2_B (non-identity) |
| L1[0,3..511] | 其余 | `0` | 无效 |

L1 index 计算：

```
VA[38:30] 选中 L1 的 512 项之一

0x40000000 = 0100 0000 0000 0000 0000 0000 0000 0000
bit30 = 1 → VA[38:30] = 0b000000001 = 1  → L1[1]

0x80000000 = 1000 0000 0000 0000 0000 0000 0000 0000
bit31 = 1 → VA[38:30] = 0b000000010 = 2  → L1[2]
```

#### L2 表 (@ PA 0x400B2000 / 0x400B3000)

| 表项 | 内存地址 | 存储的值 | 含义 |
|------|----------|----------|------|
| L2_A[0] | `0x400B2000` | `0x40000701` | 2MB block → PA base `0x40000000` |
| L2_B[0] | `0x400B3000` | `0x40000701` | 2MB block → PA base `0x40000000` |

`0x40000701` 二进制解析（Block Descriptor）：

```
0x40000701 = 0x40000000 | (1<<10) | (3<<8) | 1
           = 输出PA | AF=1  | SH=3  | valid

bit[0]   = 1   有效
bit[1]   = 0   BLOCK descriptor（翻译终止！）
bit[4:2] = 000 AttrIndx = 0，去 MAIR_EL1[7:0] 取内存属性（0xFF = Normal WBWA）
bit[7:6] = 00  AP = 00（EL1 可读写）
bit[9:8] = 11  SH = 3（inner shareable）
bit[10]  = 1   AF = 1（已访问，不产生 Access Flag fault）
bit[47:21] = 0x200  输出物理地址高 27 位（0x200 << 21 = 0x40000000）
```

---

## 六、地址翻译全过程

以 identity 映射的 **VA `0x40090000`** 为例。

### Step 1：VA 拆分为各级索引

```
VA = 0x0000 0000 4009 0000 (64-bit)

┌──────────┬──────────┬──────────┬────────────┐
│ VA[47:39]│ VA[38:30]│ VA[29:21]│ VA[20:0]   │
│   9 bits │   9 bits │   9 bits │   21 bits  │
│  L0 idx  │  L1 idx  │  L2 idx  │   offset   │
│   = 0    │   = 1    │   = 0    │  = 0x90000 │
└──────────┴──────────┴──────────┴────────────┘
```

### Step 2：L0 查表

```
TTBR0_EL1 = 0x400B0000 (物理地址)

MMU 读 PA 0x400B0000 + 0×8 = 0x400B0000
  → 得到 0x400B1003
  → bit[1]=1 (table), bit[47:12]=0x400B1
  → 下一级 PA = 0x400B1000
```

### Step 3：L1 查表

```
MMU 读 PA 0x400B1000 + 1×8 = 0x400B1008
  → 得到 0x400B2003
  → bit[1]=1 (table), bit[47:12]=0x400B2
  → 下一级 PA = 0x400B2000
```

### Step 4：L2 查表（终止）

```
MMU 读 PA 0x400B2000 + 0×8 = 0x400B2000
  → 得到 0x40000701
  → bit[1]=0 (BLOCK! 翻译终止)
  → bit[47:21] = 0x200 → PA_base = 0x200 << 21 = 0x40000000

最终 PA = PA_base | VA[20:0]
        = 0x40000000 | 0x90000
        = 0x40090000  ← 与 VA 相同，这就是 identity 映射
```

### Step 5：non-identity 路径的对比

对于 **VA `0x80090000`**，L1 index = 2，分叉到另一张 L2 表：

```
VA 0x40090000                    VA 0x80090000
     │                                │
L0[0] → L1 表 (同一张)               │
     │                                │
L1[1] → L2_A @0x400B2000          L1[2] → L2_B @0x400B3000
     │                                │
L2_A[0]: PA_base = 0x40000000    L2_B[0]: PA_base = 0x40000000
     │                                │
     └──────── 都指向同一个 PA! ───────┘
```

两个不同的 VA，在 L1 处分叉，但各自的 L2 block descriptor 里写的输出 PA 基址相同，最终访问到同一物理地址。

---

## 七、预期实验结果

运行 `run_gdb` 后，`0x400C0000` 处的四个值：

```
[0] = 0x00000000DEADBEEF   ← identity VA 读
[1] = 0x00000000DEADBEEF   ← non-identity VA 读（不同 VA，同一数据！）
[2] = 0x00000000CAFEBABE   ← non-identity VA 读
[3] = 0x00000000FEEDFACE   ← 跨 VA 写入验证（non-identity 写，identity 读）
```

`[0] == [1] == 0xDEADBEEF` 证明：不同虚拟地址通过页表翻译后，访问到同一个物理地址。

---

## 八、相关 ARM64 系统寄存器

| 寄存器 | 作用 | 实验中的设置 |
|--------|------|-------------|
| `SCTLR_EL1` | 系统控制寄存器 | bit[0] (M) = 1 使能 MMU |
| `TTBR0_EL1` | 页表基址寄存器 | 指向 L0 表 @ `0x400B0000` |
| `TCR_EL1` | 翻译控制寄存器 | T0SZ=16 (48-bit VA), EPD1=1 (禁用 TTBR1) |
| `MAIR_EL1` | 内存属性寄存器 | Attr0 = 0xFF (Normal, Inner/Outer Write-Back) |

---

## 九、遇到的坑和解决方案

1. **QEMU 默认 TCR_EL1 = 0**：T0SZ=0 意味着 64-bit VA，必须从 L0 开始翻译。之前尝试直接用 1GB block 在 L1 级别（T0SZ=25）失败，换成标准 3 级页表（T0SZ=16，L0→L1→L2）后正常。

2. **页表 descriptor 必须设置 SH（shareability）**：不加 `SH=3` 时 MMU 使能后内存访问失败。Block descriptor 需要 `AF=1` + `SH=3` + `valid`。

3. **`continue` 和 `si` 行为不同**：GDB 的 `continue` 在 MMU 使能后无法正常停住（目标一直在运行），但 `si` 单步可以。最终方案是让程序在验证完成后**自行关闭 MMU**，然后在关 MMU 后的死循环处设断点，用 `continue` 直达。

4. **`-x` 脚本文件 vs `-ex` 命令行**：GDB 从脚本文件读取命令和从 `-ex` 读取时 `continue` 行为有差异，最终 `run_gdb` 采用简洁的 3 断点 + 1 次 `continue` 方案。
