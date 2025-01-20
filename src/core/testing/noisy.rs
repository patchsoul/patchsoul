use crate::core::array::*;
use crate::core::shtick::*;

thread_local! {
    static NOISE: RefCell<Array<Shtick>> = RefCell::new(Array::new());
}

pub fn noise() -> Array<Shtick> {
    NOISE.replace(Array::new())
}

pub fn add_noise(shtick: Shtick) {
    let borrow = NOISE.borrow_mut();
    *borrow.push(shtick);
}


pub struct Noisy {
    value: u8,
}

impl Noisy {
    pub fn new(value: u8) -> Self {
        let mut shtick = Shtick::new();
        write!(&mut shtick, "Noisy+({})", value).expect("<=3");
        add_noise(shtick);
        Self { value }
    }
}

impl<T: std::default::Default> Default for Noisy {
    fn default() -> Self {
        return Self::new(0);
    }
}

impl<T> Drop for Noisy<T> {
    fn drop(&mut self) {
        let mut shtick = Shtick::new();
        write!(&mut shtick, "Noisy-({})", self.value).expect("<=3");
        add_noise(shtick);
    }
}
