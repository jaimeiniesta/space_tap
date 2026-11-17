defmodule SpaceTAPFixturesPyvoTest do
  # Parity tests on the VOTable fixtures: SpaceTAP and PyVO read each file,
  # and must give the same columns, overflow and value in every cell. They
  # need PyVO but no network, so CI runs them, and they are tagged
  # :pyvo_fixtures, excluded by default, to keep Python out of `mix test`:
  # run them with `mix test --only pyvo_fixtures`. Every XML fixture is read,
  # so a new one is compared without listing it here. Error documents, and
  # the list of jobs Gaia sent, are files both refuse.
  #
  # The job documents of async jobs, in the jobs folder of each service, are
  # compared the same way, by their phase, error summary and result.
  use ExUnit.Case, async: true

  alias SpaceTAP.Test.Pyvo
  alias SpaceTAP.UWS

  @moduletag :pyvo_fixtures

  @fixtures Path.expand("fixtures", __DIR__)
  @paths @fixtures |> Path.join("*/*.xml") |> Path.wildcard()
  @jobs @fixtures |> Path.join("*/jobs/*.xml") |> Path.wildcard()

  # PyVO reads the times of a job document with astropy, which doesn't take
  # the UTC offset NED writes them with (2026-11-16T11:01:17-08:00), so it
  # can't read NED's job documents. SpaceTAP doesn't read the times.
  @pyvo_refuses ["ned/jobs/completed.xml", "ned/jobs/error.xml"]

  if reason = Pyvo.skip_reason() do
    @moduletag skip: reason
  else
    setup_all do
      %{pyvo: Pyvo.read_files(@paths), jobs: Pyvo.read_jobs(@jobs)}
    end
  end

  for path <- @paths do
    @path path

    test "matches PyVO on #{Path.relative_to(path, @fixtures)}", %{pyvo: pyvo} do
      Pyvo.assert_file_parity(@path, Map.fetch!(pyvo, @path))
    end
  end

  for path <- @jobs, Path.relative_to(path, @fixtures) not in @pyvo_refuses do
    @path path

    test "matches PyVO on #{Path.relative_to(path, @fixtures)}", %{jobs: jobs} do
      Pyvo.assert_job_parity(@path, Map.fetch!(jobs, @path))
    end
  end

  for path <- @jobs, Path.relative_to(path, @fixtures) in @pyvo_refuses do
    @path path

    test "reads #{Path.relative_to(path, @fixtures)}, which PyVO can't", %{jobs: jobs} do
      assert %{"error" => "ValueError: Cannot parse datetime" <> _rest} = Map.fetch!(jobs, @path)
      assert {:ok, _job} = UWS.parse(File.read!(@path))
    end
  end
end
