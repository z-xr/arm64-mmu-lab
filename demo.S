.section .text
.globl _start

_start:
    // ==========================================
    // 阶段1: 开 MMU 之前 — 所有地址都是物理地址
    // ==========================================

    ldr x0, =0x40090000
    ldr x1, =0xDEADBEEF
    str x1, [x0]

    ldr x0, =0x400A0000
    ldr x1, =0xCAFEBABE
    str x1, [x0]

    // 读回确认
    ldr x0, =0x40090000
    ldr x7, [x0]                    // x7 应为 0xDEADBEEF

    // ==========================================
    // 阶段2: 建立 3 级页表 (L0 → L1 → L2, 2MB block)
    // L0 表 @ 0x400B0000, L1 表 @ 0x400B1000
    // L2_A 表 @ 0x400B2000 (identity), L2_B @ 0x400B3000 (non-identity)
    // ==========================================

    // 清零 4 张表
    ldr x0, =0x400B0000
    mov x1, xzr
    mov x2, #(512 * 4)
1:
    str x1, [x0], #8
    subs x2, x2, #1
    b.ne 1b

    // L0[0] → L1 表 (VA[47:39] = 0)
    ldr x0, =0x400B0000
    ldr x1, =0x400B1000
    orr x1, x1, #3                  // valid + table
    str x1, [x0]

    // L1[1] → L2_A (identity) (VA 0x40000000: bits[38:30] = 1)
    ldr x0, =0x400B1000
    ldr x1, =0x400B2000
    orr x1, x1, #3
    str x1, [x0, #(1 * 8)]

    // L1[2] → L2_B (non-identity) (VA 0x80000000: bits[38:30] = 2)
    ldr x1, =0x400B3000
    orr x1, x1, #3
    str x1, [x0, #(2 * 8)]

    // L2_A[0]: identity map 0x40000000-0x401FFFFF → PA 0x40000000
    // (VA bits[29:21] = 0 for 0x40000000)
    ldr x0, =0x400B2000
    ldr x1, =0x40000000             // output PA
    orr x1, x1, #(1 << 10)          // AF=1
    orr x1, x1, #(3 << 8)           // SH=3
    orr x1, x1, #1                  // valid 2MB block
    str x1, [x0]

    // L2_B[0]: non-identity map 0x80000000-0x801FFFFF → PA 0x40000000
    ldr x0, =0x400B3000
    ldr x1, =0x40000000
    orr x1, x1, #(1 << 10)
    orr x1, x1, #(3 << 8)
    orr x1, x1, #1
    str x1, [x0]

page_table_ready:
    dsb sy

    // ==========================================
    // 阶段3: 配置 MMU 寄存器
    // ==========================================

    // MAIR_EL1: Attr0 = 0xFF (Normal WBWA)
    ldr x1, =0xFF
    msr MAIR_EL1, x1

    // TCR_EL1: T0SZ=16 (48-bit VA, 从 L0 开始), EPD1=1
    mrs x1, TCR_EL1
    mov x2, #16
    bfi x1, x2, #0, #6              // T0SZ[5:0] = 16
    orr x1, x1, #(1 << 23)          // EPD1=1
    msr TCR_EL1, x1

    // TTBR0_EL1: 指向 L0 表
    ldr x0, =0x400B0000
    msr TTBR0_EL1, x0
    isb

    // 无效化 TLB
    tlbi vmalle1
    dsb sy
    isb

    // ==========================================
    // 阶段4: 开启 MMU
    // ==========================================
    mrs x0, SCTLR_EL1
    orr x0, x0, #1
    msr SCTLR_EL1, x0

mmu_enabled:
    isb                             // MMU 已生效!

    // ==========================================
    // 阶段5: MMU 开启后的对比测试
    // ==========================================

    // 5a. Identity VA 读 (VA == PA)
    ldr x0, =0x40090000
    ldr x4, [x0]                    // x4 应为 0xDEADBEEF

    // 5b. 非 identity VA 读 (VA 0x80090000 → PA 0x40090000)
    ldr x0, =0x80090000
    ldr x5, [x0]                    // x5 也应为 0xDEADBEEF!

    // 5c. 另一非 identity VA
    ldr x0, =0x800A0000
    ldr x6, [x0]                    // x6 应为 0xCAFEBABE

    // 5d. 跨 VA 写入验证
    ldr x0, =0x80090000
    ldr x1, =0xFEEDFACE
    str x1, [x0]                    // 非 identity VA 写
    ldr x0, =0x40090000
    ldr x8, [x0]                    // identity VA 读 → 也应为 0xFEEDFACE

    // 5e. 保存结果到 0x400C0000
    ldr x0, =0x400C0000
    str x4, [x0, #0]
    str x5, [x0, #8]
    str x6, [x0, #16]
    str x8, [x0, #24]

    // ==========================================
    // 阶段6: 关闭 MMU
    // ==========================================
    mrs x0, SCTLR_EL1
    bic x0, x0, #1
    msr SCTLR_EL1, x0
    isb                             // MMU 已关闭

    b .
