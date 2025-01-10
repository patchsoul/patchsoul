use crate::core::allocation::*;
use crate::core::index::*;

#[repr(C, packed)]
struct Shtick {
    count: Count16,
    short_or_long: ShortOrLong,
}

impl Shtick {
    const SHORT16: i16 = 14;
    pub const SHORT_COUNT: Count16 = Count16::of(Self::SHORT16);

    pub fn new() -> Self {
        Self {
            count: Count16::of(0),
            short_buffer_start: [u8; Shtick::SHORT16 as usize],
            short_or_long: ShortOrLong {
                short_buffer: [0; Self::SHORT16 as usize],
            },
        }
    }

    pub fn is_short(&self) -> bool {
        self.count < Self::SHORT_COUNT
    }

    pub fn capacity(&self) -> Count16 {
        if let Some(allocation) = self.get_allocation() {
            allocation.capacity()
        } else {
            Self::SHORT_COUNT
        }
    }

    fn get_allocation(&self) -> Option<&Allocation16<u8>> {
        if self.is_short() {
            None
        } else {
            Some(unsafe { &self.short_or_long.allocation })
        }
    }

    fn get_allocation_mut(&mut self) -> Option<&mut Allocation16<u8>> {
        if self.is_short() {
            None
        } else {
            Some(unsafe { &mut self.short_or_long.allocation })
        }
    }
}

union ShortOrLong {
    short_buffer_continued: [u8; Shtick::SHORT16 as usize],
    allocation: std::mem::ManuallyDrop<Allocation16<u8>>,
}

//impl Clone for Shtick {
//
//}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn size_of_shtick() {
        assert_eq!(std::mem::size_of::<Shtick>(), 16);
    }
}
