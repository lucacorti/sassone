Sassone
====

[![Test suite](https://github.com/lucacorti/sassone/actions/workflows/test.yml/badge.svg)](https://github.com/lucacorti/sassone/actions/workflows/test.yml)
[![Module Version](https://img.shields.io/hexpm/v/sassone.svg)](https://hex.pm/packages/sassone)

Sassone is an XML SAX parser and encoder in Elixir that focuses on speed, usability and standard compliance.

Sassone was born as a fork of the great [saxy][saxy] library to fix bugs, address some limitations
with XML standards compliance and add some missing features like namespaces and mapping to structs.

Comply with [Extensible Markup Language (XML) 1.0 (Fifth Edition)](https://www.w3.org/TR/xml/).

## Features highlight

* An incredibly fast XML 1.0 SAX parser.
* An extremely fast XML encoder.
* Native support for streaming parsing large XML files.
* Support for automatically building and parsing XML with structs.

## Installation

Add `:sassone` to your `mix.exs`.

```elixir
def deps() do
  [
    {:sassone, "~> 1.0"}
  ]
end
```

## Overview

Full documentation is available on [HexDocs](https://hexdocs.pm/sassone/).

If you never work with a SAX parser before, please check out [this
guide][sax-guide].

## SAX parser

A SAX event handler implementation is required before starting parsing.

```elixir
defmodule MyEventHandler do
  @behaviour Sassone.Handler

  @impl Sassone.Handler
  def handle_event(:start_document, prolog, state) do
    IO.inspect("Start parsing document")
    {:ok, [{:start_document, prolog} | state]}
  end

  @impl Sassone.Handler
  def handle_event(:end_document, _data, state) do
    IO.inspect("Finish parsing document")
    {:ok, [{:end_document} | state]}
  end

  @impl Sassone.Handler
  def handle_event(:start_element, {namespace, name, attributes}, state) do
    IO.inspect("Start parsing element #{namespace}:#{name} with attributes #{inspect(attributes)}")
    {:ok, [{:start_element, {namespace, name, attributes}} | state]}
  end

  @impl Sassone.Handler
  def handle_event(:end_element, {namespave, name}, state) do
    IO.inspect("Finish parsing element #{namespace}:#{name}")
    {:ok, [{:end_element, {namespace, name}} | state]}
  end

  @impl Sassone.Handler
  def handle_event(:characters, chars, state) do
    IO.inspect("Receive characters #{chars}")
    {:ok, [{:characters, chars} | state]}
  end

  @impl Sassone.Handler
  def handle_event(:cdata, cdata, state) do
    IO.inspect("Receive CData #{cdata}")
    {:ok, [{:cdata, cdata} | state]}
  end
end
```

Then start parsing XML documents with:

```elixir
iex> xml = "<?xml version='1.0' ?><foo bar='value'></foo>"
iex> Sassone.parse_string(xml, MyEventHandler, [])
{:ok,
 [{:end_document},
  {:end_element, {nil, "foo"}},
  {:start_element, {nil, "foo"}, [{nil, "bar", "value"}]},
  {:start_document, [version: "1.0"]}]}
```

## Streaming parser

Sassone also accepts file stream as the input:

```elixir
File.stream!("/path/to/file")
|> Sassone.parse_stream(MyEventHandler, initial_state)
```

It even supports parsing a normal stream.

```elixir
File.stream!("/path/to/file")
|> Stream.filter(&(&1 != "\n"))
|> Sassone.parse_stream(MyEventHandler, initial_state)
```

## Partial parsing

Sassone can parse an XML document partially. This feature is useful when the
document cannot be turned into a stream e.g receiving over socket.

```elixir
{:ok, partial} = Partial.new(MyEventHandler, initial_state)
{:cont, partial} = Partial.parse(partial, "<foo>")
{:cont, partial} = Partial.parse(partial, "<bar></bar>")
{:cont, partial} = Partial.parse(partial, "</foo>")
{:ok, state} = Partial.terminate(partial)
```

## Generate XML

Use `Sassone.XML` to build and compose XML simple form, then `Sassone.encode!/2`
to encode the built element into XML binary.

```elixir
iex> import Sassone.XML
iex> element = element("person", [gender: "female"], [characters("Alice")])
{nil, "person", [{"gender", "female"}], [{:characters, "Alice"}]}
iex> Sassone.encode!(element, [])
"<?xml version=\"1.0\" encoding=\"utf-8\"?><person gender=\"female\">Alice</person>"
```

See `Sassone.XML` for the full XML building API documentation.

## Struct driven XML parsing and generation

You can derive or implement `Sassone.Builder` for your structs to
automatically generate the parsers and builders for them.

```elixir
defmodule Person do
  @derive {
    Sassone.Builder,
    root_element: "person",
    fields: [gender: [type: :attribute], name: [type: :content]
  }
  defstruct [:gender, :name]
end
```

To generate an XML document for your struct by calling:

```elixir
iex> Sassone.XML.build(%Person{gender: "female", name: "Alice"}) |> Sassone.encode!()
"<?xml version=\"1.0\" encoding=\"utf-8\"?><person gender=\"female\">Alice</person>"
```

And you can now parse an XML document and obtain a map by calling:

```elixir
iex> {:ok, {struct, map}} = Sassone.parse_string(data, Sassone.Builder.handler(%Person{}), nil)
{:ok, {Person, %{gender: "female", name: "Alice"}}}
```

You can then use the map to create the struct you need:

```elixir
iex> struct(struct, map)
%Person{gender: "female", name: "Alice"}
```

In case of deeply nested data or custom data types, this can prove difficult. In that case, you
can use a library to handle the conversion to struct. `Ecto` with embedded schemas is great to
cast and validate data.

For example, assuming you defined `Person` as an embedded `Ecto` schema with a `changeset/2` function:

```elixir
defmodule Person do
  @derive {
    Sassone.Builder,
    root_element: "person",
    fields: [gender: [type: :attribute], name: [type: :content]
  }
  embedded_schema do
    field :gender
    field :name
  end

  def changeset(person, params) do
    person
    |> cast([:gender, :name)
  end
end
```

```elixir
iex> struct.changeset(struct(schema), map) |> Ecto.Changeset.apply_action(:cast)
{:ok, %Person{gender: "female", name: "Alice"}}
```

See `Sassone.Builder` for the full Builder API documentation.

## FAQs with Sassone/XMLs

### Does Sassone work with XPath?

Sassone in its core is a SAX parser, therefore Sassone does not, and likely will
not, offer any XPath functionality.

[SweetXml][sweet_xml] is a wonderful library to work with XPath. However,
`:xmerl`, the library used by SweetXml, is not always memory efficient and
speedy. You can combine the best of both sides with [Saxmerl][saxmerl], which
is a Saxy extension converting XML documents into SweetXml compatible format.
Please check that library out for more information.

### Sassone! Where did the name come from?

[Sassone](https://www.treccani.it/vocabolario/sassone/) is an italian word with
two different meanings, depending how you pronounce it:

1. `Sàssone` is the equivalent of the english word Saxon, a member of a people
   that inhabited parts of central and northern Germany from Roman times, many
   of whom conquered and settled in much of southern England in the 5th–6th centuries.
2. `Sassòne` is a big rock (`sasso` in italian). e.g. `"Va che bel sassone!"` roughly
    translates to `"What a nice big rock!"` in english.

## Benchmarking

Note that benchmarking XML parsers is difficult and highly depends on the complexity
of the documents being parsed. Event I try hard to make the benchmarking suite
fair but it's hard to avoid biases when choosing the documents to benchmark
against.

Therefore the conclusion in this section is only for reference purpose. Please
feel free to benchmark against your target documents. The benchmark suite can be found
in [bench/](https://github.com/lucacorti/sassone/tree/main/bench).

A rule of thumb is that we should compare apple to apple. Some XML parsers
target only specific types of XML. Therefore some indicators are provided in the
test suite to let know of the fairness of the benchmark results.

Some quick and biased conclusions from the benchmark suite:

* For SAX parser, Sassone is usually 1.4 times faster than [Erlsom](https://github.com/willemdj/erlsom).
  With deeply nested documents, Sassone is noticeably faster (4 times faster).
* For XML builder and encoding, Sassone is usually 10 to 30 times faster than [XML Builder](https://github.com/joshnuss/xml_builder).
  With deeply nested documents, it could be 180 times faster.
* Sassone significantly uses less memory than XML Builder (4 times to 25 times).
* Sassone significantly uses less memory than Xmerl, Erlsom and Exomler (1.4 times to 10 times).

## Limitations

* No XSD supported.
* No DTD supported, when Sassone encounters a `<!DOCTYPE`, it skips that.
* Only support UTF-8 encoding.

## Contributing

If you have any issues or ideas, feel free to write to https://github.com/lucacorti/sassone/issues.

To start developing:

1. Fork the repository.
2. Write your code and related tests.
3. Create a pull request at https://github.com/lucacorti/sassone/pulls.

## Copyright and License

Copyright (c) 2018-2024 Cẩm Huỳnh
Copyright (c) 2024 Luca Corti

This software is licensed under [the MIT license](./LICENSE.md).

[saxy]: https://github.com/qcam/saxy
[saxmerl]: https://github.com/qcam/saxmerl
[sweet_xml]: https://github.com/kbrw/sweet_xml
[sax-guide]: https://hexdocs.pm/sassone/getting-started-with-sax.html
