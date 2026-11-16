defmodule SpaceTAPFixturesPyvoTest do
  # Parity tests on the VOTable fixtures: SpaceTAP and PyVO read each file,
  # and must give the same columns, overflow and value in every cell. They
  # need PyVO but no network, so CI runs them, and they are tagged
  # :pyvo_fixtures, excluded by default, to keep Python out of `mix test`:
  # run them with `mix test --only pyvo_fixtures`. Every XML fixture is read,
  # so a new one is compared without listing it here. Error documents, and
  # the list of jobs Gaia sent, are files both refuse.
  use ExUnit.Case, async: true

  alias SpaceTAP.Test.Pyvo

  @moduletag :pyvo_fixtures

  @fixtures Path.expand("fixtures", __DIR__)
  @paths @fixtures |> Path.join("*/*.xml") |> Path.wildcard()

  if reason = Pyvo.skip_reason() do
    @moduletag skip: reason
  else
    setup_all do
      %{pyvo: Pyvo.read_files(@paths)}
    end
  end

  for path <- @paths do
    @path path

    test "matches PyVO on #{Path.relative_to(path, @fixtures)}", %{pyvo: pyvo} do
      Pyvo.assert_file_parity(@path, Map.fetch!(pyvo, @path))
    end
  end
end
