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
// TODO: add a CountN template type.
pub struct Allocation<T> {
    capacity: Count,
    ptr: NonNull<T>,
}

impl<T> Allocation<T> {
    pub fn new() -> Self {
        Self {
            capacity: Count::of(0),
            ptr: NonNull::dangling(),
        }
    }

    pub fn capacity(&self) -> Count {
        return self.capacity;
    }

    /// Ensure that you've already dropped elements that you might delete here
    /// if the new capacity is less than the old.
    pub fn mut_capacity(&mut self, new_capacity: Count) -> Allocated {
        if new_capacity <= Count::of(0) {
            if self.capacity() > Count::of(0) {
                unsafe {
                    alloc::dealloc(self.as_ptr_mut_u8(), self.layout());
                }
                self.ptr = NonNull::dangling();
                self.capacity = Count::of(0);
            }
            return Ok(());
        } else if new_capacity == self.capacity {
            return Ok(());
        }
        let new_layout = Self::layout_of(new_capacity)?;
        let new_ptr = unsafe {
            if self.capacity == Count::of(0) {
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

    fn roughly_double_capacity(&self) -> Count {
        // TODO: determine starting_alloc based on sizeof(T), use at least 1,
        // maybe more if T is small.
        let starting_alloc = 2;
        self.capacity.double_or_max(starting_alloc)
    }

    pub fn as_ptr(&self) -> *mut T {
        assert!(self.capacity > Count::of(0));
        self.ptr.as_ptr()
    }

    fn as_ptr_mut_u8(&mut self) -> *mut u8 {
        return self.ptr.as_ptr() as *mut u8;
    }

    fn layout(&self) -> alloc::Layout {
        return Self::layout_of(self.capacity).unwrap();
    }

    fn layout_of(capacity: Count) -> AllocationResult<alloc::Layout> {
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
