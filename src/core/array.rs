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
        Self::array_push(
            value,
            &mut self.count,
            &mut self.allocation,
            &mut self.capacity,
        )
    }

    #[inline]
    pub fn array_push(
        value: T,
        count: &mut Count,
        allocation: &mut Allocation<T>,
        capacity: &mut Count,
    ) -> Arrayed {
        if *capacity == *count {
            Self::array_grow(allocation, capacity)?;
        }
        *count += 1;
        allocation
            .write_uninitialized(value, count.max_offset(), *capacity)
            .expect("should be in bounds");
        return Ok(());
    }

    pub fn pop(&mut self, pop: Pop) -> Option<T> {
        Self::array_pop(pop, &mut self.count, &mut self.allocation, self.capacity)
    }

    #[inline]
    pub fn array_pop(
        pop: Pop,
        count: &mut Count,
        allocation: &mut Allocation<T>,
        capacity: Count,
    ) -> Option<T> {
        match pop {
            Pop::Last => Self::array_pop_last(count, allocation, capacity),
        }
    }

    #[inline]
    pub fn array_pop_last(
        count: &mut Count,
        allocation: &mut Allocation<T>,
        capacity: Count,
    ) -> Option<T> {
        if *count <= Count::of(0) {
            return None;
        }
        let result = Some(
            allocation
                .read_destructively(count.max_offset(), capacity)
                .expect("should be in bounds"),
        );
        *count -= 1;
        result
    }

    pub fn clear(&mut self, options: Clear) {
        Self::array_clear(
            options,
            &mut self.count,
            &mut self.allocation,
            &mut self.capacity,
        )
    }

    #[inline]
    pub fn array_clear(
        options: Clear,
        count: &mut Count,
        allocation: &mut Allocation<T>,
        capacity: &mut Count,
    ) {
        match options {
            Clear::KeepCapacity => {
                // We could optimize this but we do need Rust to drop each individual
                // element (if necessary), so we can't just dealloc the `ptr` itself.
                while let Some(_) = Self::array_pop_last(count, allocation, *capacity) {}
            }
            Clear::DropCapacity => {
                Self::array_mut_capacity(Count::of(0), count, allocation, capacity)
                    .expect("clearing should not alloc")
            }
        }
        assert!(*count == Count::of(0));
    }

    pub fn capacity(&self) -> Count {
        return self.capacity;
    }

    /// Will reallocate to exactly this capacity.
    /// Will delete items if `new_capacity < self.count()`
    pub fn mut_capacity(&mut self, new_capacity: Count) -> Arrayed {
        Self::array_mut_capacity(
            new_capacity,
            &mut self.count,
            &mut self.allocation,
            &mut self.capacity,
        )
    }

    #[inline]
    pub fn array_mut_capacity(
        new_capacity: Count,
        count: &mut Count,
        allocation: &mut Allocation<T>,
        capacity: &mut Count,
    ) -> Arrayed {
        if new_capacity == *capacity {
            return Ok(());
        }
        while *count > new_capacity {
            // We could optimize this but we do need Rust to drop each individual
            // element (if necessary), so we can't just dealloc the `ptr` itself.
            if Self::array_pop_last(count, allocation, *capacity).is_none() {
                // Could happen if new_capacity < 0
                break;
            }
        }
        allocation
            .mut_capacity(capacity, new_capacity)
            .map_err(|e| ArrayError::Allocation(e))
    }

    fn grow(&mut self) -> Arrayed {
        Self::array_grow(&mut self.allocation, &mut self.capacity)
    }

    #[inline]
    fn array_grow(allocation: &mut Allocation<T>, capacity: &mut Count) -> Arrayed {
        allocation
            .grow(capacity)
            .map_err(|e| ArrayError::Allocation(e))
    }
}

impl<T: std::default::Default> Array<T> {
    // TODO: this should be a Countable Trait
    pub fn mut_count(&mut self, new_count: Count) -> Arrayed {
        Self::array_mut_count(
            new_count,
            &mut self.count,
            &mut self.allocation,
            &mut self.capacity,
        )
    }

    #[inline]
    pub fn array_mut_count(
        new_count: Count,
        count: &mut Count,
        allocation: &mut Allocation<T>,
        capacity: &mut Count,
    ) -> Arrayed {
        if new_count < *count {
            while *count > new_count {
                _ = Self::array_pop_last(count, allocation, *capacity);
            }
        } else if new_count > *count {
            if new_count > *capacity {
                Self::array_mut_capacity(new_count, count, allocation, capacity)?;
            }
            while *count < new_count {
                Self::array_push(Default::default(), count, allocation, capacity)
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
    // TODO
    //First,
    //Index(Index),
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
        assert_eq!(array.pop(Pop::Last), Some(3));
        assert_eq!(array.pop(Pop::Last), Some(2));
        assert_eq!(array.pop(Pop::Last), Some(1));
        assert_eq!(array.count(), Count::of(0));
        assert_eq!(array.capacity(), Count::of(3));
    }

    #[test]
    fn mut_count_supplies_defaults() {
        let mut array = Array::<u32>::new();
        array.mut_count(Count::of(5)).expect("small alloc");
        assert_eq!(array.count(), Count::of(5));
        assert_eq!(array.pop(Pop::Last), Some(0));
        assert_eq!(array.pop(Pop::Last), Some(0));
        assert_eq!(array.pop(Pop::Last), Some(0));
        assert_eq!(array.pop(Pop::Last), Some(0));
        assert_eq!(array.pop(Pop::Last), Some(0));
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
