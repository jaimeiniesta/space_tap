<p align="center">
  <img src="assets/space_tap_logo.png" alt="SpaceTAP: an Elixir client for the IVOA Table Access Protocol" width="400">
</p>

# SpaceTAP

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `space_tap` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:space_tap, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/space_tap>.

## Testing

Run the default unit test suite without network access:

```sh
mix test
```

Integration tests are excluded from the default suite. Run the Gaia live
integration tests together with the default suite, with network access, using:

```sh
mix test --include integration
```

Run the unit, Gaia integration and Gaia/pyvo parity suites together:

```sh
mix test.all
```

The complete suite requires network access and
[`uv`](https://docs.astral.sh/uv/). Run it locally before a release.
