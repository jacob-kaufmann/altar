# a minimal test kernel entry point.
#
# this is intended to replicate the actual kernel entry point, but with as
# little as possible, setting up pseudo-symbols to test kernel functionality.
#
# comments will be sparser, so if something does not make sense, there is likely
# a corresponding comment in the actual kernel entry point.
#
# TODO: test nested trap.
# TODO: test traps beyond `ebreak`.

.include "platform.inc"
.include "riscv.inc"

# NOTE: we mark the section with `.entry` so that the linker can specifically
# place the entry point.
.balign 16
.section .text.entry
.global kernelentry
kernelentry:
  la sp, stackhigh

  # establish the S-mode context.
  la   t0, sctx
  csrw sscratch, t0

  # set the S-mode trap vector.
  la t0, suptvec
  csrw stvec, t0

  # disable interrupts.
  #
  # TODO: while we only test the exception trap vector path, do not enable
  # interrupts.
  li   t0, SSTATUS_MASK_SIE
  csrc sstatus, t0

  # allocate space for the pre-trap and post-trap frames.
  addi sp, sp, (-288 * 2)

  # set up the initial register state.
  #
  # NOTE: we do not perturb the return address or the stack pointer.
  li x3, 3
  li x4, 4
  li x5, 5
  li x6, 6
  li x7, 7
  li x8, 8
  li x9, 9
  li x10, 10
  li x11, 11
  li x12, 12
  li x13, 13
  li x14, 14
  li x15, 15
  li x16, 16
  li x17, 17
  li x18, 18
  li x19, 19
  li x20, 20
  li x21, 21
  li x22, 22
  li x23, 23
  li x24, 24
  li x25, 25
  li x26, 26
  li x27, 27
  li x28, 28
  li x29, 29
  li x30, 30
  li x31, 31

  # save the pre-trap frame.
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
  csrr x1, sepc
  sd   x1, 248(sp)
  csrr x1, scause
  sd   x1, 256(sp)
  csrr x1, stval
  sd   x1, 264(sp)
  csrr x1, sstatus
  sd   x1, 272(sp)
  ld   x1, 0(sp)

  # deliberately trap.
  ebreak

  # save the post-trap frame.
  sd  x1,  (288 + 0)(sp)
  sd  x2,  (288 + 8)(sp)
  sd  x3,  (288 + 16)(sp)
  sd  x4,  (288 + 24)(sp)
  sd  x5,  (288 + 32)(sp)
  sd  x6,  (288 + 40)(sp)
  sd  x7,  (288 + 48)(sp)
  sd  x8,  (288 + 56)(sp)
  sd  x9,  (288 + 64)(sp)
  sd  x10, (288 + 72)(sp)
  sd  x11, (288 + 80)(sp)
  sd  x12, (288 + 88)(sp)
  sd  x13, (288 + 96)(sp)
  sd  x14, (288 + 104)(sp)
  sd  x15, (288 + 112)(sp)
  sd  x16, (288 + 120)(sp)
  sd  x17, (288 + 128)(sp)
  sd  x18, (288 + 136)(sp)
  sd  x19, (288 + 144)(sp)
  sd  x20, (288 + 152)(sp)
  sd  x21, (288 + 160)(sp)
  sd  x22, (288 + 168)(sp)
  sd  x23, (288 + 176)(sp)
  sd  x24, (288 + 184)(sp)
  sd  x25, (288 + 192)(sp)
  sd  x26, (288 + 200)(sp)
  sd  x27, (288 + 208)(sp)
  sd  x28, (288 + 216)(sp)
  sd  x29, (288 + 224)(sp)
  sd  x30, (288 + 232)(sp)
  sd  x31, (288 + 240)(sp)
  csrr x1, sepc
  sd   x1, (288 + 248)(sp)
  csrr x1, scause
  sd   x1, (288 + 256)(sp)
  csrr x1, stval
  sd   x1, (288 + 264)(sp)
  csrr x1, sstatus
  sd   x1, (288 + 272)(sp)

  # call the test assertion function with a single stack pointer argument.
  mv a0, sp
  call verify_sup_traphandler

  call pass

.section .text


.balign 16
.global sup_traphandler
sup_traphandler:
  # if the stack pointer is not 16-byte aligned, then fail.
  andi t0, sp, 0b1111
  bnez t0, fail

  # increment the `sepc` register in the trap frame, so that when we write that
  # value to the CSR and subsequently execute `sret`, we return the instruction
  # following `ebreak`. currently, if we did not increment `sepc` in the trap
  # frame, then we would return back to the `ebreak` instruction, going into a
  # trap loop.
  #
  # NOTE: `a0` holds the stack pointer.
  ld   t0, 248(a0)
  addi t0, t0, 4
  sd   t0, 248(a0)

  # flip the SPIE bit of `sstatus`, so that we can check the preservation of the
  # SIE bit in `sstatus`. if we did not correctly preserve it, then when the
  # trap vector returns via `sret`, SIE will be set to SPIE, which may have
  # changed due to a nested trap.
  csrr t0, sstatus
  xori t0, t0, SSTATUS_MASK_SPIE
  csrw sstatus, t0

  # perturb all registers that should be saved, except for `ra` and `sp`, which
  # correspond to `x1` and `x2` respectively. we preserve `ra` for the `ret`
  # instruction at the end of the function, and we preserve `sp` so that we can
  # append the post-trap frame to the pre-trap stack.
  addi x3, x3, 1
  addi x4, x4, 1
  addi x5, x5, 1
  addi x6, x6, 1
  addi x7, x7, 1
  addi x8, x8, 1
  addi x9, x9, 1
  addi x10, x10, 1
  addi x11, x11, 1
  addi x12, x12, 1
  addi x13, x13, 1
  addi x14, x14, 1
  addi x15, x15, 1
  addi x16, x16, 1
  addi x17, x17, 1
  addi x18, x18, 1
  addi x19, x19, 1
  addi x20, x20, 1
  addi x21, x21, 1
  addi x22, x22, 1
  addi x23, x23, 1
  addi x24, x24, 1
  addi x25, x25, 1
  addi x26, x26, 1
  addi x27, x27, 1
  addi x28, x28, 1
  addi x29, x29, 1
  addi x30, x30, 1
  addi x31, x31, 1

  ret

.balign 16
.local fail
fail:
  # report failure to QEMU. `0x00100000` is the MMIO address of the SiFive
  # "test-finisher" device on QEMU `virt`.
  #
  # NOTE: once we enable virtual memory, this access will require an appropriate
  # mapping.
  li t0, 0x00100000
  li t1, 0x13333
  sw t1, 0(t0)
  j  purgatory

.balign 16
.local pass
pass:
  # report success to QEMU. `0x00100000` is the MMIO address of the SiFive
  # "test-finisher" device on QEMU `virt`.
  #
  # NOTE: once we enable virtual memory, this access will require an appropriate
  # mapping.
  li t0, 0x00100000
  li t1, 0x5555
  sw t1, 0(t0)
  j  purgatory

.balign 16
.local purgatory
purgatory:
  wfi
  j purgatory

.section .bss

.balign 16
.global sctx
sctx:
  .zero 256

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
