# ARM64 裸机汇编学习环境

用 QEMU + GDB 单步调试 ARM64 汇编指令，当前实验：**MMU 使能前后对比**。

## 文件说明

| 文件 | 作用 |
|------|------|
| `demo.S` | ARM64 汇编源码 — MMU 使能前后对比实验 |
| `linker.lds` | 链接脚本，代码段放 0x40080000 |
| `run_gdb` | GDB 批处理脚本，自动设断点、逐条执行并显示寄存器 |
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

### 方式一：批处理脚本（推荐）

```bash
aarch64-linux-gnu-gdb -q -x run_gdb demo.elf
```

### 方式二：交互式调试

两个终端配合：

**终端 1 — QEMU：**
```bash
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256 -nographic -kernel demo.elf -s -S
```

**终端 2 — GDB：**
```bash
aarch64-linux-gnu-gdb -q demo.elf -ex "target remote :1234"
```

GDB 中常用命令：
```gdb
break _start          # 在 _start 设断点
break mmu_enabled     # 在 MMU 使能后设断点
continue              # 继续执行到下一断点
si                    # 单步执行一条指令
p/x $x4              # 打印 x4 寄存器
display /x $x0        # 每步自动显示 x0
info registers        # 查看所有通用寄存器
x/4gx 0x400C0000     # 查看内存（实验结束后结果存在这里）
```

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
