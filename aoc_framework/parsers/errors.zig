pub const ParseError = error {
    InputNotConsumed,
    EmptyInput,
    LiteralDoesNotMatch,
    InvalidCharacter,
    NumberOverflow,
    Filtered,
    NoneMatch,
};