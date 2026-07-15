defmodule SassoneTest.Utils do
  @moduledoc false

  use ExUnitProperties

  import ExUnit.Assertions

  def remove_indents(xml) do
    xml
    |> String.split("\n")
    |> Enum.map_join(&String.trim/1)
  end

  def parse(data, handler, state, options \\ []) do
    assert result = Sassone.parse_string(data, handler, state, options)
    assert Sassone.parse_stream([data], handler, state, options) == result

    result
  end

  def read_fixture(name) do
    "test/support/fixture/"
    |> Kernel.<>(name)
    |> Path.relative_to_cwd()
    |> File.read!()
  end

  def stream_fixture(name) do
    "test/support/fixture/"
    |> Kernel.<>(name)
    |> Path.relative_to_cwd()
    |> File.stream!(100)
  end

  def xml_quote, do: one_of([constant(?"), constant(?')])

  def xml_equal_sign do
    gen all s1 <- xml_whitespace(),
            s2 <- xml_whitespace() do
      s1 <> "=" <> s2
    end
  end

  def xml_whitespace(options \\ []) do
    string([0xA, 0x9, 0xD, 0x20], options)
  end
end
