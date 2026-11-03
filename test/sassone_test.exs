defmodule SassoneTest do
  use SassoneTest.ParsingCase, async: true

  alias Sassone.TestHandlers.{ControlHandler, StackHandler}

  doctest Sassone

  @fixtures [
    "no-xml-decl.xml",
    "no-xml-decl-with-std-pi.xml",
    "no-xml-decl-with-custom-pi.xml",
    "foo.xml",
    "food.xml",
    "complex.xml",
    "illustrator.svg",
    "unicode.xml"
  ]

  test "parses XML document binary and streams" do
    for fixture_name <- @fixtures do
      data = read_fixture(fixture_name)
      assert {:ok, _state} = parse(data, StackHandler, [])
    end
  end

  test "parses file streams" do
    for fixture_name <- @fixtures do
      stream = stream_fixture(fixture_name)
      assert {:ok, _state} = Sassone.parse_stream(stream, StackHandler, [])
    end
  end

  test "maps file streams" do
    for fixture <- @fixtures do
      stream = stream_fixture(fixture)
      element_stream = Sassone.stream_events(stream)
      assert [_ | _] = Enum.to_list(element_stream)
    end

    assert_raise Sassone.ParseError, fn ->
      Enum.to_list(Sassone.stream_events(stream_fixture("incorrect.xml")))
    end
  end

  test "parse_string/4 parses XML binary with multiple \":expand_entity\" strategy" do
    data = "<foo>Something &unknown;</foo>"

    assert {:ok, state} = parse(data, StackHandler, [], expand_entity: :keep)

    assert state == [
             {:end_document, {}},
             {:end_element, {nil, "foo"}},
             {:characters, "Something &unknown;"},
             {:start_element, {nil, "foo", []}},
             {:start_document, []}
           ]

    assert {:ok, state} = parse(data, StackHandler, [], expand_entity: :skip)

    assert state == [
             {:end_document, {}},
             {:end_element, {nil, "foo"}},
             {:characters, "Something "},
             {:start_element, {nil, "foo", []}},
             {:start_document, []}
           ]

    assert {:ok, state} =
             parse(data, StackHandler, [], expand_entity: {__MODULE__, :convert_entity, []})

    assert state == [
             {:end_document, {}},
             {:end_element, {nil, "foo"}},
             {:characters, "Something known"},
             {:start_element, {nil, "foo", []}},
             {:start_document, []}
           ]
  end

  test "parse_string/4 parses XML binary with closing tags containing whitespaces" do
    data = "<foo>Some data</foo    >"

    assert {:ok, state} = parse(data, StackHandler, [])

    assert state == [
             end_document: {},
             end_element: {nil, "foo"},
             characters: "Some data",
             start_element: {nil, "foo", []},
             start_document: []
           ]
  end

  test "handles trailing Unicode codepoints during streaming" do
    data = "<foo>𠜎𠜱𠝹𠱓</foo>"
    stream = for byte <- :binary.bin_to_list(data), do: <<byte>>

    assert {:ok, event_stack} = Sassone.parse_stream(stream, StackHandler, [])

    assert event_stack == [
             {:end_document, {}},
             {:end_element, {nil, "foo"}},
             {:characters, "𠜎𠜱𠝹𠱓"},
             {:start_element, {nil, "foo", []}},
             {:start_document, []}
           ]
  end

  test "parse_stream/4 emits characters when they reach the max length limit" do
    character_data_max_length = 32
    first_chunk = String.duplicate("x", character_data_max_length)
    second_chunk = String.duplicate("y", character_data_max_length)

    doc = String.codepoints(~s(<foo>#{first_chunk}#{second_chunk}</foo>))

    assert {:ok, state} =
             Sassone.parse_stream(doc, StackHandler, [],
               character_data_max_length: character_data_max_length
             )

    assert state == [
             end_document: {},
             end_element: {nil, "foo"},
             characters: "",
             characters: second_chunk,
             characters: first_chunk,
             start_element: {nil, "foo", []},
             start_document: []
           ]

    assert {:ok, state} = Sassone.parse_stream(doc, StackHandler, [])

    assert state == [
             end_document: {},
             end_element: {nil, "foo"},
             characters: first_chunk <> second_chunk,
             start_element: {nil, "foo", []},
             start_document: []
           ]
  end

  test "handles errors occurred during parsing" do
    data = "<?xml ?><foo/>"
    assert {:error, exception} = parse(data, StackHandler, [])
    assert Exception.message(exception) == "unexpected byte \"?\", expected token: :version"

    data = "<?xml ?><foo/>"
    assert {:error, exception} = parse(data, StackHandler, [])
    assert Exception.message(exception) == "unexpected byte \"?\", expected token: :version"

    data = "<?xml"
    assert {:error, exception} = parse(data, StackHandler, [])
    assert Exception.message(exception) == "unexpected end of input, expected token: :version"

    data = "<foo><bar></bee></foo>"
    assert {:error, exception} = parse(data, StackHandler, [])
    assert Exception.message(exception) == "unexpected end tag \"bee\", expected tag: \"bar\""

    data = "<foo>Some data</foo    bar >"
    assert {:error, exception} = parse(data, StackHandler, [])

    assert Exception.message(exception) ==
             "unexpected end tag \"foo   \", expected tag: \"foo\""
  end

  describe "encode!/2" do
    import Sassone.XML

    test "encodes XML document into string" do
      root = element("foo", [], ["foo"])
      assert Sassone.encode!(root, version: "1.0") == ~s(<?xml version="1.0"?><foo>foo</foo>)
    end
  end

  describe "encode_to_iodata!/2" do
    import Sassone.XML

    test "encodes XML document into IO data" do
      root = element("foo", [], ["foo"])
      assert xml = Sassone.encode_to_iodata!(root, version: "1.0")
      assert is_list(xml)
      assert IO.iodata_to_binary(xml) == ~s(<?xml version="1.0"?><foo>foo</foo>)
    end
  end

  @events [
    :start_document,
    :start_element,
    :characters,
    :end_element,
    :end_document
  ]

  for event <- @events do
    test "allows stopping the parsing process on #{inspect(event)}" do
      data = "<?xml version=\"1.0\" ?><foo>foo</foo>"
      assert_parse_stop(data, unquote(event))
    end
  end

  defp assert_parse_stop(data, stop_event) do
    value = make_ref()
    state = {stop_event, {:stop, value}}

    assert parse(data, ControlHandler, state) == {:ok, value}
  end

  describe "parser halting" do
    test "halts the parsing process and returns the rest of the binary" do
      data = "<?xml version=\"1.0\" ?><foo/>"
      assert parse_halt(data, :start_document) == "<foo/>"
      assert parse_halt(data, :start_element) == ""
      assert parse_halt(data, :end_element) == ""
      assert parse_halt(data, :end_document) == ""

      data = "<?xml version=\"1.0\" ?><foo>foo</foo>"
      assert parse_halt(data, :start_element) == "foo</foo>"
      assert parse_halt(data, :characters) == "</foo>"
      assert parse_halt(data, :end_element) == ""

      data = "<?xml version=\"1.0\" ?><foo>foo <bar/></foo>"
      assert parse_halt(data, {:start_element, {nil, "foo", []}}) == "foo <bar/></foo>"
      assert parse_halt(data, {:characters, "foo "}) == "<bar/></foo>"
      assert parse_halt(data, {:start_element, {nil, "bar", []}}) == "</foo>"
      assert parse_halt(data, {:end_element, {nil, "bar"}}) == "</foo>"
      assert parse_halt(data, {:end_element, {nil, "foo"}}) == ""
      assert parse_halt(data <> "trailing", {:end_element, {nil, "foo"}}) == "trailing"

      data = "<?xml version=\"1.0\" ?><foo><![CDATA[foo]]></foo>"
      assert parse_halt(data, {:characters, "foo"}) == "</foo>"
    end
  end

  defp parse_halt(data, halt_event) do
    value = make_ref()
    state = {halt_event, {:halt, value}}

    assert {:halt, ^value, rest} = parse(data, ControlHandler, state)

    rest
  end

  for event <- @events do
    test "errs on handler invalid returning on #{event}" do
      event = unquote(event)
      data = "<?xml version=\"1.0\" ?><foo>foo</foo>"
      value = System.unique_integer()

      assert {:error, error} = parse(data, ControlHandler, {event, value})

      assert Exception.message(error) ==
               "unexpected return #{value} in #{inspect(event)} event handler"
    end
  end

  def convert_entity("unknown"), do: "known"

  describe "encode" do
    test "encodes empty element" do
      document = {
        nil,
        "person",
        [{nil, "first_name", "John"}, {nil, "last_name", "Doe"}],
        []
      }

      xml = Sassone.encode!(document, version: "1.0")

      assert xml == ~s(<?xml version="1.0"?><person first_name="John" last_name="Doe"/>)
    end

    test "encodes normal element" do
      content = [{:characters, "Hello my name is John Doe"}]

      document = {
        nil,
        "person",
        [{nil, "first_name", "John"}, {nil, "last_name", "Doe"}],
        content
      }

      xml = Sassone.encode!(document, version: "1.0")

      assert xml ==
               ~s(<?xml version="1.0"?><person first_name="John" last_name="Doe">Hello my name is John Doe</person>)
    end

    test "encodes attributes with escapable characters" do
      xml = Sassone.encode!({nil, "person", [{nil, "first_name", "&'\"<>"}], []})

      assert xml == ~s(<person first_name="&amp;&apos;&quot;&lt;&gt;"/>)
    end

    test "encodes CDATA" do
      children = [{:cdata, "Tom & Jerry"}]

      document = {nil, "person", [], children}
      xml = Sassone.encode!(document, version: "1.0")

      assert xml == ~s(<?xml version="1.0"?><person><![CDATA[Tom & Jerry]]></person>)
    end

    test "splits CDATA terminators into adjacent sections" do
      for encoder <- [&Sassone.encode!/1, &Sassone.encode_to_iodata!/1] do
        document = {nil, "body", [], [{:cdata, "before]]>after]]>"}]}

        assert IO.iodata_to_binary(encoder.(document)) ==
                 "<body><![CDATA[before]]]]><![CDATA[>after]]]]><![CDATA[>]]></body>"
      end
    end

    test "encodes a single byte in a direct CDATA tuple" do
      for encoder <- [&Sassone.encode!/1, &Sassone.encode_to_iodata!/1] do
        assert IO.iodata_to_binary(encoder.({nil, "body", [], [{:cdata, ?A}]})) ==
                 "<body><![CDATA[A]]></body>"
      end
    end

    test "encodes characters to references" do
      content = [
        {:characters, "Tom & Jerry"}
      ]

      document = {nil, "movie", [], content}
      xml = Sassone.encode!(document, version: "1.0")

      assert xml == ~s(<?xml version="1.0"?><movie>Tom &amp; Jerry</movie>)
    end

    test "supports mentioning utf-8 encoding in the prolog (as atom)" do
      document = {nil, "body", [], []}

      xml = Sassone.encode!(document, version: "1.0", encoding: :utf8)
      assert xml == ~s(<?xml version="1.0" encoding="utf-8"?><body/>)
    end

    test "supports mentioning UTF-8 encoding in the prolog (as string)" do
      document = {nil, "body", [], []}

      xml = Sassone.encode!(document, version: "1.0", encoding: "UTF-8")
      assert xml == ~s(<?xml version="1.0" encoding="UTF-8"?><body/>)

      xml = Sassone.encode!(document, version: "1.0", encoding: "utf-8")
      assert xml == ~s(<?xml version="1.0" encoding="utf-8"?><body/>)
    end

    test "encodes reference" do
      content = [
        {:reference, {:entity, "foo"}},
        {:reference, {:hexadecimal, ?<}},
        {:reference, {:decimal, ?<}}
      ]

      document = {nil, "movie", [], content}
      xml = Sassone.encode!(document, [])

      assert xml == ~s(<?xml version="1.0"?><movie>&foo;&#x3C;&#60;</movie>)
    end

    test "encodes comments" do
      content = [
        {:comment, "This is obviously a comment"},
        {:comment, "A+, A, A-"}
      ]

      document = {nil, "movie", [], content}
      xml = Sassone.encode!(document)

      assert xml == ~s(<movie><!--This is obviously a comment--><!--A+, A, A- --></movie>)
    end

    test "encodes processing instruction" do
      content = [
        {:processing_instruction, "xml-stylesheet", "type=\"text/xsl\" href=\"style.xsl\""}
      ]

      document = {nil, "movie", [], content}
      xml = Sassone.encode!(document, version: "1.0")

      assert xml ==
               ~s(<?xml version="1.0"?><movie><?xml-stylesheet type="text/xsl" href="style.xsl"?></movie>)
    end

    test "encodes nested element" do
      children = [
        {nil, "address", [{nil, "street", "foo"}, {nil, "city", "bar"}], []},
        {nil, "gender", [], [{:characters, "male"}]}
      ]

      document =
        {nil, "person", [{nil, "first_name", "John"}, {nil, "last_name", "Doe"}], children}

      xml = Sassone.encode!(document)

      assert xml ==
               ~s(<person first_name="John" last_name="Doe"><address street="foo" city="bar"/><gender>male</gender></person>)
    end

    test "integration with builder" do
      import Sassone.XML

      items =
        for index <- 1..2 do
          element("item", [], [
            element("title", [], ["Item #{index}"]),
            element("link", [], ["Link #{index}"]),
            comment("Comment #{index}"),
            element("description", [], [cdata("<a></b>")]),
            characters("ABCDEFG"),
            reference(:entity, "copyright")
          ])
        end

      xml =
        element("rss", [attribute("version", 2.0)], items)
        |> Sassone.encode!(version: "1.0")

      expected = """
      <?xml version="1.0"?>
      <rss version="2.0">
      <item>
      <title>Item 1</title>
      <link>Link 1</link>
      <!--Comment 1-->
      <description><![CDATA[<a></b>]]></description>
      ABCDEFG
      &copyright;
      </item>
      <item>
      <title>Item 2</title>
      <link>Link 2</link>
      <!--Comment 2-->
      <description><![CDATA[<a></b>]]></description>
      ABCDEFG
      &copyright;
      </item>
      </rss>
      """

      assert xml == String.replace(expected, "\n", "")
    end

    test "generates deeply nested document" do
      {document, xml} =
        Enum.reduce(100..1//-1, {"content", "content"}, fn index, {document, xml} ->
          {
            Sassone.XML.element("level#{index}", [], [document]),
            "<level#{index}>#{xml}</level#{index}>"
          }
        end)

      xml = "<?xml version=\"1.0\"?>" <> xml

      assert Sassone.encode!(document, version: "1.0") == xml
    end

    test "encodes non expanded entity reference" do
      document = {nil, "foo", [], [{nil, "event", [], ["test &apos; test"]}]}
      assert "<foo><event>test &apos; test</event></foo>" == Sassone.encode!(document)
    end
  end
end
