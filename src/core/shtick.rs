[repr(C, packed)]
struct Shtick {
    count: u16,
    short_buffer: [u8; 14],
}

impl Shtick {
    pub fn new() -> Self {
        Self { count: 0 }
    }
}

//impl Clone for Shtick {
//
//}

