# Changelog

## v1.0.0 - 2026-03-25

* Add support for `{:cont, handler, state}` as `Saxy.Handler` callbacks return value.
  This allows for splitting the parser in multiple handlers.
* Return namespace separately from element name in `Saxy.Handler` callbacks.
  This allows pattern matching on element names, which is not possibile if the namespace is
  prefixed to it, since you cannot pattern match on a variable length string prefix.
* Remove simple form. The internal format changed, and it's not that hard to implement as a
  handler if you really want to generate simple form for some reason.
* Fix deprecation warnings on elixir 1.17 and update dependencies.
* Update CI to Elixir 1.17 and bump compatibility to elixir 1.12.
