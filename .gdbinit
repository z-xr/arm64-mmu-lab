set architecture aarch64
target remote :1234

# 设置自动显示的寄存器和内存
display /x $x0
display /x $x1
display /x $x4
display /x $x5
display /x $x6
display /x $x7
display /x $x8
display /i $pc

# 停在 _start
break _start
continue
