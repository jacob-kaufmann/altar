set quiet

target := "riscv64-unknown-elf"

# `zicsr` extension is necessary for control and status registers.
arch := "rv64ima_zicsr"

# integer calling-convention only (no hardware floating-point).
abi := "lp64"

# `clang` via nix development shell.
clang := env_var("CLANG")

# do not include the C standard library.
# 
# do not include the C start files (e.g. crt), which execute before `main`. we
# do not need those start files since we initialize the stack, zero `bss`, etc.
#
# use LLVM linker `lld`.
#
# TODO: add DWARF debug information?
# TODO: is -g flag necessary here?
clanglinkopts := "-nostdlib -fuse-ld=lld -g -Wl,--gc-sections"

# debug compilation options.
debugopts := "-g"

# rust compilation target and directory.
targetrs := "riscv64imac-unknown-none-elf"
librs    := "target/" + targetrs + "/debug"

build-libs:
    # UART assembly facilities.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c uart.s \
          -o uartasm.o
      
build-bootloader: build-libs
    # machine trap assembly facilities.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c machtrap.s \
          -o machtrapasm.o
    # rust bootloader.
    cargo build -p altarboot --target {{targetrs}} --target-dir target
    # bootloader.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c bootloader.s \
          -o bootloader.o

link-bootloader: build-bootloader
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{clanglinkopts}} \
          -Wl,-T,bootloader.ld uartasm.o machtrapasm.o bootloader.o \
          {{librs}}/libaltarboot.a \
          -o bootloader.elf

build-kernel: build-libs
    # kernel trap assembly facilities.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c suptrap.s \
          -o suptrapasm.o
    # rust kernel.
    cargo build -p altarkernel --target {{targetrs}} --target-dir target
    # kernel.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c kernel.s \
          -o kernel.o

link-kernel: build-kernel
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{clanglinkopts}} \
          -Wl,-T,kernel.ld uartasm.o suptrapasm.o kernel.o \
          {{librs}}/libaltarkernel.a \
          -o kernel.elf

# debug with a port open for remote GDB/LLDB, where the program is frozen at
# startup.
debug gdb-port: link-bootloader link-kernel
    llvm-objcopy -O binary kernel.elf kernel.bin
    qemu-system-riscv64 -machine virt \
                        -bios none \
                        -display none \
                        -serial stdio \
                        -gdb tcp::{{gdb-port}} \
                        -S \
                        -kernel bootloader.elf \
                        -device loader,file=kernel.bin,addr=0x80200000

test-bootloader: build-libs
    # machine trap assembly facilities.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c machtrap.s \
          -o machtrapasm.o
    # rust bootloader with test configuration.
    cargo rustc -p altarboot \
          --lib \
          --target {{targetrs}} \
          --target-dir target \
          -- --cfg test
    # test bootloader.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c tbootloader.s \
          -o tbootloader.o
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{clanglinkopts}} \
          -Wl,-T,bootloader.ld uartasm.o machtrapasm.o tbootloader.o \
          {{librs}}/libaltarboot.a \
          -o tbootloader.elf
    # load and execute.
    qemu-system-riscv64 -machine virt \
                        -bios none \
                        -display none \
                        -monitor none \
                        -serial stdio \
                        -kernel tbootloader.elf \
  
test-kernel: build-libs link-bootloader
    # kernel trap assembly facilities.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c suptrap.s \
          -o suptrapasm.o
    # rust kernel with test configuration.
    cargo rustc -p altarkernel \
          --lib \
          --target {{targetrs}} \
          --target-dir target \
          -- --cfg test
    # test kernel.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{debugopts}} \
          -c tkernel.s \
          -o tkernel.o
    # link test kernel.
    {{clang}} --target={{target}} \
          -march={{arch}} \
          -mabi={{abi}} \
          {{clanglinkopts}} \
          -Wl,-T,kernel.ld uartasm.o suptrapasm.o tkernel.o \
          {{librs}}/libaltarkernel.a \
          -o tkernel.elf
    # load and execute.
    llvm-objcopy -O binary tkernel.elf tkernel.bin
    qemu-system-riscv64 -machine virt \
                        -bios none \
                        -display none \
                        -monitor none \
                        -serial stdio \
                        -kernel bootloader.elf \
                        -device loader,file=tkernel.bin,addr=0x80200000

test: test-bootloader test-kernel

# first, we copy the kernel ELF as a binary, so that we can load that directly
# into memory. a production bootloader would expect a raw binary, not an ELF,
# since there would not be anything available in the ROM to parse an ELF.
run: link-bootloader link-kernel
    llvm-objcopy -O binary kernel.elf kernel.bin
    qemu-system-riscv64 -machine virt \
                        -bios none \
                        -display none \
                        -monitor none \
                        -serial stdio \
                        -kernel bootloader.elf \
                        -device loader,file=kernel.bin,addr=0x80200000

# format source files.
fmt:
    cargo fmt --all

# lint source files.
lint:
    cargo clippy --all

# clean up object files, ELF files, binary files, etc.
clean:
    rm *.o
    rm *.elf
    rm *.bin
