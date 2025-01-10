use crate::core::index::*;

use std::alloc;
use std::marker::PhantomData;
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

pub type Allocation<T> = AllocationN<T, i64>;
pub type Allocation64<T> = Allocation<T>;
pub type Allocation32<T> = AllocationN<T, i32>;
pub type Allocation16<T> = AllocationN<T, i16>;
pub type Allocation8<T> = AllocationN<T, i8>;

/// Low-level structure that has a pointer to contiguous memory.
/// You need to keep track of which elements are initialized, etc.,
/// as well as the capacity as `CountN<C>`.
pub struct AllocationN<T, C: SignedPrimitive> {
    count_type: PhantomData<C>,
    ptr: NonNull<T>,
}

impl<T, C: SignedPrimitive> AllocationN<T, C> {
    pub fn new() -> Self {
        Self {
            count_type: PhantomData,
            ptr: NonNull::dangling(),
        }
    }

    /// Ensure that you've already dropped elements that you might delete here
    /// if the new capacity is less than the old.  The old capacity will be updated
    /// iff the capacity change succeeds.
    pub fn mut_capacity(&mut self, capacity: &mut CountN<C>, new_capacity: CountN<C>) -> Allocated {
        if new_capacity <= CountN::<C>::of(C::zero()) {
            if *capacity > CountN::<C>::of(C::zero()) {
                unsafe {
                    alloc::dealloc(
                        self.as_ptr_mut_u8(),
                        Self::layout_of(*capacity).expect("already allocked"),
                    );
                }
                self.ptr = NonNull::dangling();
                *capacity = CountN::<C>::of(C::zero());
            }
            return Ok(());
        } else if new_capacity == *capacity {
            return Ok(());
        }
        let new_layout = Self::layout_of(new_capacity)?;
        let new_ptr = unsafe {
            if *capacity == CountN::<C>::of(C::zero()) {
                alloc::alloc(new_layout)
            } else {
                alloc::realloc(
                    self.as_ptr_mut_u8(),
                    Self::layout_of(*capacity).expect("already allocked"),
                    new_layout.size(),
                )
            }
        } as *mut T;
        match NonNull::new(new_ptr) {
            Some(new_ptr) => {
                self.ptr = new_ptr;
                *capacity = new_capacity;
                return Ok(());
            }
            None => {
                return AllocationError::OutOfMemory.err();
            }
        }
    }

    /// Writes to an offset that should not be considered initialized.
    pub fn write_uninitialized(
        &mut self,
        value: T,
        offset: Offset,
        capacity: CountN<C>,
    ) -> Allocated {
        if !capacity.contains(offset) {
            return AllocationError::InvalidOffset.err();
        }
        unsafe {
            ptr::write(self.ptr.as_ptr().add(offset as usize), value);
        }
        Ok(())
    }

    /// Reads at the offset, and from now on, that offset should be considered
    /// uninitialized.
    pub fn read_destructively(&self, offset: Offset, capacity: CountN<C>) -> AllocationResult<T> {
        if !capacity.contains(offset) {
            return Err(AllocationError::InvalidOffset);
        }
        Ok(unsafe { ptr::read(self.ptr.as_ptr().add(offset as usize)) })
    }

    pub fn grow(&mut self, capacity: &mut CountN<C>) -> Allocated {
        let desired_capacity = self.roughly_double_capacity(*capacity);
        if desired_capacity <= *capacity {
            return AllocationError::OutOfMemory.err();
        }
        self.mut_capacity(capacity, desired_capacity)
    }

    fn roughly_double_capacity(&self, capacity: CountN<C>) -> CountN<C> {
        // TODO: determine starting_alloc based on sizeof(T), use at least 1,
        // maybe more if T is small.
        let starting_alloc = 2;
        capacity.double_or_max(starting_alloc)
    }

    /// Caller is responsible for 0 to count-1 (inclusive) being initialized.
    pub fn as_slice(&self, count: CountN<C>, capacity: CountN<C>) -> &[T] {
        assert!(count <= capacity);
        unsafe { std::slice::from_raw_parts(self.ptr.as_ptr(), count.into()) }
    }

    /// Caller is responsible for 0 to count-1 (inclusive) being initialized.
    pub fn as_slice_mut(&self, count: CountN<C>, capacity: CountN<C>) -> &mut [T] {
        assert!(count <= capacity);
        unsafe { std::slice::from_raw_parts_mut(self.ptr.as_ptr(), count.into()) }
    }

    /// Caller is responsible for capacity being > 0
    fn as_ptr_mut_u8(&mut self) -> *mut u8 {
        return self.ptr.as_ptr() as *mut u8;
    }

    fn layout_of(capacity: CountN<C>) -> AllocationResult<alloc::Layout> {
        alloc::Layout::array::<T>(capacity.into()).or(Err(AllocationError::OutOfMemory))
    }
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
