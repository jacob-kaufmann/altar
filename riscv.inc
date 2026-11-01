# RISC-V specific constants.

################################################################################
# traps (exceptions and interrupts).
################################################################################

# NOTE: the exception codes for `scause` are a subset of the exception codes for
# `mcause`, so we do not use separate constants for each.
# TODO: define.

################################################################################
# machine level ISA.
################################################################################

# previous privilege mode.
.equ MPP_M, 0b11
.equ MPP_S, 0b01
.equ MPP_U, 0b00
.equ SPP_S, 0b1
.equ SPP_U, 0b0

# machine status (`mstatus`) CSR bit masks and offsets.
.equ MSTATUS_MASK_SIE,  (0b01 << 1)
.equ MSTATUS_MASK_MIE,  (0b01 << 3)
.equ MSTATUS_MASK_SPIE, (0b01 << 5)
.equ MSTATUS_MASK_MPIE, (0b01 << 7)
.equ MSTATUS_OFFSET_MPP, 11
.equ MSTATUS_MASK_MPP,  (0b11 << MSTATUS_OFFSET_MPP)

# supervisor status (`sstatus`) CSR bit masks and offsets.
.equ SSTATUS_OFFSET_SPP, 8
.equ SSTATUS_MASK_SPP, (0b01 << SSTATUS_OFFSET_SPP)
.equ SSTATUS_OFFSET_SPIE, 5
.equ SSTATUS_MASK_SPIE, (0b01 << SSTATUS_OFFSET_SPIE)

# machine interrupt enable (`mie`) CSR bit masks.
.equ MIE_MASK_STIE, (1 << 5)
.equ MIE_MASK_MTIE, (1 << 7)

# machine interrupt pending (`mip`) CSR bit masks.
.equ MIP_MASK_STIP, (1 << 5)

# physical memory protection config (`pmpcfg`) CSR bit masks.
.equ PMPCFG_MASK_READ,  0b00001
.equ PMPCFG_MASK_WRITE, 0b00010
.equ PMPCFG_MASK_EXEC,  0b00100
.equ PMPCFG_MASK_ADDR,  0b11000

# physical memory protection config (`pmpcfg`) CSR bit values.
.equ PMPCFG_ADDR_NAPOT, 0b11000

# machine counter enable (`mcounteren`) CSR bit masks.
.equ MCOUNTEREN_MASK_TM, 0b10

################################################################################
# supervisor-level ISA.
################################################################################

# supervisor status (`sstatus`) CSR bit masks.
.equ SSTATUS_MASK_SIE,  (1 << 1)

# supervisor interrupt enable (`sie`) CSR bit masks.
.equ SIE_MASK_SEIE, (1 << 9)
