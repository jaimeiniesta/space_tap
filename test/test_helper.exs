# Integration and services tests hit real TAP services and parity tests also
# need PyVO. Run them with `mix test --include integration`,
# `mix test.services`, `mix test --only pyvo` and, for the parity tests on
# the fixtures, which need no network, `mix test --only pyvo_fixtures`.
ExUnit.start(exclude: [:integration, :services, :pyvo, :pyvo_fixtures])
