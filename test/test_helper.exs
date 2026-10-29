# Integration and services tests hit real TAP services and parity tests also
# need PyVO. Run them with `mix test --include integration`,
# `mix test.services` and `mix test --only pyvo`.
ExUnit.start(exclude: [:integration, :services, :pyvo])
