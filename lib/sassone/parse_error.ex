defmodule Sassone.ParseError do
  @moduledoc """
  Returned when parser encounters errors during parsing.
  """

  @type reason() ::
          {:token, token :: String.t()}
          | {:wrong_closing_tag, open_tag :: String.t(), close_tag :: String.t()}
          | {:invalid_pi, pi_name :: String.t()}
          | {:invalid_encoding, encoding :: String.t()}
          | {:invalid_char_ref, codepoint :: non_neg_integer() | :too_long}
          | {:bad_return, {event :: atom(), return :: term()}}

  @type t() :: %__MODULE__{reason: reason(), binary: String.t(), position: non_neg_integer()}
  defexception [:reason, :binary, :position]

  @impl Exception
  def message(%__MODULE__{reason: {:token, token}, binary: binary, position: position})
      when position == byte_size(binary) do
    "unexpected end of input, expected token: #{inspect(token)}"
  end

  @impl Exception
  def message(%__MODULE__{reason: {:token, token}} = exception) do
    "unexpected byte #{inspect(<<:binary.at(exception.binary, exception.position)>>)}, expected token: #{inspect(token)}"
  end

  @impl Exception
  def message(%__MODULE__{reason: {:wrong_closing_tag, open_tag, end_tag}}) do
    "unexpected end tag #{inspect(end_tag)}, expected tag: #{inspect(open_tag)}"
  end

  @impl Exception
  def message(%__MODULE__{reason: {:invalid_pi, pi_name}}) do
    "unexpected target name #{inspect(pi_name)} at the start of processing instruction, the target names \"XML\", \"xml\", and so on are reserved for standardization"
  end

  @impl Exception
  def message(%__MODULE__{reason: {:invalid_encoding, encoding}}) do
    "unexpected encoding declaration #{inspect(encoding)}, only UTF-8 is supported"
  end

  @impl Exception
  def message(%__MODULE__{reason: {:invalid_char_ref, :too_long}}) do
    "unexpected character reference, too many digits"
  end

  @impl Exception
  def message(%__MODULE__{reason: {:invalid_char_ref, codepoint}}) do
    "unexpected character reference to code point #{codepoint}, which is not a valid XML character"
  end

  @impl Exception
  def message(%__MODULE__{reason: {:bad_return, {event, return}}}) do
    "unexpected return #{inspect(return)} in #{inspect(event)} event handler"
  end
end
