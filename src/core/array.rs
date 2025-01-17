use crate::core::allocation::*;
use crate::core::index::*;

pub type ArrayResult<T> = Result<T, ArrayError>;
pub type Arrayed = ArrayResult<()>;

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub enum ArrayError {
    Allocation(AllocationError),
}

impl ArrayError {
    pub fn err(self) -> Arrayed {
        return Err(self);
    }
}

pub type Array<T> = ArrayN<T, i64>;
pub type Array64<T> = Array<T>;
pub type Array32<T> = ArrayN<T, i32>;
pub type Array16<T> = ArrayN<T, i16>;
pub type Array8<T> = ArrayN<T, i8>;

/// Low-level structure that has a pointer to contiguous memory.
/// You need to keep track of which elements are initialized, etc.,
/// as well as the capacity as `CountN<C>`.
#[repr(align(8))]
pub struct ArrayN<T, C: SignedPrimitive> {
    allocation: AllocationN<T, C>,
    count: CountN<C>,
}

// TODO: implement #[derive(Clone, Debug, Hash)]
impl<T, C: SignedPrimitive> ArrayN<T, C> {
    pub fn new() -> Self {
        Self {
            allocation: AllocationN::<T, C>::new(),
            count: CountN::<C>::of(C::zero()),
        }
    }

    // TODO: this should be a Countable Trait
    pub fn count(&self) -> CountN<C> {
        return self.count;
    }

    pub fn push(&mut self, value: T) -> Arrayed {
        Self::array_push(value, &mut self.allocation, &mut self.count)
    }

    #[inline]
    pub fn array_push(
        value: T,
        allocation: &mut AllocationN<T, C>,
        count: &mut CountN<C>,
    ) -> Arrayed {
        if allocation.capacity() == *count {
            Self::array_grow(allocation)?;
        }
        *count += C::one();
        allocation
            .write_uninitialized(count.max_offset(), value)
            .expect("should be in bounds");
        return Ok(());
    }

    pub fn pop(&mut self, pop: Pop) -> Option<T> {
        Self::array_pop(pop, &mut self.allocation, &mut self.count)
    }

    #[inline]
    pub fn array_pop(
        pop: Pop,
        allocation: &mut AllocationN<T, C>,
        count: &mut CountN<C>,
    ) -> Option<T> {
        match pop {
            Pop::Last => Self::array_pop_last(allocation, count),
        }
    }

    #[inline]
    pub fn array_pop_last(allocation: &mut AllocationN<T, C>, count: &mut CountN<C>) -> Option<T> {
        if *count <= CountN::<C>::of(C::zero()) {
            return None;
        }
        let result = Some(
            allocation
                .read_destructively(count.max_offset())
                .expect("should be in bounds"),
        );
        *count -= C::one();
        result
    }

    pub fn clear(&mut self, options: Clear) {
        Self::array_clear(options, &mut self.allocation, &mut self.count)
    }

    #[inline]
    pub fn array_clear(options: Clear, allocation: &mut AllocationN<T, C>, count: &mut CountN<C>) {
        match options {
            Clear::KeepCapacity => {
                // We could optimize this but we do need Rust to drop each individual
                // element (if necessary), so we can't just dealloc the `ptr` itself.
                while let Some(_) = Self::array_pop_last(allocation, count) {}
            }
            Clear::DropCapacity => {
                Self::array_mut_capacity(CountN::<C>::of(C::zero()), allocation, count)
                    .expect("clearing should not alloc")
            }
        }
        assert!(*count == CountN::<C>::of(C::zero()));
    }

    pub fn capacity(&self) -> CountN<C> {
        return self.allocation.capacity();
    }

    /// Will reallocate to exactly this capacity.
    /// Will delete items if `new_capacity < self.count()`
    pub fn mut_capacity(&mut self, new_capacity: CountN<C>) -> Arrayed {
        Self::array_mut_capacity(new_capacity, &mut self.allocation, &mut self.count)
    }

    #[inline]
    pub fn array_mut_capacity(
        new_capacity: CountN<C>,
        allocation: &mut AllocationN<T, C>,
        count: &mut CountN<C>,
    ) -> Arrayed {
        if new_capacity == allocation.capacity() {
            return Ok(());
        }
        while *count > new_capacity {
            // We could optimize this but we do need Rust to drop each individual
            // element (if necessary), so we can't just dealloc the `ptr` itself.
            if Self::array_pop_last(allocation, count).is_none() {
                // Could happen if new_capacity < 0
                break;
            }
        }
        allocation
            .mut_capacity(new_capacity)
            .map_err(|e| ArrayError::Allocation(e))
    }

    #[inline]
    pub fn array_grow(allocation: &mut AllocationN<T, C>) -> Arrayed {
        allocation.grow().map_err(|e| ArrayError::Allocation(e))
    }
}

impl<T: std::default::Default, C: SignedPrimitive> ArrayN<T, C> {
    // TODO: this should be a Countable Trait
    pub fn mut_count(&mut self, new_count: CountN<C>) -> Arrayed {
        Self::array_mut_count(new_count, &mut self.allocation, &mut self.count)
    }

    #[inline]
    pub fn array_mut_count(
        new_count: CountN<C>,
        allocation: &mut AllocationN<T, C>,
        count: &mut CountN<C>,
    ) -> Arrayed {
        if new_count < *count {
            while *count > new_count {
                _ = Self::array_pop_last(allocation, count);
            }
        } else if new_count > *count {
            if new_count > allocation.capacity() {
                Self::array_mut_capacity(new_count, allocation, count)?;
            }
            while *count < new_count {
                Self::array_push(Default::default(), allocation, count)
                    .expect("already allocated enough above");
            }
        }
        return Ok(());
    }
}

impl<T, C: SignedPrimitive> std::ops::Deref for ArrayN<T, C> {
    type Target = [T];
    fn deref(&self) -> &[T] {
        &self.allocation[0..self.count.into()]
    }
}

impl<T, C: SignedPrimitive> std::ops::DerefMut for ArrayN<T, C> {
    fn deref_mut(&mut self) -> &mut [T] {
        &mut self.allocation[0..self.count.into()]
    }
}

impl<T: std::cmp::PartialEq, C: SignedPrimitive> PartialEq<Self> for ArrayN<T, C> {
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

impl<T: std::cmp::Eq, C: SignedPrimitive> Eq for ArrayN<T, C> {}

impl<T, C: SignedPrimitive> Default for ArrayN<T, C> {
    fn default() -> Self {
        return Self::new();
    }
}

impl<T, C: SignedPrimitive> Drop for ArrayN<T, C> {
    fn drop(&mut self) {
        self.clear(Clear::DropCapacity);
    }
}

unsafe impl<T: Send, C: SignedPrimitive> Send for ArrayN<T, C> {}
unsafe impl<T: Sync, C: SignedPrimitive> Sync for ArrayN<T, C> {}

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
