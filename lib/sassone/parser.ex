defmodule Sassone.Parser do
  @moduledoc false

  alias Sassone.Parser.Generator

  defmodule Binary do
    @moduledoc false

    use Generator, streaming?: false
  end

  defmodule Stream do
    @moduledoc false

    use Generator, streaming?: true
  end

  @compile {:inline, [convert_entity_reference: 2]}

  def convert_entity_reference(reference_name, :never),
    do: [?&, reference_name, ?;]

  def convert_entity_reference("amp", _expand_entity), do: [?&]
  def convert_entity_reference("lt", _expand_entity), do: [?<]
  def convert_entity_reference("gt", _expand_entity), do: [?>]
  def convert_entity_reference("apos", _expand_entity), do: [?']
  def convert_entity_reference("quot", _expand_entity), do: [?"]

  def convert_entity_reference(reference_name, expand_entity) do
    case expand_entity do
      :keep -> [?&, reference_name, ?;]
      :skip -> []
      {mod, fun, args} -> apply(mod, fun, [reference_name | args])
    end
  end

  def compute_char_len(char) when char <= 0x7F, do: 1
  def compute_char_len(char) when char <= 0x7FF, do: 2
  def compute_char_len(char) when char <= 0xFFFF, do: 3
  def compute_char_len(_char), do: 4

  # Maximum number of digits allowed in a numeric character reference. The
  # largest valid code point is U+10FFFF, which needs 7 decimal / 6 hexadecimal
  # digits; the extra budget applies after leading zeros are skipped, still bounding
  # the integer we hand to `String.to_integer/2`, preventing huge-bignum DoS.
  @max_decimal_char_ref_digits 10
  @max_hexadecimal_char_ref_digits 8

  @compile {:inline, [valid_char_ref?: 1, skip_zeros: 1]}

  @doc """
  Parses the digits of a numeric character reference into a code point.
  `base` is `10` for `&#...;` or `16` for `&#x...;`. Returns `{:ok, codepoint}`
  for a valid XML character, or `{:error, reason}` (a `Saxy.ParseError` reason)
  when there are too many digits or the code point is not a valid XML `Char`.
  """
  def parse_char_ref(digits, base) do
    max_digits =
      case base do
        10 -> @max_decimal_char_ref_digits
        16 -> @max_hexadecimal_char_ref_digits
      end

    digits = skip_zeros(digits)

    if byte_size(digits) > max_digits do
      {:error, {:invalid_char_ref, :too_long}}
    else
      codepoint = if digits == "", do: 0, else: String.to_integer(digits, base)

      if valid_char_ref?(codepoint) do
        {:ok, codepoint}
      else
        {:error, {:invalid_char_ref, codepoint}}
      end
    end
  end

  defp skip_zeros(<<?0, rest::bits>>), do: skip_zeros(rest)
  defp skip_zeros(digits), do: digits

  # Returns `true` when the code point is a valid XML 1.0 `Char`, ordered with
  # the common printable BMP range first. See https://www.w3.org/TR/xml/#NT-Char
  # — this excludes NUL and other disallowed control characters, the surrogate
  # range (U+D800–U+DFFF), U+FFFE, U+FFFF, and anything beyond U+10FFFF.
  defp valid_char_ref?(codepoint) do
    (codepoint >= 0x20 and codepoint <= 0xD7FF) or
      codepoint == 0x9 or codepoint == 0xA or codepoint == 0xD or
      (codepoint >= 0xE000 and codepoint <= 0xFFFD) or
      (codepoint >= 0x10000 and codepoint <= 0x10FFFF)
  end

  def valid_pi_name?(<<l::integer, m::integer, x::integer>>)
      when x in [?X, ?x] or m in [?M, ?m] or l in [?L, ?l],
      do: false

  def valid_pi_name?(<<_::bits>>), do: true

  def valid_encoding?(encoding), do: String.upcase(encoding, :ascii) == "UTF-8"
end
