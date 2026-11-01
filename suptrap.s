.include "riscv.inc"

.equ SCTX_OFFSET_T1, 8
.equ SCTX_OFFSET_T2, 16
.equ SCTX_OFFSET_SP, 24

.section .text

.balign 16
.global suptvec
suptvec:
  # NOTE: the platform clears the supervisor interrupt enable (SIE) bit in the
  # `sstatus` CSR, so interrupts are disabled. however, we need to ensure that
  # we do not trigger an exception while we establish the trap frame.
  # 
  # TODO: optimize.

  # load the pointer to the supervisor context from `sscratch` into `t0`, and
  # simultaneously preserve the value of `t0` in `sscratch`.
  csrrw t0, sscratch, t0

  # preserve `t1` and `t2` in the machine context, so that we can use those
  # registers to set up the trap stack frame. note that `t0` is also in the
  # machine context. also, we preserve `sp` so that we can freely move it.
  sd t1, SCTX_OFFSET_T1(t0)
  sd t2, SCTX_OFFSET_T2(t0)
  sd sp, SCTX_OFFSET_SP(t0)

  # determine whether the previous privilege constitutes an escalation in
  # privilege i.e. whether the previous privilege was or was not S. if there was
  # an escalation in privilege, then we need to move the stack pointer.
  csrr t1, sstatus
  li   t2, SSTATUS_MASK_SPP
  and  t1, t1, t2
  srli t1, t1, SSTATUS_OFFSET_SPP
  li   t2, SPP_S
  bne  t2, t1, 1f

  # if the previous privilege is equal to S, then we need to check whether the
  # stack pointer points to a location in the trap-specific stack. if it does,
  # then we don't need to move the stack pointer, and we can append a new trap
  # frame below the pre-existing trap frame. if it does not, then we need to
  # move the stack pointer to the trap-specific stack.
  #
  # NOTE: we do not handle the situation where we were handling a trap and we
  # overflow the stack.
  la   t1, ststacklow
  bltu sp, t1, 1f
  la   t1, ststackhigh
  bgtu sp, t1, 1f
  j    2f

# if the previous privilege is not equal to S, or the previous privilege is
# equal to S and the stack pointer does not point to a location in the
# trap-specific stack, then we need to move the stack pointer to the
# trap-specific stack.
1:
  la sp, ststackhigh

2:
  # reload the values of the registers that we preserved in the hart-local
  # context except for the stack pointer, which we need to delay until we set up
  # the trap frame.
  ld    t1, SCTX_OFFSET_T1(t0)
  ld    t2, SCTX_OFFSET_T2(t0)
  csrrw t0, sscratch, t0

  # allocate the trap frame containing all 32 registers (248 = 31 * 8) and the
  # following four CSRs (32 = 4 * 8): `sepc`, `scause`, `stval`, `sstatus`, and
  # add 8 bytes of padding for 16-byte alignment.
  addi sp, sp, -288

  # store all integer registers to the stack.
  #
  # NOTE: the stack pointer that we store (i.e. x2) is not the original stack
  # pointer. we remedy this below.
  #
  # NOTE: we do not have the floating-point extension enabled, so there is no
  # floating-point register state.
  sd  x1,  0(sp)
  sd  x2,  8(sp)
  sd  x3,  16(sp)
  sd  x4,  24(sp)
  sd  x5,  32(sp)
  sd  x6,  40(sp)
  sd  x7,  48(sp)
  sd  x8,  56(sp)
  sd  x9,  64(sp)
  sd  x10, 72(sp)
  sd  x11, 80(sp)
  sd  x12, 88(sp)
  sd  x13, 96(sp)
  sd  x14, 104(sp)
  sd  x15, 112(sp)
  sd  x16, 120(sp)
  sd  x17, 128(sp)
  sd  x18, 136(sp)
  sd  x19, 144(sp)
  sd  x20, 152(sp)
  sd  x21, 160(sp)
  sd  x22, 168(sp)
  sd  x23, 176(sp)
  sd  x24, 184(sp)
  sd  x25, 192(sp)
  sd  x26, 200(sp)
  sd  x27, 208(sp)
  sd  x28, 216(sp)
  sd  x29, 224(sp)
  sd  x30, 232(sp)
  sd  x31, 240(sp)

  # read and store the CSRs corresponding to the trap.
  csrr t0, sepc
  sd   t0, 248(sp)
  csrr t1, scause
  sd   t1, 256(sp)
  csrr t2, stval
  sd   t2, 264(sp)
  csrr t0, sstatus
  sd   t0, 272(sp)

  # load the original stack pointer from the hart-local context, and store that
  # value appropriately.
  csrr t0, sscratch
  ld   t1, SCTX_OFFSET_SP(t0)
  sd   t1, 8(sp)

  # move the stack pointer into the first argument register, and call the trap
  # handler.
  mv   a0, sp
  call sup_traphandler

  # load and write the `sepc` before we restore the register state. the handler
  # may have changed `sepc` depending on the cause of the trap (i.e. whether we
  # retry the instruction). if we waited until after we restored the register
  # state, then we would not be able to use the registers as scratch space.
  ld   x1,   248(sp)
  csrw sepc, x1

  # load and write the `sstatus` CSR before we restore the register state.
  ld   x1, 272(sp)
  csrw sstatus, x1
  
  # load all the registers from the stack.
  #
  # NOTE: we do not load `x2`, because that is the stack pointer, so loading
  # `x2` would make it so that the remaining loads occur relative to the
  # interrupted stack pointer, not the trap stack pointer.
  ld  x1,  0(sp)
  ld  x3,  16(sp)
  ld  x4,  24(sp)
  ld  x5,  32(sp)
  ld  x6,  40(sp)
  ld  x7,  48(sp)
  ld  x8,  56(sp)
  ld  x9,  64(sp)
  ld  x10, 72(sp)
  ld  x11, 80(sp)
  ld  x12, 88(sp)
  ld  x13, 96(sp)
  ld  x14, 104(sp)
  ld  x15, 112(sp)
  ld  x16, 120(sp)
  ld  x17, 128(sp)
  ld  x18, 136(sp)
  ld  x19, 144(sp)
  ld  x20, 152(sp)
  ld  x21, 160(sp)
  ld  x22, 168(sp)
  ld  x23, 176(sp)
  ld  x24, 184(sp)
  ld  x25, 192(sp)
  ld  x26, 200(sp)
  ld  x27, 208(sp)
  ld  x28, 216(sp)
  ld  x29, 224(sp)
  ld  x30, 232(sp)
  ld  x31, 240(sp)

  # load the interrupted stack pointer.
  ld x2, 8(sp)

  # NOTE: `sret` restores the SIE bit in `sstatus` according to the SPIE bit in
  # `sstatus`. therefore, we do not need to manually restore it.
  sret

# NOTE: `a0` holds the desired `mtimecmp` for the next timer interrupt.
.balign 16
.global sup_ecall_mtimecmp_set
sup_ecall_mtimecmp_set:
  # put the `ecall` function identifier in `a7`.
  # 
  # TODO: add symbolic constant.
  mv a7, zero

  ecall

  ret

