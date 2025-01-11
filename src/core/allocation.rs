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
/// You need to keep track of which elements are initialized, etc.
/// Because of that, you need to MANUALLY drop this allocation after
/// freeing any initialized elements, by calling `mut_capacity(Count::of(0))`
#[repr(C, packed)]
pub struct AllocationN<T, C: SignedPrimitive> {
    ptr: NonNull<T>,
    capacity: CountN<C>,
}

impl<T, C: SignedPrimitive> AllocationN<T, C> {
    pub fn new() -> Self {
        Self {
            ptr: NonNull::dangling(),
            capacity: CountN::<C>::of(C::zero()),
        }
    }

    pub fn capacity(&self) -> CountN<C> {
        self.capacity
    }

    /// Caller MUST ensure that they've already dropped elements that you might delete here
    /// if the new capacity is less than the old.  The old capacity will be updated
    /// iff the capacity change succeeds.
    pub fn mut_capacity(&mut self, new_capacity: CountN<C>) -> Allocated {
        // To get around alignment (and double borrowing) issues, just grab it and update it.
        let mut capacity = self.capacity;
        let result = Self::allocation_mut_capacity(new_capacity, self.as_ptr_mut(), &mut capacity);
        self.capacity = capacity;
        result
    }

    #[inline]
    pub fn allocation_mut_capacity(
        new_capacity: CountN<C>,
        ptr: &mut NonNull<T>,
        capacity: &mut CountN<C>,
    ) -> Allocated {
        if new_capacity <= CountN::<C>::of(C::zero()) {
            if *capacity > CountN::<C>::of(C::zero()) {
                unsafe {
                    alloc::dealloc(
                        ptr.as_ptr() as *mut u8,
                        Self::layout_of(*capacity).expect("already allocked"),
                    );
                }
                *ptr = NonNull::dangling();
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
                    ptr.as_ptr() as *mut u8,
                    Self::layout_of(*capacity).expect("already allocked"),
                    new_layout.size(),
                )
            }
        } as *mut T;
        match NonNull::new(new_ptr) {
            Some(new_ptr) => {
                *ptr = new_ptr;
                *capacity = new_capacity;
                return Ok(());
            }
            None => {
                return AllocationError::OutOfMemory.err();
            }
        }
    }

    /// Writes to an offset that should not be considered initialized.
    pub fn write_uninitialized(&self, offset: Offset, value: T) -> Allocated {
        Self::allocation_write_uninitialized(offset, value, &self.as_ptr(), self.capacity)
    }

    #[inline]
    pub fn allocation_write_uninitialized(
        offset: Offset,
        value: T,
        ptr: &NonNull<T>,
        capacity: CountN<C>,
    ) -> Allocated {
        if !capacity.contains(offset) {
            return AllocationError::InvalidOffset.err();
        }
        unsafe {
            ptr::write(ptr.as_ptr().add(offset as usize), value);
        }
        Ok(())
    }

    /// Reads at the offset, and from now on, that offset should be considered
    /// uninitialized.
    pub fn read_destructively(&self, offset: Offset) -> AllocationResult<T> {
        Self::allocation_read_destructively(offset, &self.as_ptr(), self.capacity)
    }

    #[inline]
    pub fn allocation_read_destructively(
        offset: Offset,
        ptr: &NonNull<T>,
        capacity: CountN<C>,
    ) -> AllocationResult<T> {
        if !capacity.contains(offset) {
            return Err(AllocationError::InvalidOffset);
        }
        Ok(unsafe { ptr::read(ptr.as_ptr().add(offset as usize)) })
    }

    pub fn grow(&mut self) -> Allocated {
        let mut capacity = self.capacity;
        let result = Self::allocation_grow(self.as_ptr_mut(), &mut capacity);
        self.capacity = capacity;
        result
    }

    #[inline]
    pub fn allocation_grow(ptr: &mut NonNull<T>, capacity: &mut CountN<C>) -> Allocated {
        let desired_capacity = Self::roughly_double_capacity(*capacity);
        if desired_capacity <= *capacity {
            return AllocationError::OutOfMemory.err();
        }
        Self::allocation_mut_capacity(desired_capacity, ptr, capacity)
    }

    fn roughly_double_capacity(capacity: CountN<C>) -> CountN<C> {
        // TODO: determine starting_alloc based on sizeof(T), use at least 1,
        // maybe more if T is small.
        let starting_alloc = 2;
        capacity.double_or_max(starting_alloc)
    }

    /// Caller is responsible for 0 to count-1 (inclusive) being initialized.
    pub fn as_slice(&self, count: CountN<C>) -> &[T] {
        Self::allocation_as_slice(self.as_ptr(), count, self.capacity)
    }

    #[inline]
    pub fn allocation_as_slice(ptr: &NonNull<T>, count: CountN<C>, capacity: CountN<C>) -> &[T] {
        assert!(count <= capacity);
        unsafe { std::slice::from_raw_parts(ptr.as_ptr(), count.into()) }
    }

    /// Caller is responsible for 0 to count-1 (inclusive) being initialized.
    pub fn as_slice_mut(&self, count: CountN<C>) -> &mut [T] {
        Self::allocation_as_slice_mut(self.as_ptr(), count, self.capacity)
    }

    #[inline]
    pub fn allocation_as_slice_mut(
        ptr: &NonNull<T>,
        count: CountN<C>,
        capacity: CountN<C>,
    ) -> &mut [T] {
        assert!(count <= capacity);
        unsafe { std::slice::from_raw_parts_mut(ptr.as_ptr(), count.into()) }
    }

    fn layout_of(capacity: CountN<C>) -> AllocationResult<alloc::Layout> {
        alloc::Layout::array::<T>(capacity.into()).or(Err(AllocationError::OutOfMemory))
    }

    fn as_ptr(&self) -> &NonNull<T> {
        let ptr = std::ptr::addr_of!(self.ptr);
        assert!((ptr as usize) % 8 == 0);
        unsafe { &*ptr }
    }

    fn as_ptr_mut(&mut self) -> &mut NonNull<T> {
        let ptr = std::ptr::addr_of_mut!(self.ptr);
        assert!((ptr as usize) % 8 == 0);
        unsafe { &mut *ptr }
    }
}

impl<T, C: SignedPrimitive> Default for AllocationN<T, C> {
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
