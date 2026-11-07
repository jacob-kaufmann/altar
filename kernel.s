# a minimal kernel entry point.

.include "platform.inc"
.include "riscv.inc"

# TODO: portability for RV32/RV64?

# NOTE: we mark the section with `.entry` so that the linker can specifically
# place the entry point.
.balign 16
.section .text.entry
.global kernelentry
kernelentry:
  # NOTE: we assume that we are in S (i.e. supervisor) mode.

  # load the address of the high address of the stack region into the stack
  # pointer register. we assign the high address because the stack grows
  # "downward" (i.e. from a higher address to a lower address), and the stack
  # is empty.
  la sp, stackhigh

  # write the location of the hart-local context to `sscratch`.
  #
  # NOTE: in a multi-hart environment, we would have to compute some offset
  # based on the hart ID.
  la   t0, sctx
  csrw sscratch, t0

  # supervisor trap vector base address. write the supervisor trap vector base
  # address to `stvec`, and set the mode to direct. in direct mode, all traps
  # into supervisor mode (synchronous exceptions and asynchronous interrupts)
  # cause the `pc` to be set to the base address.
  #
  # NOTE: the address of `suptvec` ought to be aligned to 16 bytes, so we do not
  # need to zero the lower two bits for direct mode.
  la t0, suptvec
  csrw stvec, t0

  # enable interrupts from the UART device. we must set the DLAB bit of the line
  # control register (LCR) to logic low to set the interrupt enable register
  # (IER).
  li   t0, UART
  lbu  t1, UART_OFFSET_LCR(t0)
  andi t1, t1, ~UART_MASK_LCR_DLAB
  sb   t1, UART_OFFSET_LCR(t0)
  lbu  t1, UART_OFFSET_IER(t0)
  ori  t1, t1, UART_MASK_IER_ERBFI
  sb   t1, UART_OFFSET_IER(t0)

  # address of PLIC.
  li t0, PLIC

  # the context is an index into the PLIC memory-mapped regions.
  li t1, PLIC_CTX_KERNEL

  # set the interrupt priority for interrupt source corresponding to the UART
  # device.
  li   t2, PLIC_OFFSET_INT_PRIORITY
  add  t2, t2, t0
  addi t2, t2, (PLIC_INT_SRC_UART << 2) # each slot is 4 bytes
  li   t3, PLIC_INT_PRIORITY_UART
  sw   t3, 0(t2)

  # set the interrupt priority threshold for the PLIC context corresponding to
  # the kernel. set the threshold to zero to enable all interrupts with a
  # positive (i.e. non-zero) priority.
  li   t2, PLIC_OFFSET_INT_THRESHOLD
  add  t2, t2, t0
  slli t3, t1, 12 # 1024 sources times 4 bytes for each threshold
  add  t2, t2, t3
  sw   zero, 0(t2)

  # enable interrupts for the PLIC context corresponding to the kernel.
  li   t2, PLIC_OFFSET_INT_SRC_ENABLE
  add  t2, t2, t0
  slli t3, t1, 7 # 1024 sources divided by 8 bits per byte
  add  t2, t2, t3
  lwu  t4, 0(t2)
  li   t5, (1 << PLIC_INT_SRC_UART) # TODO: shift is not robust for ID >= XLEN.
  or   t4, t4, t5
  sw   t4, 0(t2)

  # initialize the kernel.
  call kernelinit

  # enable external interrupts in the `sie` CSR.
  li   t0, SIE_MASK_SEIE
  csrs sie, t0

  # enable interrupts in the `sstatus` CSR.
  li   t0, SSTATUS_MASK_SIE
  csrs sstatus, t0

  j purgatory

.section .text
.balign 16

.local purgatory
purgatory:
  wfi
  j purgatory

.section .rodata
.local output
output: .asciz "hello from the kernel :)\n"

.section .bss

# allocate memory for the hart-local context that maintains context information.
# each hart maintains the location of its context in its `mscratch` register.
#
# NOTE: to support multiple harts, this region will consist of a contiguous
# array of hart-local contexts indexed by hart ID (if hart IDs are contiguous).
.balign 16
.global sctx
sctx:
  .zero 256

# trap-specific stack.
.balign 16
.global ststacklow
ststacklow:
  .zero 8192
.global ststackhigh
ststackhigh:

.local stacklow
stacklow:
  .zero 8192
.local stackhigh
stackhigh:
