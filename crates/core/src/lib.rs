#![no_std]

/// returns `true` if `x` has alignment `alignment` and `false` otherwise.
///
/// # Safety
///
/// panics if `alignment` is not a power of two.
pub const fn is_aligned(x: usize, alignment: usize) -> bool {
    assert!(alignment.is_power_of_two());
    x & (alignment - 1) == 0
}

pub mod platform {
    use super::*;

    #[derive(Clone, Copy)]
    pub struct HalfOpenInterval {
        pub begin: usize,
        pub end: usize,
    }

    impl HalfOpenInterval {
        pub const fn contains(self, x: usize) -> bool {
            x >= self.begin && x < self.end
        }
    }

    /// universal asynchronous receiver-transmitter (UART).
    pub const MMIO_ADDR_UART: usize = 0x10000000;
    /// platform-level interrupt controller (PLIC).
    pub const MMIO_ADDR_PLIC: usize = 0x0c000000;
    /// `mtime` register.
    pub const MMIO_ADDR_MTIME: usize = 0x0200bff8;

    /// size (in bytes) of physical memory.
    pub const MEMSIZE: usize = 1usize << 27;

    pub const MEMREGION: HalfOpenInterval = HalfOpenInterval {
        begin: 0x80000000,
        end: 0x80000000 + MEMSIZE,
    };

    /// address of the bootloader entry point.
    pub const ADDR_BOOT_ENTRY: usize = MEMREGION.begin;
    /// address of the kernel entry point.
    pub const ADDR_KERNEL_ENTRY: usize = 0x80200000;

    /// size (in bytes) of a memory page.
    pub const PAGESIZE: usize = 4096;

    /// number of memory pages.
    pub const PAGES: usize = MEMSIZE / PAGESIZE;

    const _: () = {
        assert!(MEMSIZE.is_power_of_two());
        assert!(PAGESIZE.is_power_of_two());
        assert!(MEMSIZE == PAGESIZE * PAGES);
        assert!(is_aligned(MEMREGION.begin, PAGESIZE));
        assert!(is_aligned(MEMREGION.end, PAGESIZE));
    };
}

pub mod trap {
    /// trap frame.
    #[repr(C, align(16))]
    pub struct TrapFrame {
        /// integer registers.
        pub x: [usize; 31],
        /// program counter (PC).
        pub xepc: usize,
        /// trap cause.
        pub xcause: usize,
        /// trap value.
        pub xtval: usize,
        /// status CSR.
        pub xstatus: usize,
        /// padding for alignment.
        pad: [u8; 8],
    }

    const _: () = {
        assert!(core::mem::align_of::<TrapFrame>() == 16);
        assert!(core::mem::size_of::<TrapFrame>() == 288);
    };

    /// platform logic interrupt controller (PLIC) interrupt source.
    pub enum PlicInterruptSource {
        /// universal asynchronous receiver-transmitter (UART).
        Uart,
    }

    impl TryFrom<usize> for PlicInterruptSource {
        type Error = ();

        fn try_from(value: usize) -> Result<Self, Self::Error> {
            match value {
                10 => Ok(Self::Uart),
                _ => Err(()),
            }
        }
    }

    /// interrupt cause.
    pub enum Interrupt {
        SupervisorSoftware,
        MachineSoftware,
        SupervisorTimer,
        MachineTimer,
        SupervisorExternal,
        MachineExternal,
        CounterOverflow,
    }

    impl TryFrom<usize> for Interrupt {
        type Error = ();

        fn try_from(value: usize) -> Result<Self, Self::Error> {
            match value {
                1 => Ok(Self::SupervisorSoftware),
                3 => Ok(Self::MachineSoftware),
                5 => Ok(Self::SupervisorTimer),
                7 => Ok(Self::MachineTimer),
                9 => Ok(Self::SupervisorExternal),
                11 => Ok(Self::MachineExternal),
                13 => Ok(Self::CounterOverflow),
                _ => Err(()),
            }
        }
    }

    /// exception cause.
    pub enum Exception {
        IllegalInstruction,
        Breakpoint,
        EnvCallFromUser,
        EnvCallFromSupervisor,
    }

    impl TryFrom<usize> for Exception {
        type Error = ();

        fn try_from(value: usize) -> Result<Self, Self::Error> {
            match value {
                2 => Ok(Self::IllegalInstruction),
                3 => Ok(Self::Breakpoint),
                8 => Ok(Self::EnvCallFromUser),
                9 => Ok(Self::EnvCallFromSupervisor),
                _ => Err(()),
            }
        }
    }

    /// environment call identifier.
    pub enum Ecall {
        /// set `mtimecmp`.
        MtimecmpSet,
    }

    impl TryFrom<usize> for Ecall {
        type Error = ();

        fn try_from(value: usize) -> Result<Self, Self::Error> {
            match value {
                0 => Ok(Self::MtimecmpSet),
                _ => Err(()),
            }
        }
    }
}

pub mod uart {
    use core::ffi;
    use core::ptr;

    /// universal asynchronous receiver-transmitter (UART) device registers.
    pub enum UartRegister {
        RbrThrDll,
        IerDlm,
        IirFcr,
        Lcr,
        Mcr,
        Lsr,
        Msr,
        Scr,
    }

    impl UartRegister {
        /// returns the offset from the UART device address to the register
        /// corresponding to `self`.
        pub const fn offset(self) -> usize {
            match self {
                UartRegister::RbrThrDll => 0,
                UartRegister::IerDlm => 1,
                UartRegister::IirFcr => 2,
                UartRegister::Lcr => 3,
                UartRegister::Mcr => 4,
                UartRegister::Lsr => 5,
                UartRegister::Msr => 6,
                UartRegister::Scr => 7,
            }
        }
    }

    /// reads at most `cap` bytes from the UART device into `buf`, returning the
    /// number of bytes read.
    pub fn uartread(buf: &mut [u8], cap: usize) -> usize {
        use crate::platform;

        // DLAB bit of the LCR must be logic low (i.e. zero) to acess the RBR.
        let mut lcr_ptr = platform::MMIO_ADDR_UART as *mut u8;
        lcr_ptr = lcr_ptr.wrapping_add(UartRegister::offset(UartRegister::Lcr));
        unsafe {
            let mut lcr = ptr::read_volatile(lcr_ptr);
            lcr &= 0b01111111;
            ptr::write_volatile(lcr_ptr, lcr);
        }

        // DR (i.e. data ready) bit of the LSR.
        let mut lsr_ptr = platform::MMIO_ADDR_UART as *mut u8;
        lsr_ptr = lsr_ptr.wrapping_add(UartRegister::offset(UartRegister::Lsr));
        let mut is_data_ready: u8 = unsafe { ptr::read_volatile(lsr_ptr) };
        is_data_ready &= 0b00000001;

        // while data is available and there is remaining capacity, read a character
        // from the UART device receive buffer into the given buffer.
        let mut i = 0;
        let mut rbr_ptr = platform::MMIO_ADDR_UART as *mut u8;
        rbr_ptr = rbr_ptr.wrapping_add(UartRegister::offset(UartRegister::RbrThrDll));
        let mut tmp: u8;
        while is_data_ready != 0 && i < cap {
            tmp = unsafe { ptr::read_volatile(rbr_ptr) };
            buf[i] = tmp;
            is_data_ready = unsafe { ptr::read_volatile(lsr_ptr) };
            is_data_ready &= 0b00000001;
            i += 1;
        }

        i
    }

    unsafe extern "C" {
        /// prints `s` to the UART device.
        pub fn uartprint(s: *const ffi::c_char);
        /// prints `len` bytes of `s` in hexadecimal to the UART device.
        pub fn uartprinthex(s: *const ffi::c_char, len: usize);
    }
}
