use crate::core::allocation::*;
use crate::core::array::*;
use crate::core::index::*;

use std::ops::DerefMut;

#[repr(C, packed)]
struct Shtick {
    short_or_long: ShortOrLong,
    count: Count16,
}

#[repr(C, packed)]
union ShortOrLong {
    short_buffer: [u8; Shtick::SHORT16 as usize],
    allocation: std::mem::ManuallyDrop<Allocation16<u8>>,
}

impl Shtick {
    const SHORT16: i16 = 14;
    fn short_count() -> Count16 {
        Count16::of(Self::SHORT16)
    }

    pub fn new() -> Self {
        Self {
            short_or_long: ShortOrLong {
                short_buffer: [0; Self::SHORT16 as usize],
            },
            count: Count16::of(0),
        }
    }

    pub fn is_short(&self) -> bool {
        let count = self.count;
        count < Self::short_count()
    }

    pub fn capacity(&self) -> Count16 {
        if let Some(allocation) = self.allocation() {
            allocation.capacity()
        } else {
            Self::short_count()
        }
    }

    pub fn mut_capacity(&mut self, new_capacity: Count16) -> Arrayed {
        if new_capacity <= Self::short_count() {
            if let Some(allocation) = self.allocation_mut() {
                // We need to take out the allocation into its own instance because
                // we'll start overwriting bytes in `self.short_or_long.allocation`.
                let allocation = unsafe { std::mem::ManuallyDrop::take(allocation) };
                // Ensure updating count so that when we grab the slice it's the short slice.
                self.count = new_capacity;
                // Copy into the slice.
                self.deref_mut()
                    .copy_from_slice(allocation.as_slice(new_capacity));
            } else {
                // We already had a short Shtick, but ensure the size gets dropped if necessary.
                let count = self.count;
                if new_capacity < count {
                    self.count = new_capacity;
                }
            }
        } else {
            panic!("not implemented")
        }
        Ok(())
    }

    fn allocation(&self) -> Option<&Allocation16<u8>> {
        if self.is_short() {
            None
        } else {
            let ptr = unsafe { std::ptr::addr_of!(self.short_or_long.allocation) };
            assert!((ptr as usize) % 8 == 0);
            Some(unsafe { &*ptr })
        }
    }

    fn allocation_mut(&mut self) -> Option<&mut std::mem::ManuallyDrop<Allocation16<u8>>> {
        if self.is_short() {
            None
        } else {
            let ptr = unsafe { std::ptr::addr_of_mut!(self.short_or_long.allocation) };
            assert!((ptr as usize) % 8 == 0);
            Some(unsafe { &mut *ptr })
        }
    }
}

impl std::ops::Deref for Shtick {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        if self.is_short() {
            let ptr = unsafe { std::ptr::addr_of!(self.short_or_long.short_buffer[0]) };
            unsafe { std::slice::from_raw_parts(ptr, self.count.into()) }
        } else {
            let ptr = unsafe { std::ptr::addr_of!(self.short_or_long.allocation) };
            assert!((ptr as usize) % 8 == 0);
            let ptr = unsafe { &*ptr };
            ptr.as_slice(self.count)
        }
    }
}

impl std::ops::DerefMut for Shtick {
    fn deref_mut(&mut self) -> &mut [u8] {
        if self.is_short() {
            let ptr = unsafe { std::ptr::addr_of_mut!(self.short_or_long.short_buffer[0]) };
            unsafe { std::slice::from_raw_parts_mut(ptr, self.count.into()) }
        } else {
            let ptr = unsafe { std::ptr::addr_of!(self.short_or_long.allocation) };
            assert!((ptr as usize) % 8 == 0);
            let ptr = unsafe { &*ptr };
            ptr.as_slice_mut(self.count)
        }
    }
}

//impl Clone for Shtick {
//
//}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn size_of_short_or_long() {
        assert_eq!(std::mem::size_of::<ShortOrLong>(), 14);
    }

    #[test]
    fn size_of_shtick() {
        assert_eq!(std::mem::size_of::<Shtick>(), 16);
    }
}
