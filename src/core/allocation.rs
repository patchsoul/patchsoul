use crate::core::index::*;

use std::alloc;
use std::ptr::{self, NonNull};

#[derive(Eq, PartialEq, Copy, Clone, Default, Debug, Hash)]
pub enum AllocationError {
    #[default]
    OutOfMemory,
    InvalidOffset,
}

pub type AllocationResult<T> = Result<T, AllocationError>;
pub type Allocated = AllocationResult<()>;

impl AllocationError {
    pub fn err(self) -> Allocated {
        return Err(self);
    }
}

/// Low-level structure that has a pointer to contiguous memory and some capacity.
/// You need to keep track of which elements are initialized, etc.
pub type Allocation<T> = AllocationN<T, i64>;

#[repr(C)]
pub struct AllocationN<T, C: SignedPrimitive> {
    capacity: CountN<C>,
    ptr: NonNull<T>,
}

impl<T, C: SignedPrimitive> AllocationN<T, C> {
    pub fn new() -> Self {
        Self {
            capacity: CountN::<C>::default(),
            ptr: NonNull::dangling(),
        }
    }

    pub fn capacity(&self) -> CountN<C> {
        return self.capacity;
    }

    /// Ensure that you've already dropped elements that you might delete here
    /// if the new capacity is less than the old.
    pub fn mut_capacity(&mut self, new_capacity: CountN<C>) -> Allocated {
        if new_capacity <= CountN::<C>::of(C::zero()) {
            if self.capacity() > CountN::<C>::of(C::zero()) {
                unsafe {
                    alloc::dealloc(self.as_ptr_mut_u8(), self.layout());
                }
                self.ptr = NonNull::dangling();
                self.capacity = CountN::<C>::of(C::zero());
            }
            return Ok(());
        } else if new_capacity == self.capacity {
            return Ok(());
        }
        let new_layout = Self::layout_of(new_capacity)?;
        let new_ptr = unsafe {
            if self.capacity == CountN::<C>::of(C::zero()) {
                alloc::alloc(new_layout)
            } else {
                alloc::realloc(self.as_ptr_mut_u8(), self.layout(), new_layout.size())
            }
        } as *mut T;
        match NonNull::new(new_ptr) {
            Some(new_ptr) => {
                self.ptr = new_ptr;
                self.capacity = new_capacity;
                return Ok(());
            }
            None => {
                return AllocationError::OutOfMemory.err();
            }
        }
    }

    /// Writes to an offset that should not be considered initialized.
    pub fn write_uninitialized(&mut self, offset: Offset, value: T) -> Allocated {
        if !self.capacity.contains(offset) {
            return AllocationError::InvalidOffset.err();
        }
        unsafe {
            ptr::write(self.ptr.as_ptr().add(offset as usize), value);
        }
        Ok(())
    }

    /// Reads at the offset, and from now on, that offset should be considered
    /// uninitialized.
    pub fn read_destructively(&self, offset: Offset) -> AllocationResult<T> {
        if !self.capacity.contains(offset) {
            return Err(AllocationError::InvalidOffset);
        }
        Ok(unsafe { ptr::read(self.ptr.as_ptr().add(offset as usize)) })
    }

    pub fn grow(&mut self) -> Allocated {
        let desired_capacity = self.roughly_double_capacity();
        if desired_capacity <= self.capacity {
            return AllocationError::OutOfMemory.err();
        }
        self.mut_capacity(desired_capacity)
    }

    fn roughly_double_capacity(&self) -> CountN<C> {
        // TODO: determine starting_alloc based on sizeof(T), use at least 1,
        // maybe more if T is small.
        let starting_alloc = 2;
        self.capacity.double_or_max(starting_alloc)
    }

    pub fn as_ptr(&self) -> *mut T {
        assert!(self.capacity > CountN::<C>::of(C::zero()));
        self.ptr.as_ptr()
    }

    fn as_ptr_mut_u8(&mut self) -> *mut u8 {
        return self.ptr.as_ptr() as *mut u8;
    }

    fn layout(&self) -> alloc::Layout {
        return Self::layout_of(self.capacity).unwrap();
    }

    fn layout_of(capacity: CountN<C>) -> AllocationResult<alloc::Layout> {
        alloc::Layout::array::<T>(capacity.into()).or(Err(AllocationError::OutOfMemory))
    }

    // TODO: something like to_ptr and from_ptr, for Shtick functionality
}

impl<T> Default for Allocation<T> {
    fn default() -> Self {
        return Self::new();
    }
}

unsafe impl<T: Send> Send for Allocation<T> {}
unsafe impl<T: Sync> Sync for Allocation<T> {}

#[cfg(test)]
mod test {
    use super::*;
}
