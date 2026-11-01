# a minimal bootloader for QEMU "virt" platform (i.e. board).

.include "platform.inc"
.include "riscv.inc"

# TODO: portability for RV32?
# TODO: tighten up alignment if possible.

# TODO: tighten. current number of ticks is somewhat arbitrary.
.equ TIMER_INT_TICKS_INIT, 1000000

.section .text.entry

.balign 16
.global bootentry
bootentry:
  # load the `mhartid` CSR into a temporary register. if the hart ID is not
  # equal to zero, then branch to the idle loop.
  #
  # NOTE: we assume that we are in M (i.e. machine) mode, since otherwise `csrr`
  # would trap. if openSBI is in use, then we will be in S mode, and this will
  # trap.
  #
  # NOTE: we assume that there is only a single hart, and that, on QEMU, the
  # hart ID is zero. once we remove the single hart assumption, we can determine
  # the number of harts via the device tree blob (DTB).
  csrr t0, mhartid
  bnez t0, purgatory

  # clear the machine interrupt enable (MIE) and supervisor interrupt enable
  # (SIE) bits in the `mstatus` CSR. clearing the MIE bit globally disables
  # interrupts for execution in privilege M, which is the privilege level of the
  # bootloader. we disable interrupts until we set up the M mode trap vector.
  # while interrupts for privilege level S are always disabled during M mode
  # execution, we clear SIE so that, once we transfer to the kernel entry point,
  # there cannot be an interrupt to S mode until we set up the S mode trap
  # vector.
  li   t0, (MSTATUS_MASK_SIE | MSTATUS_MASK_MIE)
  csrc mstatus, t0

  # clear the machine interrupt enable (i.e. `mie`) CSR. even though we clear
  # the MIE bit of `mstatus` above, an interrupt from a lower privilege mode can
  # trap if the corresponding bit is set in `mie`.
  csrw mie, zero

  # load the address of the high address of the stack region into the stack
  # pointer register. we assign the high address because the stack grows
  # "downward" (i.e. from a higher address to a lower address), and the stack
  # is empty.
  la sp, stackhigh

  # physical memory protection (PMP). here, we use naturally-aligned power of
  # two (NAPOT) with all address bits set to grant S mode access to the entire
  # address space with read/write/execute permissions.
  #
  # NOTE: PMP entries correspond to an 8-bit config register (i.e. `pmpcfgN`)
  # and an MXLEN-bit address register (i.e. `pmpaddrN`). these CSRs are only
  # available in M mode.
  # 
  # NOTE: PMP config register layout: | L | 0 0 | A A | X | W | R |. the `A`
  # field corresponds to the address-matching mode for the associated address
  # register.
  li   t0, -1
  csrw pmpaddr0, t0
  # TODO: tidy up setting PMP config. we have these mask bit vectors, but it is
  # also nice to have not just the masks but the values (e.g. NAPOT). however,
  # for single-bit fields, they are sort of equivalent.
  li   t1, (PMPCFG_MASK_READ | PMPCFG_MASK_WRITE | PMPCFG_MASK_EXEC)
  ori  t1, t1, PMPCFG_ADDR_NAPOT
  csrw pmpcfg0, t1

  # supervisor address translation and protection (SATP). we set the mode to
  # BARE, which corresponds to no translation/protection. in BARE mode, the
  # remaining bits must be zero. otherwise, address translation and protection
  # behavior is unspecified.
  csrw satp, zero

  # write the location of the hart-local context to `mscratch`.
  #
  # NOTE: in a multi-hart environment, we would have to compute some offset
  # based on the hart ID.
  la   t0, mctx
  csrw mscratch, t0

  # print output message from the bootloader.
  la   a0, output
  call uartprint

  # machine trap vector base address. write the machine trap vector base address
  # to `mtvec`, and set the mode to direct. in direct mode, all traps into
  # machine mode (synchronous exceptions and asynchronous interrupts) cause the
  # `pc` to be set to the base address.
  #
  # NOTE: the trap vector base address ought to be aligned to 16 bytes, so we do
  # not need to zero the lower two bits for direct mode.
  la   t0, machtvec
  csrw mtvec, t0

  # machine exception delegation.
  #
  # delegate the following exceptions:
  # - 0: instruction address mis-aligned
  # - 1: instruction access fault
  # - 2: illegal instruction
  # - 3: breakpoint
  # - 4: load address mis-aligned
  # - 5: load access fault
  # - 6: store/AMO access mis-aligned
  # - 7: store/AMO access fault
  # - 8: environment call from U mode
  # - 12: instruction page fault
  # - 13: load page fault
  # - 15: store/AMO page fault
  #
  # NOTE: AMO is atomic memory operation.
  #
  # TODO: probe the register to see which exceptions are delegate-able (e.g.
  # extensions).
  li   t0, 0xb1ff
  csrw medeleg, t0

  # machine interrupt delegation.
  #
  # delegate the following interrupts:
  # - 2: supervisor (S) software interrupt
  # - 5: supervisor (S) timer interrupt
  # - 9: supervisor (S) external interrupt
  #
  # NOTE: we cannot delegate the machine software/timer/external interrupts.
  # 
  # TODO: probe the register to see which exceptions are delegate-able (e.g.
  # extensions).
  li   t0, 0x02220
  csrw mideleg, t0

  # re-set machine interrupt enable (MIE) in `mstatus`. supervisor interrupt
  # enable (SIE) is re-set in the kernel entry point.
  li   t0, MSTATUS_MASK_MIE
  csrs mstatus, t0

  # set the machine timer interrupt enable (MTIE) bit and the supervisor timer
  # interrupt bit in the `mie` CSR.
  li   t0, (MIE_MASK_MTIE | MIE_MASK_STIE)
  csrs mie, t0

  # set the TM (i.e. time) bit in the machine counter enable (i.e. `mcounteren`)
  # CSR, so that S mode can access the `stime` register.
  csrsi mcounteren, MCOUNTEREN_MASK_TM

  # schedule the initial timer interrupt.
  li  t0, MMIO_ADDR_MTIME
  ld  t1, 0(t0)
  li  t2, TIMER_INT_TICKS_INIT
  add t1, t1, t2
  li  t0, MMIO_ADDR_MTIMECMP_BASE
  sd  t1, 0(t0)
  
  # machine previous interrupt enable (MPIE). we set MPIE to 1 so that `mret`
  # (below) sets MIE to 1.
  li   t0, MSTATUS_MASK_MPIE
  csrs mstatus, t0

  # machine privilege previous (MPP). we set MPP to S mode, so that `mret`
  # (below) returns to S mode.
  li   t0, MSTATUS_MASK_MPP
  csrc mstatus, t0
  li   t0, MPP_S
  slli t0, t0, MSTATUS_OFFSET_MPP
  csrs mstatus, t0

  # machine exception program counter (MEPC). we set the `mepc` register to the
  # location of the kernel. when we execute `mret` (below), `pc` is set to
  # `mepc`.
  li   t0, ENTRYPOINT_KERNEL
  csrw mepc, t0

  # TODO: elaborate on arguments for jump to kernel.
  csrr a0, mhartid
  mv a1, zero

  # machine return.
  mret

.section .text

.balign 16
.local purgatory
purgatory:
  # wait here forever.
  wfi
  j purgatory

.section .rodata
.balign 16
.local output
output: .asciz "hello from the bare metal :)\n"

.section .bss

# hart-local context. each hart maintains the location of its context in its
# `mscratch` register.
#
# NOTE: to support multiple harts, this region will consist of a contiguous
# array of hart-local contexts indexed by hart ID (if hart IDs are contiguous).
.balign 16
.local mctx
mctx:
  .zero 256

# trap-specific stack.
.balign 16
.global mtstacklow
mtstacklow:
  .zero 8192
.global mtstackhigh
mtstackhigh:

# general purpose stack.
.balign 16
.local stacklow
stacklow:
  .zero 8192
.local stackhigh
stackhigh:
