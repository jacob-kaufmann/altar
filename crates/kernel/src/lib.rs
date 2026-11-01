#![no_std]
#![deny(unsafe_op_in_unsafe_fn)]

use core::panic::PanicInfo;

pub mod trap {
    use hyperion_common::platform;
    use hyperion_common::trap;
    use hyperion_common::trap::{Exception, Interrupt, TrapFrame};
    use hyperion_common::uart::{uartprint, uartprinthex, uartread};

    /// # Safety
    ///
    /// TODO
    #[cfg(not(test))]
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn sup_traphandler(frame: *mut TrapFrame) {
        let frame = unsafe { &mut *frame };
        handler(frame);
    }

    unsafe extern "C" {
        pub fn sup_ecall_mtimecmp_set(mtimecmp: u64);
    }

    /// trap handler.
    pub fn handler(frame: &mut TrapFrame) {
        use core::ffi;
        use core::mem;

        // the highest bit of `xcause` is a flag that is set if the cause of the trap
        // was an interrupt.
        let is_interrupt = frame.xcause >> (usize::BITS - 1);
        let cause: usize = (frame.xcause << 1) >> 1;

        unsafe {
            uartprint(c"sepc: ".as_ptr());
            uartprinthex(
                (&raw const frame.xepc).cast::<ffi::c_char>(),
                mem::size_of::<usize>(),
            );
            uartprint(c"\n".as_ptr());
            uartprint(c"scause: ".as_ptr());
            uartprinthex(
                (&raw const frame.xcause).cast::<ffi::c_char>(),
                mem::size_of::<usize>(),
            );
            uartprint(c"\n".as_ptr());
            uartprint(c"stval: ".as_ptr());
            uartprinthex(
                (&raw const frame.xtval).cast::<ffi::c_char>(),
                mem::size_of::<usize>(),
            );
            uartprint(c"\n".as_ptr());
        }

        // TODO: check for fatal or non-fatal?
        //
        // TODO: profile against lookup table (i.e. LUT) and against vectored trap
        // mode as opposed to direct trap mode in `stvec`.
        if is_interrupt > 0 {
            let cause = Interrupt::try_from(cause).expect("invalid interrupt");
            int_handler(frame, cause);
        } else {
            let cause = Exception::try_from(cause).expect("invalid exception");
            exception_handler(frame, cause);
        }
    }

    /// (asynchronous) interrupt handler.
    fn int_handler(frame: &mut TrapFrame, cause: Interrupt) {
        match cause {
            Interrupt::SupervisorTimer => int_handler_timer(),
            Interrupt::SupervisorExternal => int_handler_ext(frame),
            Interrupt::MachineTimer
            | Interrupt::MachineExternal
            | Interrupt::SupervisorSoftware
            | Interrupt::MachineSoftware
            | Interrupt::CounterOverflow => {}
        }
    }

    /// (synchronous) exception handler.
    fn exception_handler(frame: &mut TrapFrame, cause: Exception) {
        match cause {
            Exception::IllegalInstruction
            | Exception::Breakpoint
            | Exception::EnvCallFromUser
            | Exception::EnvCallFromSupervisor => {}
        }

        // increment the program counter to the next instruction. RISC-V instructions
        // are fixed-width instructions.
        //
        // TODO: is there a situation where we do not want to increment the PC here?
        frame.xepc += 4;
    }

    /// timer interrupt handler. because we do not assume the Sstc extension is
    /// enabled, a supervisor timer interrupt occurs after a machine timer interrupt
    /// handler sets the STIP bit of the `mip` CSR. then, this timer interrupt
    /// handler can handle the interrupt and subsequently trap to machine mode via
    /// `ecall` to increment `mtimecmp`, arming the next timer interrupt.
    fn int_handler_timer() {
        use core::ptr;

        // NOTE: we assume that we can read `mtime` in supervisor mode based on the
        // `mcounteren` CSR.
        let mtime: *const u64 = platform::MMIO_ADDR_MTIME as *const u64;
        let now = unsafe { ptr::read_volatile(mtime) };

        // compute the time of the next tick.
        const TICK: u64 = 10000000;
        let next = now + TICK;

        unsafe {
            sup_ecall_mtimecmp_set(next);
        }
    }

    /// handles external interrupts.
    ///
    /// to service an interrupt, we transmit an interrupt claim to the PLIC in the
    /// form of a memory-mapped I/O register read. then, the PLIC atomically
    /// determines the ID of the highest priority pending interrupt for the interrupt
    /// target and clears the corresponding interrupt sources's interrupt pending
    /// bit. the PLIC returns the ID if there was a pending interrupt and zero
    /// otherwise. since there might be other (lower priority) pending interrupts,
    /// the PLIC external interrupt pending bit may not be clear after a claim. after
    /// we service the interrupt, we transmit an interrupt completion to the PLIC in
    /// the form of a memory-mapped I/O register write with the same ID returned by
    /// the PLIC.
    fn int_handler_ext(_frame: &mut TrapFrame) {
        use core::ffi;
        use core::ptr;
        use trap::PlicInterruptSource;

        let ptr = (platform::MMIO_ADDR_PLIC + 0x201004) as *mut u32;
        let id: u32 = unsafe { ptr::read_volatile(ptr) };
        let src = PlicInterruptSource::try_from(id as usize).expect("invalid interrupt source");

        match src {
            PlicInterruptSource::Uart => {
                // the interrupt source is the UART device.
                //
                // TODO: check that the interrupt corresponds to received data ready or a
                // recevied data timeout (if in FIFO mode).
                let mut buf: [u8; 64] = [0; 64];
                let n = uartread(buf.as_mut_slice(), 64);
                unsafe {
                    uartprinthex(buf.as_ptr() as *const ffi::c_char, n);
                }
            }
        }

        unsafe {
            ptr::write_volatile(ptr, id);
        }
    }

    #[cfg(test)]
    mod test {
        use super::*;

        #[repr(C)]
        struct TrapFrames {
            before: TrapFrame,
            after: TrapFrame,
        }

        #[unsafe(no_mangle)]
        extern "C" fn verify_sup_traphandler(frames: &TrapFrames) {
            // equality of integer registers.
            for (before, after) in frames.before.x.iter().zip(frames.after.x.iter()) {
                assert_eq!(before, after);
            }

            // equality of SIE bit of `sstatus` CSR.
            const SIE: usize = 0b10;
            assert_eq!(frames.before.xstatus & SIE, frames.after.xstatus & SIE);

            unsafe {
                uartprint(c"KERNEL TRAP VECTOR: PASS\n".as_ptr());
            }
        }
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    use hyperion_common::uart::uartprint;
    unsafe {
        uartprint(c"PANIC".as_ptr());
        core::ptr::write_volatile(0x00100000 as *mut u32, 0x13333);
    }
    loop {
        core::hint::spin_loop();
    }
}
