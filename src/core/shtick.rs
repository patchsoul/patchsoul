use crate::core::allocation::*;
use crate::core::array::*;
use crate::core::index::*;

#[repr(C, packed)]
struct Shtick {
    short_or_long: ShortOrLong,
    count: Count16,
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
        if let Some(allocation) = self.get_allocation() {
            allocation.capacity()
        } else {
            Self::short_count()
        }
    }

    fn get_allocation(&self) -> Option<&Allocation16<u8>> {
        if self.is_short() {
            None
        } else {
            let ptr = unsafe { std::ptr::addr_of!(self.short_or_long.allocation) };
            assert!((ptr as usize) % 8 == 0);
            Some(unsafe { &*ptr })
        }
    }

    fn get_allocation_mut(&mut self) -> Option<&mut Allocation16<u8>> {
        if self.is_short() {
            None
        } else {
            let ptr = unsafe { std::ptr::addr_of_mut!(self.short_or_long.allocation) };
            assert!((ptr as usize) % 8 == 0);
            Some(unsafe { &mut *ptr })
        }
    }
}

#[repr(C, packed)]
union ShortOrLong {
    short_buffer: [u8; Shtick::SHORT16 as usize],
    allocation: std::mem::ManuallyDrop<Allocation16<u8>>,
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
