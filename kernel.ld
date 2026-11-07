ENTRY(kernelentry)

/* the bootloader linker script maps the entry to 0x80000000 for QEMU `virt`. */
/* by convention, firmware (i.e. openSBI) occupies the first two megabytes. */
/* therefore, we map the kernel entry to 0x80200000. */

SECTIONS
{
  . = 0x80200000;
  .text    : { KEEP(*(.text.entry)) *(.text .text.*) }
  .rodata  : { *(.rodata .rodata.*) }
  .data    : { *(.data .data.*) }
  .bss     : { *(.bss .bss.*) }

  /* align the end of the kernel's memory region to the page size of 4KiB. */
  /* physical memory that we allocate pages from begins after here. */
  . = ALIGN(4096);
  __kernelend = .;
}
