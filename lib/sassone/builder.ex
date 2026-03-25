defprotocol Sassone.Builder do
  @moduledoc """
  Protocol to implement XML building and parsing for structs.

  You can derive or implement this protocol for your structs.
  When deriving the protocol, these are the supported options:

  #{Sassone.Builder.Field.__schema__() |> NimbleOptions.new!() |> NimbleOptions.docs()}

  The builder allows nesting of other structs implementing `Sassone.Builder`
  via the `struct` field option.

  The generated parser returns a map with atom keys you can pass to  `struct/2`
  or `struct!/2` to obtain a struct.

  > #### Data validation {: .neutral}
  >
  > Transforming a map with nested structs and/or values into data
  > types other than strings, such as dates, datetimes, etc. might
  > prove complex and error prone and is out of scope for `Sassone`.
  >
  > In this case, using a library to define your struct, validate and
  > transform your data, both before building and after parsing, is
  > probably a good idea.
  >
  > `Ecto` with [embedded schemas](https://hexdocs.pm/ecto/embedded-schemas.html)
  > is a great way to do this, and naturally fits the `Sassone.Builder` model.

  > #### XML elements order {: .warning}
  >
  > In XML documents, the order in which elements appear is meaningful.
  >
  > The builder protocol preserves field ordering, so if you need fields to be
  > mapped to elments appearing in a a specific order in XML when building with
  > `Sassone.XML.build/1`, be sure to list them in that spefic order in the `fields`
  > option.
  >
  > Also note that ordering is not enforced by the parser, so parsing is not strict
  > in that sense and the generated parser will parse elements refardless of the order
  > in which they appear in the XML document.
  """

  alias Sassone.Builder.Field

  @typedoc "A strut implementing `Sassone.Builder`"
  @type t :: struct()

  @doc """
  Returns the mapping of attributes for the struct.
  """
  @spec attributes(t()) :: [Field.t()]
  def attributes(struct)

  @doc """
  Returns the mapping of elements for the struct.
  """
  @spec elements(t()) :: [Field.t()]
  def elements(t)

  @doc """
  Returns the XML namespace for the struct.
  """
  @spec namespace(t()) :: String.t() | nil
  def namespace(t)

  @doc """
  Returns the `Sassone.Handler` implementation for the struct.
  """
  @spec handler(t()) :: module()
  def handler(t)

  @doc """
  Returns the XML root element name for the struct.
  """
  @spec root_element(t()) :: String.t() | nil
  def root_element(t)
end

defimpl Sassone.Builder, for: Any do
  alias Sassone.Builder
  alias Sassone.Builder.Field

  @moduledoc """
  Default implementation of the `Sassone.Builder` protocol for any struct.

  Options:
  #{NimbleOptions.docs(Field.__schema__())}
  """

  defmacro __deriving__(module, struct, options) do
    options =
      options
      |> normalize_default_options()
      |> Macro.prewalk(&Macro.expand(&1, __CALLER__))
      |> NimbleOptions.validate!(NimbleOptions.new!(Field.__schema__()))

    struct_members = struct |> Map.keys() |> MapSet.new()
    names = options[:fields] |> Keyword.keys() |> MapSet.new()

    if not MapSet.subset?(names, struct_members) do
      raise "Mismatching fields in the declaration. Missing fields: #{inspect(MapSet.difference(names, struct_members) |> MapSet.to_list())}"
    end

    fields =
      Enum.map(options[:fields], fn {name, field_options} ->
        case =
          if field_options[:type] == :attribute do
            options[:attribute_case]
          else
            options[:element_case]
          end

        xml_name = field_options[:name] || recase(to_string(name), case)
        %Field{} = field = struct(Field, field_options)
        %{field | xml_name: xml_name, name: name}
      end)

    {attributes, elements} =
      Enum.split_with(fields, fn %Field{} = field -> field.type == :attribute end)

    start_document = generate_start_document(module)
    end_document = generate_end_document()
    start_element = generate_start_element(elements, options[:root_element])
    characters = generate_characters(elements)
    end_element = generate_end_element(elements)

    maybe_debug(options[:debug], [
      start_document,
      end_document,
      start_element,
      characters,
      end_element
    ])

    quote do
      defimpl Sassone.Builder, for: unquote(module) do
        @behaviour Sassone.Handler

        alias Sassone.Builder.Parser
        alias Sassone.XML

        unquote(start_document)
        unquote(end_document)
        unquote(start_element)
        unquote(characters)
        unquote(end_element)

        def attributes(_t), do: unquote(Macro.escape(attributes))
        def elements(_t), do: unquote(Macro.escape(elements))
        def handler(_t), do: __MODULE__
        def namespace(_t), do: unquote(options[:namespace])
        def root_element(_t), do: unquote(options[:root_element])
      end
    end
  end

  def attributes(_t), do: []
  def elements(_t), do: []
  def handler(_t), do: nil
  def namespace(_t), do: nil
  def root_element(_t), do: nil

  defp maybe_debug(true = _debug, code) do
    for funcs <- code, do: funcs |> Macro.to_string() |> IO.puts()
  end

  defp maybe_debug(_debug, _funcs), do: :ok

  defp normalize_default_options(options) do
    {_, options} =
      get_and_update_in(options, [:fields, Access.all()], fn
        field when is_tuple(field) -> {field, field}
        field -> {field, {field, []}}
      end)

    options
  end

  defp recase(name, :pascal), do: Recase.to_pascal(name)
  defp recase(name, :camel), do: Recase.to_camel(name)
  defp recase(name, :snake), do: Recase.to_snake(name)
  defp recase(name, :kebab), do: Recase.to_kebab(name)

  defp generate_start_document(module) do
    quote do
      @impl Sassone.Handler
      def handle_event(:start_document, _data, _parser) do
        {:ok, %Parser{struct: unquote(module), handlers: [__MODULE__]}}
      end
    end
  end

  defp generate_end_document do
    quote do
      @impl Sassone.Handler
      def handle_event(:end_document, _data, %Parser{} = parser) do
        {:ok, {parser.struct, parser.state}}
      end
    end
  end

  defp generate_start_element(elements, root_element) do
    Enum.filter(elements, fn %Field{} = field -> field.parse end)
    |> Enum.reduce(
      [
        quote do
          @impl Sassone.Handler
          def handle_event(
                :start_element,
                {_ns, unquote(root_element), attributes},
                %Parser{depth: 0} = parser
              ) do
            {
              :ok,
              %{
                parser
                | state: Parser.parse_attributes(struct(parser.struct), attributes)
              }
            }
          end
        end,
        quote do
          @impl Sassone.Handler
          def handle_event(:start_element, _data, %Parser{} = parser),
            do: {:ok, %{parser | depth: parser.depth + 1}}
        end
      ],
      fn
        %Field{struct: nil} = field, functions ->
          [
            quote do
              @impl Sassone.Handler
              def handle_event(
                    :start_element,
                    {_ns, unquote(field.xml_name) = element, _attributes} = data,
                    %Parser{} = parser
                  ) do
                {
                  :ok,
                  %{
                    parser
                    | depth: parser.depth + 1,
                      elements: [unquote(field.xml_name) | parser.elements],
                      keys: [unquote(field.name) | parser.keys]
                  }
                }
              end
            end
            | functions
          ]

        %Field{many: false} = field, functions ->
          [
            quote do
              @impl Sassone.Handler
              def handle_event(
                    :start_element,
                    {_ns, unquote(field.xml_name) = element, attributes} = data,
                    %Parser{} = parser
                  ) do
                {
                  :cont,
                  unquote(Builder.handler(struct(field.struct))),
                  %{
                    parser
                    | depth: 0,
                      elements: [unquote(field.xml_name) | parser.elements],
                      keys: [unquote(field.name) | parser.keys],
                      handlers: [unquote(Builder.handler(struct(field.struct))) | parser.handlers],
                      state:
                        put_in(
                          parser.state,
                          Enum.reverse([unquote(field.name) | parser.keys]),
                          Parser.parse_attributes(struct(unquote(field.struct)), attributes)
                        )
                  }
                }
              end
            end
            | functions
          ]

        %Field{many: true} = field, functions ->
          [
            quote do
              @impl Sassone.Handler
              def handle_event(
                    :start_element,
                    {_ns, unquote(field.xml_name) = element, attributes} = data,
                    %Parser{} = parser
                  ) do
                attributes =
                  Parser.parse_attributes(struct(unquote(field.struct)), attributes)

                {
                  :cont,
                  unquote(Builder.handler(struct(field.struct))),
                  %{
                    parser
                    | depth: 0,
                      elements: [:__LAST__, unquote(field.xml_name) | parser.elements],
                      keys: [Access.at(-1), unquote(field.name) | parser.keys],
                      handlers: [unquote(Builder.handler(struct(field.struct))) | parser.handlers],
                      state:
                        update_in(
                          parser.state,
                          Enum.reverse([unquote(field.name) | parser.keys]),
                          fn
                            nil -> [attributes]
                            values -> values ++ [attributes]
                          end
                        )
                  }
                }
              end
            end
            | functions
          ]

        _field, functions ->
          functions
      end
    )
  end

  defp generate_characters(elements) do
    Enum.filter(elements, fn %Field{} = field -> field.parse end)
    |> Enum.reduce(
      [
        quote do
          @impl Sassone.Handler
          def handle_event(:characters, _data, state), do: {:ok, state}
        end
      ],
      fn
        %Field{struct: nil, type: :content} = field, functions ->
          [
            quote do
              @impl Sassone.Handler
              def handle_event(
                    :characters,
                    data,
                    %Parser{depth: 0} = parser
                  ) do
                {
                  :ok,
                  %{
                    parser
                    | state:
                        update_in(
                          parser.state,
                          Enum.reverse([unquote(field.name) | parser.keys]),
                          fn
                            nil -> String.trim(data)
                            value -> value <> String.trim(data)
                          end
                        )
                  }
                }
              end
            end
            | functions
          ]

        %Field{struct: nil, many: false} = field, functions ->
          [
            quote do
              @impl Sassone.Handler
              def handle_event(
                    :characters,
                    data,
                    %Parser{
                      elements: [unquote(field.xml_name) | _],
                      keys: [unquote(field.name) | _]
                    } = parser
                  ) do
                {
                  :ok,
                  %{
                    parser
                    | state:
                        update_in(parser.state, Enum.reverse(parser.keys), fn
                          nil -> String.trim(data)
                          value -> value <> String.trim(data)
                        end)
                  }
                }
              end
            end
            | functions
          ]

        %Field{struct: nil, many: true} = field, functions ->
          [
            quote do
              @impl Sassone.Handler
              def handle_event(
                    :characters,
                    data,
                    %Parser{
                      elements: [unquote(field.xml_name) | _],
                      keys: [unquote(field.name) | _]
                    } = parser
                  ) do
                {
                  :ok,
                  %{
                    parser
                    | state:
                        update_in(parser.state, Enum.reverse(parser.keys), fn
                          nil -> [String.trim(data)]
                          values -> values ++ [String.trim(data)]
                        end)
                  }
                }
              end
            end
            | functions
          ]

        _field, functions ->
          functions
      end
    )
  end

  defp generate_end_element(elements) do
    Enum.filter(elements, fn %Field{} = field -> field.parse end)
    |> Enum.reduce(
      [
        quote do
          @impl Sassone.Handler
          def handle_event(
                :end_element,
                {_ns, element},
                %Parser{
                  keys: [_index, _key | keys],
                  elements: [:__LAST__, element | elements],
                  handlers: [_current_handler, previous_handler | handlers]
                } = parser
              ) do
            {
              :cont,
              previous_handler,
              %{
                parser
                | depth: 0,
                  keys: keys,
                  elements: elements,
                  handlers: [previous_handler | handlers]
              }
            }
          end
        end,
        quote do
          @impl Sassone.Handler
          def handle_event(
                :end_element,
                {_ns, element},
                %Parser{
                  keys: [_key | keys],
                  elements: [element | elements],
                  handlers: [_current_handler, previous_handler | handlers]
                } = parser
              ) do
            {
              :cont,
              previous_handler,
              %{
                parser
                | depth: 0,
                  keys: keys,
                  elements: elements,
                  handlers: [previous_handler | handlers]
              }
            }
          end
        end,
        quote do
          @impl Sassone.Handler
          def handle_event(:end_element, _data, %Parser{} = parser),
            do: {:ok, %{parser | depth: parser.depth - 1}}
        end
      ],
      fn
        %Field{struct: nil} = field, functions ->
          [
            quote do
              @impl Sassone.Handler
              def handle_event(
                    :end_element,
                    {_ns, unquote(field.xml_name) = element},
                    %Parser{keys: [_key | keys], elements: [element | elements]} = parser
                  ) do
                {:ok, %{parser | depth: parser.depth - 1, keys: keys, elements: elements}}
              end
            end
            | functions
          ]

        %Field{many: false} = field, functions ->
          [
            quote do
              @impl Sassone.Handler
              def handle_event(
                    :end_element,
                    {_ns, unquote(field.xml_name) = element},
                    %Parser{keys: [_key | keys], elements: [element | elements]} = parser
                  ) do
                {:ok, %{parser | depth: parser.depth - 1, keys: keys, elements: elements}}
              end
            end
            | functions
          ]

        _field, functions ->
          functions
      end
    )
  end
end
