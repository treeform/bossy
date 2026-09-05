import std/math

type
  BasicError* = object of CatchableError

  ValueKind* = enum
    IntegerValue,
    FloatValue

  Value* = object
    ## A finite float64 or a wrapping int32, with an integer zero default.
    case kind: ValueKind
    of IntegerValue:
      integer: int32
    of FloatValue:
      decimal: float64

proc kind*(value: Value): ValueKind {.inline, raises: [].} =
  ## Returns the numeric representation of a value.
  value.kind

converter toValue*(value: int32): Value {.inline, raises: [].} =
  ## Wraps an integer without changing its representation.
  Value(kind: IntegerValue, integer: value)

converter toValue*(value: bool): Value {.inline, raises: [].} =
  ## Converts a Nim Boolean to BASIC's integer -1 or zero.
  toValue(-int32(value))

converter toValue*(value: int): Value {.inline, raises: [BasicError].} =
  ## Converts a native integer after checking the portable int32 range.
  if value < int(low(int32)) or value > int(high(int32)):
    raise newException(BasicError, "BASIC integer is outside the int32 range")
  toValue(int32(value))

converter toValue*(value: float64): Value {.inline, raises: [BasicError].} =
  ## Wraps a finite float, rejecting NaN and infinity.
  if classify(value) in {fcNan, fcInf, fcNegInf}:
    raise newException(BasicError, "BASIC floating-point value must be finite")
  Value(kind: FloatValue, decimal: value)

proc asFloat*(value: Value): float64 {.inline, raises: [].} =
  ## Reads a float or widens an integer exactly to float64.
  case value.kind
  of IntegerValue:
    float64(value.integer)
  of FloatValue:
    value.decimal

proc asBool*(value: Value): bool {.inline, raises: [].} =
  ## Tests a BASIC condition, where every nonzero numeric value is true.
  case value.kind
  of IntegerValue:
    value.integer != 0
  of FloatValue:
    value.decimal != 0.0

proc asInt*(value: Value): int32 {.inline, raises: [BasicError].} =
  ## Reads an integer, rejecting fractional or out-of-range floats.
  case value.kind
  of IntegerValue:
    value.integer
  of FloatValue:
    if value.decimal < float64(low(int32)) or
      value.decimal > float64(high(int32)) or
      trunc(value.decimal) != value.decimal:
        raise newException(BasicError, "BASIC value must be an exact int32")
    int32(value.decimal)

proc `$`*(value: Value): string {.raises: [].} =
  ## Formats a numeric value using its stored representation.
  case value.kind
  of IntegerValue:
    $value.integer
  of FloatValue:
    $value.decimal

proc `+`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Adds integers with wrapping or promotes mixed operands to float64.
  if left.kind == IntegerValue and right.kind == IntegerValue:
    toValue(left.integer +% right.integer)
  else:
    toValue(left.asFloat + right.asFloat)

proc `-`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Subtracts integers with wrapping or promotes operands to float64.
  if left.kind == IntegerValue and right.kind == IntegerValue:
    toValue(left.integer -% right.integer)
  else:
    toValue(left.asFloat - right.asFloat)

proc `*`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Multiplies integers with wrapping or promotes operands to float64.
  if left.kind == IntegerValue and right.kind == IntegerValue:
    toValue(left.integer *% right.integer)
  else:
    toValue(left.asFloat * right.asFloat)

proc `-`*(value: Value): Value {.inline, raises: [BasicError].} =
  ## Negates a float or wraps an integer's two's-complement negation.
  case value.kind
  of IntegerValue:
    toValue(0'i32 -% value.integer)
  of FloatValue:
    toValue(-value.decimal)

proc `/`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Divides as float64 and rejects zero divisors and non-finite results.
  if right.asFloat == 0.0:
    raise newException(BasicError, "division by zero")
  toValue(left.asFloat / right.asFloat)

proc `div`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Divides exact int32 operands toward zero with defined overflow.
  let
    a = left.asInt
    b = right.asInt
  if b == 0:
    raise newException(BasicError, "division by zero")
  if a == low(int32) and b == -1:
    return toValue(low(int32))
  toValue(a div b)

proc `mod`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Computes the remainder of exact int32 operands with defined overflow.
  let
    a = left.asInt
    b = right.asInt
  if b == 0:
    raise newException(BasicError, "division by zero")
  if a == low(int32) and b == -1:
    return toValue(0'i32)
  toValue(a mod b)

proc bitInteger(value: Value): int32 {.inline, raises: [BasicError].} =
  ## Converts a logical operand to int32, rounding ties to the even integer.
  case value.kind
  of IntegerValue:
    result = value.integer
  of FloatValue:
    if value.decimal < float64(low(int32)) or
      value.decimal > float64(high(int32)):
        raise newException(BasicError, "BASIC logical operand exceeds int32")
    let
      lower = floor(value.decimal)
      fraction = value.decimal - lower
    result = int32(lower)
    if fraction > 0.5 or (fraction == 0.5 and (result and 1) != 0):
      inc result

proc `not`*(value: Value): Value {.inline, raises: [BasicError].} =
  ## Complements every bit of a rounded int32 operand.
  toValue(not value.bitInteger)

proc `and`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Intersects the bits of two rounded int32 operands.
  toValue(left.bitInteger and right.bitInteger)

proc `or`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Unites the bits of two rounded int32 operands.
  toValue(left.bitInteger or right.bitInteger)

proc `xor`*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Returns the bits present in exactly one rounded int32 operand.
  toValue(left.bitInteger xor right.bitInteger)

proc eqv*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Returns the matching bits of two rounded int32 operands.
  toValue(not (left.bitInteger xor right.bitInteger))

proc imp*(left, right: Value): Value {.inline, raises: [BasicError].} =
  ## Computes bitwise implication between two rounded int32 operands.
  toValue((not left.bitInteger) or right.bitInteger)

proc `==`*(left, right: Value): bool {.inline, raises: [].} =
  ## Compares numeric values, widening only when a float is present.
  if left.kind == IntegerValue and right.kind == IntegerValue:
    left.integer == right.integer
  else:
    left.asFloat == right.asFloat

proc `<`*(left, right: Value): bool {.inline, raises: [].} =
  ## Orders numeric values, widening only when a float is present.
  if left.kind == IntegerValue and right.kind == IntegerValue:
    left.integer < right.integer
  else:
    left.asFloat < right.asFloat

proc `<=`*(left, right: Value): bool {.inline, raises: [].} =
  ## Compares numeric values inclusively without changing their types.
  if left.kind == IntegerValue and right.kind == IntegerValue:
    left.integer <= right.integer
  else:
    left.asFloat <= right.asFloat
