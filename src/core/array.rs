use crate::core::allocation::*;
use crate::core::index::*;

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub enum ArrayError {
    Allocation(AllocationError),
    InvalidCount,
}

impl std::default::Default for ArrayError {
    fn default() -> Self {
        return ArrayError::Allocation(AllocationError::OutOfMemory);
    }
}

pub type ArrayResult<T> = Result<T, ArrayError>;
pub type Arrayed = ArrayResult<()>;

impl ArrayError {
    pub fn err(self) -> Arrayed {
        return Err(self);
    }
}

// TODO: make an option to use a smaller `Count`, and even like Allocation
// to have a `&mut count` somewhere else, e.g., for Shtick's.
// probably want some `array_push` and `array_pop`-like functions for the generic case,
// which are used inside `Array.push`, etc.
pub struct Array<T> {
    count: Count,
    capacity: Count,
    allocation: Allocation<T>,
}

// TODO: implement #[derive(Clone, Debug, Hash)]
impl<T> Array<T> {
    pub fn new() -> Self {
        Self {
            count: Count::of(0),
            capacity: Count::of(0),
            allocation: Allocation::new(),
        }
    }

    // TODO: this should be a Countable Trait
    pub fn count(&self) -> Count {
        return self.count;
    }

    pub fn push(&mut self, value: T) -> Arrayed {
        if self.capacity == self.count {
            self.grow()?;
        }
        self.count += 1;
        self.allocation
            .write_uninitialized(value, self.count.max_offset(), self.capacity)
            .expect("should be in bounds");
        return Ok(());
    }

    // TODO: add an `enum Pop {Last, First, Index(Index)}` argument to a new `pop` method.
    pub fn pop_last(&mut self) -> Option<T> {
        if self.count <= Count::of(0) {
            return None;
        }
        let result = Some(
            self.allocation
                .read_destructively(self.count.max_offset(), self.capacity)
                .expect("should be in bounds"),
        );
        self.count -= 1;
        result
    }

    pub fn clear(&mut self, options: Clear) {
        // We could optimize this but we do need Rust to drop each individual
        // element (if necessary), so we can't just dealloc the `ptr` itself.
        while let Some(_) = self.pop_last() {}

        assert!(self.count == Count::of(0));

        match options {
            Clear::KeepCapacity => {}
            Clear::DropCapacity => self
                .mut_capacity(Count::of(0))
                .expect("clearing should not alloc"),
        }
    }

    pub fn capacity(&self) -> Count {
        return self.capacity;
    }

    /// Will reallocate to exactly this capacity.
    /// Will delete items if `new_capacity < self.count()`
    pub fn mut_capacity(&mut self, new_capacity: Count) -> Arrayed {
        if new_capacity == self.capacity() {
            return Ok(());
        }
        while self.count > new_capacity {
            if self.pop_last().is_none() {
                // Could happen if new_capacity < 0
                break;
            }
        }
        self.allocation
            .mut_capacity(&mut self.capacity, new_capacity)
            .map_err(|e| ArrayError::Allocation(e))
    }

    fn grow(&mut self) -> Arrayed {
        self.allocation
            .grow(&mut self.capacity)
            .map_err(|e| ArrayError::Allocation(e))
    }
}

impl<T: std::default::Default> Array<T> {
    // TODO: this should be a Countable Trait
    pub fn mut_count(&mut self, new_count: Count) -> Arrayed {
        if new_count < self.count {
            while self.count > new_count {
                _ = self.pop_last();
            }
        } else if new_count > self.count {
            if new_count > self.capacity {
                self.mut_capacity(new_count)?;
            }
            while self.count < new_count {
                self.push(Default::default())
                    .expect("already allocated enough above");
            }
        }
        return Ok(());
    }
}

impl<T> std::ops::Deref for Array<T> {
    type Target = [T];
    fn deref(&self) -> &[T] {
        self.allocation.as_slice(self.count, self.capacity)
    }
}

impl<T> std::ops::DerefMut for Array<T> {
    fn deref_mut(&mut self) -> &mut [T] {
        self.allocation.as_slice_mut(self.count, self.capacity)
    }
}

impl<T: std::cmp::PartialEq> PartialEq<Self> for Array<T> {
    fn eq(&self, other: &Self) -> bool {
        if self.count != other.count {
            return false;
        }
        for i in 0..=self.count.max_offset() {
            let i = i as usize;
            if self[i] != other[i] {
                return false;
            }
        }
        return true;
    }
}

impl<T: std::cmp::Eq> Eq for Array<T> {}

impl<T> Default for Array<T> {
    fn default() -> Self {
        return Self::new();
    }
}

impl<T> Drop for Array<T> {
    fn drop(&mut self) {
        self.clear(Clear::DropCapacity);
    }
}

unsafe impl<T: Send> Send for Array<T> {}
unsafe impl<T: Sync> Sync for Array<T> {}

#[derive(Eq, PartialEq, Copy, Clone, Debug, Default, Hash)]
pub enum Clear {
    #[default]
    KeepCapacity,
    DropCapacity,
}

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

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn push_and_pop() {
        let mut array = Array::<u32>::new();
        array.mut_capacity(Count::of(3)).expect("small alloc");
        array.push(1).expect("already allocked");
        array.push(2).expect("already allocked");
        array.push(3).expect("already allocked");
        assert_eq!(array.count(), Count::of(3));
        assert_eq!(array.pop_last(), Some(3));
        assert_eq!(array.pop_last(), Some(2));
        assert_eq!(array.pop_last(), Some(1));
        assert_eq!(array.count(), Count::of(0));
        assert_eq!(array.capacity(), Count::of(3));
    }

    #[test]
    fn mut_count_supplies_defaults() {
        let mut array = Array::<u32>::new();
        array.mut_count(Count::of(5)).expect("small alloc");
        assert_eq!(array.count(), Count::of(5));
        assert_eq!(array.pop_last(), Some(0));
        assert_eq!(array.pop_last(), Some(0));
        assert_eq!(array.pop_last(), Some(0));
        assert_eq!(array.pop_last(), Some(0));
        assert_eq!(array.pop_last(), Some(0));
        assert_eq!(array.count(), Count::of(0));
    }

    #[test]
    fn clear_keep_capacity() {
        // TODO: switch to noisy
        let mut array = Array::<u8>::new();
        array.mut_capacity(Count::of(10)).expect("small alloc");
        // TODO
        assert_eq!(array.capacity(), Count::of(10));
    }
}
