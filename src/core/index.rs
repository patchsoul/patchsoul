use core::num::Wrapping;
use num_traits::{AsPrimitive, Num, PrimInt, Signed, ToPrimitive};
use std::cmp::Ordering;
use std::ops::{Add, AddAssign, Sub, SubAssign};

pub type Offset = i64;

#[derive(Debug)]
pub enum CountError {
    TooHigh,
    NonPositive,
}

pub type Count = Count64;
pub type Count64 = CountN<i64>;
pub type Count32 = CountN<i32>;
pub type Count16 = CountN<i16>;
pub type Count8 = CountN<i8>;

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub struct CountN<T: SignedPrimitive>(T);

/// Internally represents the i64 as the *negative* of the count,
/// so that we can have representable indices up to that value.
/// E.g., for an i8, Index(127) is valid, but Count::of(127) would not be large enough
/// to consider Index(127) as valid, so we represent a count of 128 as Count::of(-128).

impl<T> CountN<T>
where
    T: SignedPrimitive,
{
    pub const MAX: Self = Self(T::MIN);
    pub const MAX_USIZE: usize = T::MAX_USIZE;
    const TWO: T = T::TWO;

    pub fn of(value: T) -> Self {
        assert!(value >= T::zero());
        Self(-value)
    }

    pub fn from_usize(value: usize) -> Result<Self, CountError> {
        if value > Self::MAX_USIZE {
            Err(CountError::TooHigh)
        } else {
            Ok(Self(T::from(-(value as i64)).unwrap()))
        }
    }

    /// Returns `clamp(2 * self, min_value, MAX)`.
    /// Useful for growing containers via reallocation.
    /// `min_value` should be smallish, e.g., 1 to 16;
    /// if it's greater than `MAX` then bugs are on you.
    pub fn double_or_max(self, min_value: i8) -> Self {
        if self.0 <= Self::MAX.0 / Self::TWO {
            return Self::MAX;
        }
        return Self(T::from(-min_value).unwrap().min(self.0 * Self::TWO));
    }

    pub fn contains(self, offset: Offset) -> bool {
        offset >= 0 && offset <= self.max_offset()
    }

    pub fn max_offset(self) -> Offset {
        // This should always be representable, e.g., for an i8
        // the max count is 128, held as [-128] in self.0, so -([-128] + 1) is 127.
        -(self.0.to_i64().unwrap() + 1)
    }
}

pub trait SignedPrimitive:
    PrimInt
    + ToPrimitive
    + AsPrimitive<i64>
    + Signed
    + AddAssign
    + Add<Output = Self>
    + SubAssign
    + Sub<Output = Self>
    + std::cmp::PartialOrd
    + Sized
    + std::ops::Neg
    + Num
{
    const MIN: Self;
    const MAX_USIZE: usize;
    const MAX: Self;
    const TWO: Self;
}
impl SignedPrimitive for i64 {
    const MIN: Self = i64::MIN;
    const MAX_USIZE: usize = (-(i64::MIN + 1)) as usize + 1;
    const MAX: Self = i64::MAX;
    const TWO: Self = 2;
}
impl SignedPrimitive for i32 {
    const MIN: Self = i32::MIN;
    const MAX_USIZE: usize = (-(i32::MIN + 1)) as usize + 1;
    const MAX: Self = i32::MAX;
    const TWO: Self = 2;
}
impl SignedPrimitive for i16 {
    const MIN: Self = i16::MIN;
    const MAX_USIZE: usize = (-(i16::MIN + 1)) as usize + 1;
    const MAX: Self = i16::MAX;
    const TWO: Self = 2;
}
impl SignedPrimitive for i8 {
    const MIN: Self = i8::MIN;
    const MAX_USIZE: usize = (-(i8::MIN + 1)) as usize + 1;
    const MAX: Self = i8::MAX;
    const TWO: Self = 2;
}

impl<T: SignedPrimitive> std::default::Default for CountN<T> {
    fn default() -> Self {
        Self(T::zero())
    }
}

impl<T: SignedPrimitive> std::cmp::PartialOrd for CountN<T> {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.0.partial_cmp(&other.0).unwrap().reverse())
    }
}

impl<T: SignedPrimitive> Add<T> for CountN<T> {
    type Output = Self;

    fn add(self, other: T) -> Self {
        // Since the internal is negated, adding is subtracting:
        Self(self.0 - other)
    }
}

impl<T: SignedPrimitive> Add<Self> for CountN<T> {
    type Output = Self;

    fn add(self, other: Self) -> Self {
        // TODO: check for overflow
        Self(self.0 + other.0)
    }
}

impl<T: SignedPrimitive> AddAssign<T> for CountN<T> {
    fn add_assign(&mut self, other: T) {
        // Since the internal is negated, adding is subtracting:
        self.0 -= other;
        assert!(self.0 <= T::zero());
    }
}

impl<T: SignedPrimitive> AddAssign<Self> for CountN<T> {
    fn add_assign(&mut self, other: Self) {
        self.0 += other.0;
        assert!(self.0 <= T::zero());
    }
}

impl<T: SignedPrimitive> Sub<T> for CountN<T> {
    type Output = Self;

    fn sub(self, other: T) -> Self {
        // Since the internal is negated, adding is subtracting:
        Self(self.0 + other)
    }
}

impl<T: SignedPrimitive> Sub<Self> for CountN<T> {
    type Output = Self;

    fn sub(self, other: Self) -> Self {
        // TODO: check for overflow
        Self(self.0 - other.0)
    }
}

impl<T: SignedPrimitive> SubAssign<T> for CountN<T> {
    fn sub_assign(&mut self, other: T) {
        // Since the internal is negated, adding is subtracting:
        self.0 += other;
        assert!(self.0 <= T::zero());
    }
}

impl<T: SignedPrimitive> SubAssign<Self> for CountN<T> {
    fn sub_assign(&mut self, other: Self) {
        self.0 -= other.0;
        assert!(self.0 <= T::zero());
    }
}

impl<T: SignedPrimitive> Into<usize> for CountN<T> {
    fn into(self) -> usize {
        assert!(self.0 <= T::zero());
        (Wrapping(self.max_offset()) + Wrapping(1)).0 as usize
    }
}

// TODO: subtract, multiply, divide, etc.

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub enum Index {
    /// Zero-based indexing into an ordered sequence with partial wrap around, e.g.,
    /// `Index::Of(0)` is the first element, `Index::Of(1)` is the second, etc.,
    /// and negative values will "wrap once", i.e., `Index::Of(-1)` will grab the
    /// last element, `Index::Of(-2)` will give the second to last, all the way
    /// up to `Index::Of(-count)` which gives the first element, where `count` is
    /// the number of elements in the sequence.  `Index::Of(-count - x)` will
    /// produce an error for `x > 1`.  This does not check for being in bounds if
    /// you pass in a positive number, so it can increase the size of an array.
    Of(i64),
    /// Zero-based indexing into an ordered sequence, where the caller does not
    /// want to exceed the current bounds of the sequence.  I.e., negative values
    /// are invalid, and values larger than that of the sequence will produce errors.
    InBounds(i64),
    /// Zero-based indexing into an ordered sequence, but with wraparound so that
    /// negative values correspond to elements at the end of the array and
    /// positive values greater or equal to the sequence size wrap back to the start.
    /// E.g., `Index::Wrap(-1)` is the last element, `Index::Wrap(-2)` is the second to last,
    /// and `Index::Wrap(count + x)` is the same as `Index::Of(x)` where `x < count`,
    /// and `count` is the number of elements in the sequence.
    Wrap(i64),
    /// One-based indexing into an ordered sequence, e.g.,
    /// `Index::Ordinal(Count::of(1))` is the first element,
    /// `Index::Ordinal(Count::of(2))` is the second, etc.
    /// Non-positive values are invalid, i.e., 0 and anything negative.
    /// This does not check for being in bounds, so ordinals larger than the size of the
    /// sequence are considered valid offsets.
    Ordinal(Count),
}

impl Index {
    pub fn check_offset(self, sequence_size: Count) -> IndexResult<OffsetCheck> {
        match self {
            Index::Of(value) => {
                let sequence_size: usize = sequence_size.into();
                if value >= 0 {
                    Ok(OffsetCheck {
                        offset: value,
                        increases_count: value as usize >= sequence_size,
                    })
                } else if (-value) as usize <= sequence_size {
                    Ok(OffsetCheck::in_bounds(
                        (sequence_size - (-value) as usize) as i64,
                    ))
                } else {
                    Err(IndexError::OutOfBounds)
                }
            }
            Index::InBounds(value) => {
                if sequence_size.contains(value) {
                    Ok(OffsetCheck::in_bounds(value))
                } else {
                    Err(IndexError::OutOfBounds)
                }
            }
            Index::Wrap(value) => {
                let sequence_size: usize = sequence_size.into();
                if sequence_size <= 0 {
                    Err(IndexError::EmptySequence)
                } else if sequence_size == Count::MAX_USIZE {
                    if value >= 0 {
                        assert!((value as usize) < Count::MAX_USIZE);
                        Ok(OffsetCheck::in_bounds(value))
                    } else {
                        assert!(((-(value + 1)) as usize) < Count::MAX_USIZE);
                        Ok(OffsetCheck::in_bounds(
                            (sequence_size - (-(value + 1)) as usize - 1) as i64,
                        ))
                    }
                } else {
                    Ok(OffsetCheck::in_bounds(
                        value.rem_euclid(sequence_size as i64),
                    ))
                }
            }
            Index::Ordinal(count) => {
                let offset = count.max_offset();
                if offset >= 0 {
                    Ok(OffsetCheck {
                        offset,
                        increases_count: count > sequence_size,
                    })
                } else {
                    Err(IndexError::InvalidOrdinal)
                }
            }
        }
    }
}

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub enum IndexError {
    EmptySequence,
    OutOfBounds,
    InvalidOrdinal,
}

pub type IndexResult<T> = Result<T, IndexError>;

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub struct OffsetCheck {
    offset: Offset,
    increases_count: bool,
}

impl OffsetCheck {
    pub fn in_bounds(offset: Offset) -> Self {
        Self {
            offset,
            increases_count: false,
        }
    }

    pub fn increases_count(offset: Offset) -> Self {
        Self {
            offset,
            increases_count: true,
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn count_double_or_max_for_very_small_values() {
        assert_eq!(Count::of(0).double_or_max(1), Count::of(1));
        assert_eq!(Count::of(0).double_or_max(2), Count::of(2));
        assert_eq!(Count::of(1).double_or_max(50), Count::of(50));
        assert_eq!(Count::of(200).double_or_max(127), Count::of(400));
    }

    #[test]
    fn count_double_or_max_for_small_values() {
        assert_eq!(Count::of(123).double_or_max(2), Count::of(246));
        assert_eq!(
            Count::of(100_010_001).double_or_max(3),
            Count::of(200_020_002)
        );
        assert_eq!(
            Count::from_usize(Count::MAX_USIZE / 2 - 1)
                .expect("ok")
                .double_or_max(4),
            Count::of(9_223_372_036_854_775_806)
        );
    }

    #[test]
    fn count_double_or_max_for_large_values() {
        assert_eq!(Count::MAX.double_or_max(5), Count::MAX);
        assert_eq!(Count::of(i64::MAX - 5).double_or_max(6), Count::MAX);
        assert_eq!(Count::of(i64::MAX / 2 + 5).double_or_max(7), Count::MAX);
    }

    #[test]
    fn of_positive_values_less_than_count() {
        assert_offset(Index::Of(1), Count::of(5), Ok(OffsetCheck::in_bounds(1)));
        assert_offset(
            Index::Of(123),
            Count::of(124),
            Ok(OffsetCheck::in_bounds(123)),
        );
        assert_offset(
            Index::Of(Count::MAX.max_offset()),
            Count::MAX,
            Ok(OffsetCheck::in_bounds(9_223_372_036_854_775_807)),
        )
    }

    #[test]
    fn of_positive_values_greater_or_equal_to_count() {
        assert_offset(
            Index::Of(7),
            Count::of(4),
            Ok(OffsetCheck::increases_count(7)),
        );
        assert_offset(
            Index::Of(8),
            Count::of(0),
            Ok(OffsetCheck::increases_count(8)),
        );
        assert_offset(
            Index::Of(9),
            Count::of(9),
            Ok(OffsetCheck::increases_count(9)),
        );
        assert_offset(
            Index::Of(Count::MAX.max_offset()),
            Count::from_usize(Count::MAX_USIZE - 1).expect("ok"),
            Ok(OffsetCheck::increases_count(9_223_372_036_854_775_807)),
        )
    }

    #[test]
    fn of_negative_values_within_size() {
        assert_offset(Index::Of(-1), Count::of(5), Ok(OffsetCheck::in_bounds(4)));
        assert_offset(Index::Of(-3), Count::of(5), Ok(OffsetCheck::in_bounds(2)));
        assert_offset(Index::Of(-5), Count::of(5), Ok(OffsetCheck::in_bounds(0)));

        assert_offset(Index::Of(-7), Count::of(8), Ok(OffsetCheck::in_bounds(1)));
        assert_offset(Index::Of(-3), Count::of(8), Ok(OffsetCheck::in_bounds(5)));
    }

    #[test]
    fn of_negative_values_beyond_size_errs() {
        assert_offset(Index::Of(-6), Count::of(5), Err(IndexError::OutOfBounds));
        assert_offset(Index::Of(-100), Count::of(8), Err(IndexError::OutOfBounds));
    }

    #[test]
    fn in_bounds_positive_less_than_count() {
        assert_offset(
            Index::InBounds(0),
            Count::of(5),
            Ok(OffsetCheck::in_bounds(0)),
        );
        assert_offset(
            Index::InBounds(4),
            Count::of(5),
            Ok(OffsetCheck::in_bounds(4)),
        );
        assert_offset(
            Index::InBounds(3),
            Count::of(100),
            Ok(OffsetCheck::in_bounds(3)),
        );
        assert_offset(
            Index::InBounds(77),
            Count::of(100),
            Ok(OffsetCheck::in_bounds(77)),
        );
    }

    #[test]
    fn in_bounds_negative_or_beyond_count_errs() {
        assert_offset(
            Index::InBounds(-1),
            Count::of(5),
            Err(IndexError::OutOfBounds),
        );
        assert_offset(
            Index::InBounds(5),
            Count::of(5),
            Err(IndexError::OutOfBounds),
        );
        assert_offset(
            Index::InBounds(5),
            Count::of(4),
            Err(IndexError::OutOfBounds),
        );
    }

    #[test]
    fn wrap_negative_values() {
        assert_offset(Index::Wrap(-1), Count::of(5), Ok(OffsetCheck::in_bounds(4)));
        assert_offset(Index::Wrap(-3), Count::of(5), Ok(OffsetCheck::in_bounds(2)));
        assert_offset(Index::Wrap(-5), Count::of(5), Ok(OffsetCheck::in_bounds(0)));
        assert_offset(Index::Wrap(-7), Count::of(5), Ok(OffsetCheck::in_bounds(3)));

        assert_offset(Index::Wrap(-7), Count::of(8), Ok(OffsetCheck::in_bounds(1)));
        assert_offset(Index::Wrap(-9), Count::of(8), Ok(OffsetCheck::in_bounds(7)));

        assert_offset(
            Index::Wrap(i64::MIN),
            Count::MAX,
            Ok(OffsetCheck::in_bounds(0)),
        );
        assert_offset(
            Index::Wrap(-3),
            Count::MAX,
            Ok(OffsetCheck::in_bounds(
                i64::MAX - 3 + 1, /* +1 is because i64::MAX is short Count::MAX by 1. */
            )),
        );
    }

    #[test]
    fn wrap_positive_values() {
        assert_offset(Index::Wrap(1), Count::of(5), Ok(OffsetCheck::in_bounds(1)));
        assert_offset(Index::Wrap(3), Count::of(5), Ok(OffsetCheck::in_bounds(3)));
        assert_offset(Index::Wrap(5), Count::of(5), Ok(OffsetCheck::in_bounds(0)));
        assert_offset(Index::Wrap(7), Count::of(5), Ok(OffsetCheck::in_bounds(2)));

        assert_offset(Index::Wrap(7), Count::of(8), Ok(OffsetCheck::in_bounds(7)));
        assert_offset(Index::Wrap(9), Count::of(8), Ok(OffsetCheck::in_bounds(1)));

        assert_offset(
            Index::Wrap(i64::MAX),
            Count::MAX,
            Ok(OffsetCheck::in_bounds(i64::MAX)),
        );
        assert_offset(Index::Wrap(77), Count::MAX, Ok(OffsetCheck::in_bounds(77)));
    }

    #[test]
    fn wrap_nonpositive_counts_errs() {
        for value in vec![-5, 0, 4] {
            assert_offset(
                Index::Wrap(value),
                Count::of(0),
                Err(IndexError::EmptySequence),
            );
        }
    }

    #[test]
    fn ordinal_above_count() {
        assert_offset(
            Index::Ordinal(Count::of(1)),
            Count::of(0),
            Ok(OffsetCheck::increases_count(0)),
        );
        assert_offset(
            Index::Ordinal(Count::of(2)),
            Count::of(1),
            Ok(OffsetCheck::increases_count(1)),
        );

        for count in vec![0, 1, 2] {
            for value in count + 1..count + 4 {
                assert_offset(
                    Index::Ordinal(Count::of(value)),
                    Count::of(count),
                    Ok(OffsetCheck::increases_count(value - 1)),
                );
            }
        }
    }

    #[test]
    fn ordinal_within_or_equal_to_count() {
        assert_offset(
            Index::Ordinal(Count::of(1)),
            Count::of(1),
            Ok(OffsetCheck::in_bounds(0)),
        );
        for count in vec![2, 3, 6] {
            for value in vec![1, count] {
                assert_offset(
                    Index::Ordinal(Count::of(value)),
                    Count::of(count),
                    Ok(OffsetCheck::in_bounds(value - 1)),
                );
            }
        }
    }

    #[test]
    fn ordinal_when_nonpositive_errs() {
        for count in vec![0, 1, 2] {
            assert_offset(
                Index::Ordinal(Count::of(0)),
                Count::of(count),
                Err(IndexError::InvalidOrdinal),
            );
        }
    }

    // TODO: test from_usize
    // TODO: test MAX_USIZE on each i8, i16, etc.

    fn assert_offset(index: Index, count: Count, result: IndexResult<OffsetCheck>) {
        assert_eq!(
            index.check_offset(count),
            result,
            "{:?}.check_offset({:?})",
            index,
            count,
        );
    }
}
