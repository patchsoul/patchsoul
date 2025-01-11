use crate::core::allocation::*;
use crate::core::array::*;
use crate::core::index::*;

use std::ops::{Deref, DerefMut};

pub type ShtickResult<T> = Result<T, ShtickError>;
pub type Shticked = ShtickResult<()>;

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub enum ShtickError {
    Allocation(AllocationError),
}

impl std::default::Default for ShtickError {
    fn default() -> Self {
        return Self::Allocation(AllocationError::OutOfMemory);
    }
}

#[repr(C, packed)]
pub struct Shtick {
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

    fn mut_count_unallocated(&mut self, new_count: Count16) {
        // Unallocated Shticks hold positive special counts
        // greater or equal to `Self::UNALLOCATED_ZERO_SPECIAL_COUNT`.
        self.special_count = Self::UNALLOCATED_ZERO_SPECIAL_COUNT + (-new_count.as_negated());
    }

    fn mut_count_allocated(&mut self, new_count: Count16) {
        // Allocated ("long") Shticks hold negative special counts.
        self.special_count = new_count.as_negated();
    }

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
                // We need to take out the allocation into its own instance because
                // we'll start overwriting bytes in `self.maybe_allocated.allocation`.
                let allocation = unsafe { std::mem::ManuallyDrop::take(allocation) };
                // The current end-Shtick is allocated, but it might have a small count.
                let new_count = self.count_allocated().min(new_capacity);
                // Ensure updating count so that when we grab the slice it's the unallocated slice.
                self.mut_count_unallocated(new_count);
                // Copy into the slice.
                self.deref_mut()
                    .copy_from_slice(allocation.as_slice(new_count));
            } else {
                // We already had an unallocated Shtick, but ensure the size gets dropped if necessary.
                let count = self.count_unallocated();
                if new_capacity < count {
                    self.mut_count_unallocated(new_capacity)
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
                    self.mut_count_allocated(new_capacity);
                }
            } else {
                // Current Shtick is unallocated.
                let current_count = self.count_unallocated();
                // Create an allocation first, move the bytes over, *then* set it into `self`,
                // otherwise we'll erase data in `self.maybe_allocated.unallocated_buffer` that we need.
                let mut allocation = Allocation16::<u8>::new();
                match allocation.mut_capacity(new_capacity) {
                    Err(e) => return Err(ShtickError::Allocation(e)),
                    _ => {}
                }
                allocation
                    .as_slice_mut(current_count)
                    .copy_from_slice(self.deref());
                self.maybe_allocated.allocation = std::mem::ManuallyDrop::new(allocation);
                // We don't need to change the `current_count`, but we do need to
                // convert it from unallocated to allocated special form.
                self.mut_count_allocated(current_count);
            }
        }
        Ok(())
    }

    fn allocation(&self) -> Option<&Allocation16<u8>> {
        if self.is_allocated() {
            let ptr = unsafe { std::ptr::addr_of!(self.maybe_allocated.allocation) };
            assert!((ptr as usize) % 8 == 0);
            Some(unsafe { &*ptr })
        } else {
            None
        }
    }

    fn allocation_mut(&mut self) -> Option<&mut std::mem::ManuallyDrop<Allocation16<u8>>> {
        if self.is_allocated() {
            let ptr = unsafe { std::ptr::addr_of_mut!(self.maybe_allocated.allocation) };
            assert!((ptr as usize) % 8 == 0);
            Some(unsafe { &mut *ptr })
        } else {
            None
        }
    }
}

impl std::ops::Deref for Shtick {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        if self.is_allocated() {
            let ptr = unsafe { std::ptr::addr_of!(self.maybe_allocated.allocation) };
            assert!((ptr as usize) % 8 == 0);
            let ptr = unsafe { &*ptr };
            ptr.as_slice(self.count_allocated())
        } else {
            let ptr = unsafe { std::ptr::addr_of!(self.maybe_allocated.unallocated_buffer[0]) };
            unsafe { std::slice::from_raw_parts(ptr, self.count_unallocated().into()) }
        }
    }
}

impl std::ops::DerefMut for Shtick {
    fn deref_mut(&mut self) -> &mut [u8] {
        if self.is_allocated() {
            let ptr = unsafe { std::ptr::addr_of!(self.maybe_allocated.allocation) };
            assert!((ptr as usize) % 8 == 0);
            let ptr = unsafe { &*ptr };
            ptr.as_slice_mut(self.count_allocated())
        } else {
            let ptr = unsafe { std::ptr::addr_of_mut!(self.maybe_allocated.unallocated_buffer[0]) };
            unsafe { std::slice::from_raw_parts_mut(ptr, self.count_unallocated().into()) }
        }
    }
}

// TODO: implement From and Into via str and u8 for Shtick.

impl Drop for Shtick {
    fn drop(&mut self) {
        self.mut_capacity(Count16::of(0));
    }
}

//impl Clone for Shtick {
//
//}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn size_of_maybe_allocated() {
        assert_eq!(std::mem::size_of::<MaybeAllocated>(), 14);
    }

    #[test]
    fn size_of_shtick() {
        assert_eq!(std::mem::size_of::<Shtick>(), 16);
    }
}
