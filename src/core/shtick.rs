use crate::core::aligned::*;
use crate::core::allocation::*;
use crate::core::array::*;
use crate::core::index::*;

use std::ops::{Deref, DerefMut};

pub type ShtickResult<T> = Result<T, ShtickError>;
pub type Shticked = ShtickResult<()>;

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub enum ShtickError {
    /// Shticks can only be up to 2**15 bytes in size.
    TooLarge,
    Allocation(AllocationError),
}

impl std::default::Default for ShtickError {
    fn default() -> Self {
        return Self::Allocation(AllocationError::OutOfMemory);
    }
}

// TODO: add Shtick16 (what we are here), i16, taking up 16 bytes
// TODO: Shtick32 (with i32 and 20 bytes of local storage), taking up 24 bytes
// TODO: Shtick64 (with i64 and 24 bytes of local storage), taking up 32 bytes
#[repr(C, align(8))]
pub struct Shtick {
    /// Invariants:
    ///   * If allocated, then `maybe_allocated.allocation.capacity() > Self::unallocated_max_count()`
    /// Not invariants:
    ///   * If allocated, `Shtick.count()` can be less than `Self::unallocated_max_count()`.
    ///     This is to ensure that we can increase capacity and *then* increase the size of the `Shtick`.
    ///     We do this using `special_count` to distinguish between allocated/unallocated.
    maybe_allocated: MaybeAllocated,
    /// If positive, then it's a unallocated string, with actual count as `special_count - 1`.
    /// If negative, then it's a allocated string with count as `-special_count`.
    special_count: i16,
}

#[repr(C, packed)]
union MaybeAllocated {
    /// No heap allocations, just a buffer.
    unallocated_buffer: [u8; Shtick::SHORT16 as usize],
    /// Heap allocation, pointer to a buffer.
    allocation: std::mem::ManuallyDrop<Allocation16<u8>>,
}

impl Shtick {
    const SHORT16: i16 = 14;
    /// We have an offset to ensure we can distinguish
    /// an unallocated Shtick from an allocated one.
    /// See documentation on `special_count`.
    const UNALLOCATED_ZERO_SPECIAL_COUNT: i16 = 1;

    fn unallocated_max_count() -> Count16 {
        Count16::of(Self::SHORT16)
    }

    pub fn new() -> Self {
        Self {
            maybe_allocated: MaybeAllocated {
                unallocated_buffer: [0; Self::SHORT16 as usize],
            },
            special_count: Self::UNALLOCATED_ZERO_SPECIAL_COUNT,
        }
    }

    /// Returns a Shtick from this string or panics.
    /// Caller should ensure that the string is small enough to fit in a Shtick.
    pub fn or_die(string: &str) -> Self {
        Self::try_from(string).expect("Shtick::or_die died")
    }

    pub fn is_allocated(&self) -> bool {
        let special_count = self.special_count;
        if special_count < Self::UNALLOCATED_ZERO_SPECIAL_COUNT {
            true
        } else {
            assert!(special_count - Self::UNALLOCATED_ZERO_SPECIAL_COUNT <= Self::SHORT16);
            false
        }
    }

    pub fn is_unallocated(&self) -> bool {
        !self.is_allocated()
    }

    pub fn as_slice(&self) -> &[u8] {
        if self.is_allocated() {
            let ptr = unsafe { std::ptr::addr_of!(self.maybe_allocated.allocation) };
            let ptr = unsafe { &*ptr };
            ptr.as_slice(self.count_allocated())
        } else {
            let ptr = unsafe { std::ptr::addr_of!(self.maybe_allocated.unallocated_buffer[0]) };
            unsafe { std::slice::from_raw_parts(ptr, self.count_unallocated().into()) }
        }
    }

    pub fn as_slice_mut(&mut self) -> &mut [u8] {
        if self.is_allocated() {
            let ptr = unsafe { std::ptr::addr_of!(self.maybe_allocated.allocation) };
            let ptr = unsafe { &*ptr };
            ptr.as_slice_mut(self.count_allocated())
        } else {
            let ptr = unsafe { std::ptr::addr_of_mut!(self.maybe_allocated.unallocated_buffer[0]) };
            unsafe { std::slice::from_raw_parts_mut(ptr, self.count_unallocated().into()) }
        }
    }

    /// Returns the number of bytes in this Shtick.
    pub fn count(&self) -> Count16 {
        let special_count = self.special_count;
        if special_count >= Self::UNALLOCATED_ZERO_SPECIAL_COUNT {
            Count16::of(special_count - Self::UNALLOCATED_ZERO_SPECIAL_COUNT)
        } else {
            Count16::negated(special_count)
        }
    }

    #[inline]
    fn count_unallocated(&self) -> Count16 {
        let special_count = self.special_count;
        assert!(special_count >= Self::UNALLOCATED_ZERO_SPECIAL_COUNT);
        Count16::of(special_count - Self::UNALLOCATED_ZERO_SPECIAL_COUNT)
    }

    #[inline]
    fn count_allocated(&self) -> Count16 {
        let special_count = self.special_count;
        assert!(special_count <= 0);
        Count16::negated(special_count)
    }

    /// Doesn't zero bytes if the count is getting larger, just mutates `count`.
    /// WARNING: this does not check if we were unallocated.
    /// Caller needs to ensure that we DON'T have an allocation.
    #[inline]
    fn mut_count_unchecked_unallocated(&mut self, new_count: Count16) {
        // Unallocated Shticks hold positive special counts
        // greater or equal to `Self::UNALLOCATED_ZERO_SPECIAL_COUNT`.
        self.special_count = Self::UNALLOCATED_ZERO_SPECIAL_COUNT + (-new_count.as_negated());
    }

    /// Doesn't zero bytes if the count is getting larger, just mutates `count`.
    /// WARNING: this does not check if we were allocated.
    /// Caller needs to ensure that we do have an allocation.
    #[inline]
    fn mut_count_unchecked_allocated(&mut self, new_count: Count16) {
        // Allocated ("long") Shticks hold negative special counts.
        self.special_count = new_count.as_negated();
    }

    // TODO: `pub fn mut_count(&mut self, new_count: Count16)` should fill larger space with zeros.

    /// Returns the number of bytes that are available to this Shtick.
    pub fn capacity(&self) -> Count16 {
        if let Some(allocation) = self.allocation() {
            allocation.capacity()
        } else {
            Self::unallocated_max_count()
        }
    }

    /// Will truncate `self.count` to `new_capacity` if the new capacity is smaller.
    pub fn mut_capacity(&mut self, new_capacity: Count16) -> Shticked {
        if new_capacity <= Self::unallocated_max_count() {
            // The desired end-Shtick is unallocated.
            if let Some(allocation) = self.allocation_mut() {
                // The current Shtick is allocated...
                // We need to take out the allocation into its own instance because
                // we'll start overwriting bytes in `self.maybe_allocated.allocation`
                // if we try to write to `self.maybe_allocated.unallocated_buffer`.
                let allocation = Aligned(unsafe { std::mem::ManuallyDrop::take(allocation) });
                // The current end-Shtick is allocated, but it might have a small count.
                let new_count = self.count_allocated().min(new_capacity);
                // Ensure updating count so that when we grab the slice it's the unallocated slice.
                self.mut_count_unchecked_unallocated(new_count);
                // Copy into the slice.
                self.deref_mut()
                    .copy_from_slice(allocation.as_slice(new_count));
            } else {
                // We already had an unallocated Shtick, but ensure the size gets dropped if necessary.
                let count = self.count_unallocated();
                if new_capacity < count {
                    self.mut_count_unchecked_unallocated(new_capacity)
                }
            }
        } else {
            // The desired end-Shtick is allocated.
            if let Some(allocation) = self.allocation_mut() {
                // The current Shtick is allocated as well.
                match allocation.mut_capacity(new_capacity) {
                    Err(e) => return Err(ShtickError::Allocation(e)),
                    _ => {}
                }
                // Ensure the size gets dropped if necessary.
                let count = self.count_allocated();
                if new_capacity < count {
                    self.mut_count_unchecked_allocated(new_capacity);
                }
            } else {
                // Current Shtick is unallocated.
                let current_count = self.count_unallocated();
                // Create an allocation first, move the bytes over, *then* set it into `self`,
                // otherwise we'll erase data in `self.maybe_allocated.unallocated_buffer` that we need.
                let mut allocation = Aligned(Allocation16::<u8>::new());
                match allocation.mut_capacity(new_capacity) {
                    Err(e) => return Err(ShtickError::Allocation(e)),
                    _ => {}
                }
                allocation
                    .as_slice_mut(current_count)
                    .copy_from_slice(self.deref());
                self.maybe_allocated.allocation = std::mem::ManuallyDrop::new(allocation.unalign());
                // We don't need to change the `current_count`, but we do need to
                // convert it from unallocated to allocated special form.
                self.mut_count_unchecked_allocated(current_count);
            }
        }
        Ok(())
    }

    fn allocation(&self) -> Option<&Allocation16<u8>> {
        if self.is_allocated() {
            let ptr = unsafe { std::ptr::addr_of!(self.maybe_allocated.allocation) };
            assert_eq!((ptr as usize) % 8, 0);
            Some(unsafe { &*ptr })
        } else {
            None
        }
    }

    fn allocation_mut(&mut self) -> Option<&mut std::mem::ManuallyDrop<Allocation16<u8>>> {
        if self.is_allocated() {
            let ptr = unsafe { std::ptr::addr_of_mut!(self.maybe_allocated.allocation) };
            assert_eq!((ptr as usize) % 8, 0);
            Some(unsafe { &mut *ptr })
        } else {
            None
        }
    }
}

impl std::ops::Deref for Shtick {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        self.as_slice()
    }
}

impl std::ops::DerefMut for Shtick {
    fn deref_mut(&mut self) -> &mut [u8] {
        self.as_slice_mut()
    }
}

impl TryFrom<&str> for Shtick {
    type Error = ShtickError;
    fn try_from(string: &str) -> Result<Self, Self::Error> {
        Shtick::try_from(string.as_bytes())
    }
}

impl TryFrom<&[u8]> for Shtick {
    type Error = ShtickError;
    fn try_from(bytes: &[u8]) -> Result<Self, Self::Error> {
        let mut shtick = Shtick::new();
        let count = Count16::from_usize(bytes.len()).map_err(|_e| ShtickError::TooLarge)?;
        shtick.mut_capacity(count)?;
        if shtick.is_allocated() {
            shtick.mut_count_unchecked_allocated(count);
        } else {
            shtick.mut_count_unchecked_unallocated(count);
        }
        shtick.as_slice_mut().copy_from_slice(bytes);
        Ok(shtick)
    }
}

impl std::fmt::Display for Shtick {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}", unsafe {
            std::str::from_utf8_unchecked(self.as_slice())
        })
    }
}

impl std::fmt::Debug for Shtick {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "Shtick::or_die(\"{}\")", unsafe {
            std::str::from_utf8_unchecked(self.as_slice())
        })
    }
}

impl Drop for Shtick {
    fn drop(&mut self) {
        if let Some(allocation) = self.allocation_mut() {
            let mut allocation = Aligned(unsafe { std::mem::ManuallyDrop::take(allocation) });
            allocation
                .mut_capacity(Count16::of(0))
                .expect("should be able to dealloc");
        }
        // Not really needed for a drop but useful for a move-reset.
        self.mut_count_unchecked_unallocated(Count16::of(0));
    }
}

//impl Clone for Shtick {
//
//}

#[cfg(test)]
mod test {
    use super::*;

    use arrayvec::ArrayVec;
    use std::io::Write;

    #[test]
    fn size_of_maybe_allocated() {
        assert_eq!(std::mem::size_of::<MaybeAllocated>(), 14);
    }

    #[test]
    fn size_of_shtick() {
        assert_eq!(std::mem::size_of::<Shtick>(), 16);
    }

    #[test]
    fn shtick_internal_offsets() {
        let shtick = Shtick::new();
        let shtick_ptr = std::ptr::addr_of!(shtick);
        let maybe_ptr = std::ptr::addr_of!(shtick.maybe_allocated);
        let allocation_ptr = unsafe { std::ptr::addr_of!(shtick.maybe_allocated.allocation) };
        let buffer_ptr = unsafe { std::ptr::addr_of!(shtick.maybe_allocated.unallocated_buffer) };
        assert_eq!(buffer_ptr as usize, shtick_ptr as usize);
        assert_eq!(maybe_ptr as usize, shtick_ptr as usize);
        assert_eq!(allocation_ptr as usize, shtick_ptr as usize);
        assert_eq!((allocation_ptr as usize) % 8, 0);
    }

    #[test]
    fn print_pretty() {
        try_pretty_print("");
        try_pretty_print("short");
        try_pretty_print("hello, world");
        try_pretty_print("exact fourteen");
        try_pretty_print("exactly fifteen");
        try_pretty_print("this is getting longer");
        try_pretty_print("watch out for the edge oh no don't fall off the edge");
    }

    #[test]
    fn print_debug() {
        try_debug_print("", "Shtick::or_die(\"\")");
        try_debug_print("asdf", "Shtick::or_die(\"asdf\")");
        try_debug_print("exact fourteen", "Shtick::or_die(\"exact fourteen\")");
        try_debug_print("exactly fifteen", "Shtick::or_die(\"exactly fifteen\")");
        try_debug_print(
            "this is getting longer",
            "Shtick::or_die(\"this is getting longer\")",
        );
    }

    /// String should not be larger than 128 bytes.
    fn try_pretty_print(string: &str) {
        eprintln!("testing string: \"{}\"", string);
        let shtick = Shtick::or_die(string);
        let mut buf = ArrayVec::<u8, 128>::new();
        write!(buf, "{}", shtick).expect("ok");
        assert_eq!(
            unsafe { std::str::from_utf8_unchecked(buf.deref()) },
            string,
        );
        eprintln!("done string: \"{}\"", string);
    }

    /// String should not be larger than 110 bytes.
    fn try_debug_print(string: &str, debug_string: &str) {
        eprintln!("testing debug: \"{}\"", string);
        let shtick = Shtick::or_die(string);
        let mut buf = ArrayVec::<u8, 128>::new();
        write!(buf, "{:?}", shtick).expect("ok");
        assert_eq!(
            unsafe { std::str::from_utf8_unchecked(buf.deref()) },
            debug_string,
        );
        eprintln!("done debug: \"{}\"", string);
    }
}
