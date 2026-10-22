# Integration tests hit real TAP services and parity tests also need pyvo.
# Run them with `mix test --include integration` and `mix test --only pyvo`.
ExUnit.start(exclude: [:integration, :pyvo])
