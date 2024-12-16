pub const ParseError = error{
    InputNotConsumed,
    EmptyInput,
    LiteralDoesNotMatch,
    InvalidCharacter,
    NumberOverflow,
    Filtered,
    NoneMatch,
    GridNoItems,
    GridRowTooShort,
    GridRowTooLong,
    GridMissingPOIs,
};
