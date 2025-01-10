use crate::core::index::*;

[repr(C, packed)]
struct Shtick {
    count: Count16,
    short_buffer: [u8; 6],
}

impl Shtick {
    pub fn new() -> Self {
        Self { count: 0 }
    }
}

//impl Clone for Shtick {
//
//}

