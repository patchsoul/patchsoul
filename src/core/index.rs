pub type Offset = i64;
#[derive(Eq, PartialEq, Copy, Clone, Debug, Default, Hash)]
pub struct Count(i64);

#[derive(Eq, PartialEq, Copy, Clone, Debug, Hash)]
pub enum Index {
    /// Zero-based indexing into an ordered sequence with partial wrap around, e.g.,
    /// `Index::Of(0)` is the first element, `Index::Of(1)` is the second, etc.,
    /// and negative values will "wrap once", i.e., `Index::Of(-1)` will grab the
    /// last element, `Index::Of(-2)` will give the second to last, all the way
    /// up to `Index::Of(-count)` which gives the first element, where `count` is
    /// the number of elements in the sequence.  `Index::Of(-count - x)` will
    /// produce an error for `x > 1`.  This does not check for being in bounds if
    /// you pass in a positive number.
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
    /// `Index::Ordinal(1)` is the first element, `Index::Ordinal(2)` is the second, etc.
    /// Non-positive values are invalid, i.e., 0 and anything negative.
    /// This does not check for being in bounds, so ordinals larger than the size of the
    /// sequence are considered valid offsets.
    Ordinal(i64),
}

impl Index {
    pub fn check_offset(self, sequence_size: Count) -> IndexResult<OffsetCheck> {
        let sequence_size = sequence_size.0;
        match self {
            Index::Of(value) => {
                if value >= 0 {
                    Ok(OffsetCheck {
                        offset: value,
                        increases_count: value >= sequence_size,
                    })
                } else if value >= -sequence_size {
                    Ok(OffsetCheck::in_bounds(sequence_size + value))
                } else {
                    Err(IndexError::OutOfBounds)
                }
            }
            Index::InBounds(value) => {
                if value >= 0 && value < sequence_size {
                    Ok(OffsetCheck::in_bounds(value))
                } else {
                    Err(IndexError::OutOfBounds)
                }
            }
            Index::Wrap(value) => {
                if sequence_size <= 0 {
                    Err(IndexError::EmptySequence)
                } else {
                    Ok(OffsetCheck::in_bounds(value.rem_euclid(sequence_size)))
                }
            }
            Index::Ordinal(value) => {
                if value > 0 {
                    Ok(OffsetCheck {
                        offset: value - 1,
                        increases_count: value > sequence_size,
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
    fn of_positive_values_less_than_count() {
        assert_offset(Index::Of(1), Count(5), Ok(OffsetCheck::in_bounds(1)));
        assert_offset(Index::Of(123), Count(124), Ok(OffsetCheck::in_bounds(123)));
    }

    #[test]
    fn of_positive_values_greater_or_equal_to_count() {
        assert_offset(Index::Of(7), Count(4), Ok(OffsetCheck::increases_count(7)));
        assert_offset(Index::Of(8), Count(0), Ok(OffsetCheck::increases_count(8)));
        assert_offset(Index::Of(9), Count(9), Ok(OffsetCheck::increases_count(9)));
    }

    #[test]
    fn of_negative_values_within_size() {
        assert_offset(Index::Of(-1), Count(5), Ok(OffsetCheck::in_bounds(4)));
        assert_offset(Index::Of(-3), Count(5), Ok(OffsetCheck::in_bounds(2)));
        assert_offset(Index::Of(-5), Count(5), Ok(OffsetCheck::in_bounds(0)));

        assert_offset(Index::Of(-7), Count(8), Ok(OffsetCheck::in_bounds(1)));
        assert_offset(Index::Of(-3), Count(8), Ok(OffsetCheck::in_bounds(5)));
    }

    #[test]
    fn of_negative_values_beyond_size_errs() {
        assert_offset(Index::Of(-6), Count(5), Err(IndexError::OutOfBounds));
        assert_offset(Index::Of(-100), Count(8), Err(IndexError::OutOfBounds));
    }

    #[test]
    fn in_bounds_positive_less_than_count() {
        assert_offset(Index::InBounds(0), Count(5), Ok(OffsetCheck::in_bounds(0)));
        assert_offset(Index::InBounds(4), Count(5), Ok(OffsetCheck::in_bounds(4)));
        assert_offset(
            Index::InBounds(3),
            Count(100),
            Ok(OffsetCheck::in_bounds(3)),
        );
        assert_offset(
            Index::InBounds(77),
            Count(100),
            Ok(OffsetCheck::in_bounds(77)),
        );
    }

    #[test]
    fn in_bounds_negative_or_beyond_count_errs() {
        assert_offset(Index::InBounds(-1), Count(5), Err(IndexError::OutOfBounds));
        assert_offset(Index::InBounds(5), Count(5), Err(IndexError::OutOfBounds));
        assert_offset(Index::InBounds(5), Count(4), Err(IndexError::OutOfBounds));
    }

    #[test]
    fn wrap_negative_values() {
        assert_offset(Index::Wrap(-1), Count(5), Ok(OffsetCheck::in_bounds(4)));
        assert_offset(Index::Wrap(-3), Count(5), Ok(OffsetCheck::in_bounds(2)));
        assert_offset(Index::Wrap(-5), Count(5), Ok(OffsetCheck::in_bounds(0)));
        assert_offset(Index::Wrap(-7), Count(5), Ok(OffsetCheck::in_bounds(3)));

        assert_offset(Index::Wrap(-7), Count(8), Ok(OffsetCheck::in_bounds(1)));
        assert_offset(Index::Wrap(-9), Count(8), Ok(OffsetCheck::in_bounds(7)));
    }

    #[test]
    fn wrap_positive_values() {
        assert_offset(Index::Wrap(1), Count(5), Ok(OffsetCheck::in_bounds(1)));
        assert_offset(Index::Wrap(3), Count(5), Ok(OffsetCheck::in_bounds(3)));
        assert_offset(Index::Wrap(5), Count(5), Ok(OffsetCheck::in_bounds(0)));
        assert_offset(Index::Wrap(7), Count(5), Ok(OffsetCheck::in_bounds(2)));

        assert_offset(Index::Wrap(7), Count(8), Ok(OffsetCheck::in_bounds(7)));
        assert_offset(Index::Wrap(9), Count(8), Ok(OffsetCheck::in_bounds(1)));
    }

    #[test]
    fn wrap_nonpositive_counts_errs() {
        for count in vec![-2, -1, 0] {
            for value in vec![-5, 0, 4] {
                assert_offset(
                    Index::Wrap(value),
                    Count(count),
                    Err(IndexError::EmptySequence),
                );
            }
        }
    }

    #[test]
    fn ordinal_above_count() {
        assert_offset(
            Index::Ordinal(1),
            Count(0),
            Ok(OffsetCheck::increases_count(0)),
        );
        assert_offset(
            Index::Ordinal(2),
            Count(-1),
            Ok(OffsetCheck::increases_count(1)),
        );

        for count in vec![0, 1, 2] {
            for value in count + 1..count + 4 {
                assert_offset(
                    Index::Ordinal(value),
                    Count(count),
                    Ok(OffsetCheck::increases_count(value - 1)),
                );
            }
        }
    }

    #[test]
    fn ordinal_within_or_equal_to_count() {
        assert_offset(Index::Ordinal(1), Count(1), Ok(OffsetCheck::in_bounds(0)));
        for count in vec![2, 3, 6] {
            for value in vec![1, count] {
                assert_offset(
                    Index::Ordinal(value),
                    Count(count),
                    Ok(OffsetCheck::in_bounds(value - 1)),
                );
            }
        }
    }

    #[test]
    fn ordinal_when_nonpositive_errs() {
        for count in vec![-1, 0, 1, 2] {
            for value in vec![-1, 0, -2] {
                assert_offset(
                    Index::Ordinal(value),
                    Count(count),
                    Err(IndexError::InvalidOrdinal),
                );
            }
        }
    }

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
