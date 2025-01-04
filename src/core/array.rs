use crate::core::index::*;

use std::alloc;
use std::ptr::{self, NonNull};

pub struct Array<T: std::default::Default> {
    ptr: NonNull<T>,
    capacity: Count,
    count: Count,
}

// TODO: implement #[derive(Eq, PartialEq, Clone, Debug, Hash)]
impl<T: std::default::Default> Array<T> {
    pub fn new() -> Self {
        Self {
            ptr: NonNull::dangling(),
            capacity: Count(0),
            count: Count(0),
        }
    }

    // TODO: this should be a Countable Trait
    pub fn count(&self) -> Count {
        return self.count;
    }

    // TODO: this should be a Countable Trait
    pub fn mut_count(&mut self, new_count: Count) -> Arrayed {
        if new_count.0 < self.count.0 {
            while self.count.0 > new_count.0 {
                _ = self.pop_last();
            }
        } else if new_count.0 > self.count.0 {
            if new_count.0 > self.capacity.0 {
                self.mut_capacity(new_count)?;
            }
            while self.count.0 < new_count.0 {
                self.push(Default::default())
                    .expect("already allocated enough above");
            }
        }
        return Ok(());
    }

    pub fn push(&mut self, value: T) -> Arrayed {
        if self.capacity == self.count {
            self.grow()?;
        }
        unsafe {
            ptr::write(self.ptr.as_ptr().add(self.count.0 as usize), value);
        }
        self.count.0 += 1;
        return Ok(());
    }

    // TODO: add an `enum Pop {Last, First, Index(Index)}` argument to a new `pop` method.
    pub fn pop_last(&mut self) -> Option<T> {
        if self.count.0 <= 0 {
            return None;
        }
        self.count.0 -= 1;
        unsafe {
            return Some(ptr::read(self.ptr.as_ptr().add(self.count.0 as usize)));
        }
    }

    pub fn clear(&mut self) {
        // We could optimize this but we do need Rust to deallocate the individual
        // elements, so we can't just dealloc the `ptr` itself.
        while let Some(_) = self.pop_last() {}
    }

    fn as_ptr_mut_u8(&mut self) -> *mut u8 {
        return self.ptr.as_ptr() as *mut u8;
    }

    fn layout(&self) -> alloc::Layout {
        return Self::layout_of(self.capacity).unwrap();
    }

    fn layout_of(capacity: Count) -> ArrayResult<alloc::Layout> {
        alloc::Layout::array::<T>(capacity.0 as usize).or(Err(ArrayError::OutOfMemory))
    }

    fn grow(&mut self) -> Arrayed {
        let desired_capacity = self.roughly_double_capacity();
        if desired_capacity.0 <= self.capacity.0 {
            return ArrayError::OutOfMemory.err();
        }
        self.mut_capacity(desired_capacity)
    }

    fn roughly_double_capacity(&self) -> Count {
        // TODO: determine starting_alloc based on sizeof(T), use at least 1,
        // maybe more if T is small.
        let starting_alloc = 2;
        self.capacity.double_or_max(starting_alloc)
    }

    fn reset(&mut self) {
        if self.capacity.0 > 0 {
            self.clear();
            unsafe {
                alloc::dealloc(self.as_ptr_mut_u8(), self.layout());
            }
            self.ptr = NonNull::dangling();
            self.capacity = Count(0);
        }
    }

    /// Will reallocate to exactly this capacity, prefer `grow()`.
    /// Will delete items if `new_capacity < self.count()`
    fn mut_capacity(&mut self, new_capacity: Count) -> Arrayed {
        if new_capacity.0 == self.capacity.0 {
            return Ok(());
        } else if new_capacity.0 <= 0 {
            self.reset();
        } else if new_capacity.0 < self.count.0 {
            while self.count.0 > new_capacity.0 {
                _ = self.pop_last();
            }
            // fall through
        } else {
            // new_capacity != self.capacity
            // fall through
        }
        let new_layout = Self::layout_of(new_capacity)?;
        let new_ptr = unsafe {
            alloc::realloc(self.as_ptr_mut_u8(), self.layout(), new_layout.size()) as *mut T
        };
        match NonNull::new(new_ptr) {
            Some(new_ptr) => {
                self.ptr = new_ptr;
                self.capacity = new_capacity;
                return Ok(());
            }
            None => {
                return ArrayError::OutOfMemory.err();
            }
        }
    }
}

impl<T: std::default::Default> Default for Array<T> {
    fn default() -> Self {
        return Self::new();
    }
}

impl<T: std::default::Default> Drop for Array<T> {
    fn drop(&mut self) {
        self.reset();
    }
}

#[derive(Eq, PartialEq, Copy, Clone, Default, Debug, Hash)]
pub enum ArrayError {
    #[default]
    OutOfMemory,
    InvalidCount,
}

pub type ArrayResult<T> = Result<T, ArrayError>;
pub type Arrayed = ArrayResult<()>;

impl ArrayError {
    pub fn err(self) -> Arrayed {
        return Err(self);
    }
}

unsafe impl<T: Send + std::default::Default> Send for Array<T> {}
unsafe impl<T: Sync + std::default::Default> Sync for Array<T> {}

#[derive(Eq, PartialEq, Copy, Clone, Debug, Default, Hash)]
pub enum Pop {
    #[default]
    Last,
    First,
    Index(Index),
}

#[derive(Eq, PartialEq, Copy, Clone, Debug, Default, Hash)]
pub enum Sort {
    #[default]
    Default,
}