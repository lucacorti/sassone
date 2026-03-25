defmodule Sassone.Builder.Field do
  @moduledoc """
  A struct representing the builder options for a struct field.
  """

  @type t :: %__MODULE__{
          build: boolean(),
          many: boolean(),
          name: atom(),
          namespace: String.t() | nil,
          parse: boolean(),
          struct: module(),
          type: :attribute | :content | :element,
          xml_name: String.t()
        }

  @enforce_keys [:name, :type, :xml_name]
  defstruct build: true,
            many: false,
            name: nil,
            namespace: nil,
            parse: true,
            struct: nil,
            type: nil,
            xml_name: nil

  schema = [
    attribute_case: [
      doc: "Rename the struct fields of type `:attribute` with the given strategy in XML.",
      type: {:in, [:pascal, :camel, :snake, :kebab]},
      default: :snake
    ],
    debug: [doc: "Enable debug for parser generation.", type: :boolean, default: false],
    element_case: [
      doc: "Rename the struct fields of type `:element` with the given strategy in XML.",
      type: {:in, [:pascal, :camel, :snake, :kebab]},
      default: :pascal
    ],
    fields: [
      doc:
        "Struct fields to map to XML. The order of elements will be preserved in the generated XML.",
      type: :keyword_list,
      keys: [
        *: [
          type: :keyword_list,
          keys: [
            parse: [
              doc: "If false, the struct field won't be parsed from XML.",
              type: :boolean,
              default: true
            ],
            build: [
              doc: "If false, the field will be ignored when building the struct to XML.",
              type: :boolean,
              default: true
            ],
            many: [
              doc: "Specifies if the field must be handled as a list.",
              type: :boolean,
              default: false
            ],
            name: [
              doc: "Custom field name for parsing and building. It will be used as-is.",
              type: :string
            ],
            namespace: [
              doc: "Namespace to apply to the field. It will be used as-is.",
              type: {:or, [:string, nil]},
              default: nil
            ],
            struct: [
              doc: "A struct deriving `Sassone.Builder` used to parse and build this element.",
              type: :atom
            ],
            type: [
              doc: "How the field is represented in XML: `:element`, `:attribute`, `:content`.",
              type: {:in, [:attribute, :content, :element]},
              default: :element
            ]
          ]
        ]
      ],
      required: true
    ],
    namespace: [
      doc: "XML namespace of the element.",
      type: {:or, [:string, nil]},
      default: nil
    ],
    root_element: [
      doc: "XML root element. This applies only to the toplevel struct when parsing.",
      type: :string
    ]
  ]

  def __schema__, do: unquote(schema)
end
