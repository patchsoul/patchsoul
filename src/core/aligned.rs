#[repr(C, align(8))]
pub struct Aligned<T>(pub T);

impl<T> Aligned<T> {
    pub fn unalign(self) -> T {
        self.0
    }
}

impl<T> std::ops::Deref for Aligned<T> {
    type Target = T;

    fn deref(&self) -> &T {
        &self.0
    }
}

impl<T> std::ops::DerefMut for Aligned<T> {
    fn deref_mut(&mut self) -> &mut T {
        &mut self.0
    }
}
