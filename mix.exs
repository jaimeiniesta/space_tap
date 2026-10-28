defmodule SpaceTAP.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jaimeiniesta/space_tap"

  def project do
    [
      app: :space_tap,
      name: "SpaceTAP",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "IVOA Table Access Protocol (TAP) client: run ADQL queries against astronomical archives.",
      package: package(),
      source_url: @source_url,
      docs: docs(),
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: ["test.release": :test, "test.services": :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl]
    ]
  end

  #####################
  # Private functions #
  #####################

  # The services and parity tests share the modules in test/support.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      "test.release": ["test --include integration --include pyvo"],
      "test.services": ["test --only services"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.7.5"},
      {:nimble_csv, "~> 1.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:plug, "~> 1.0", only: :test}
    ]
  end

  # The README shows the full logo from assets/, so ExDoc copies that
  # directory; the sidebar and favicon use the icon alone. ExDoc publishes each
  # livebook next to its page, and the page's "Run in Livebook" button opens
  # that copy.
  defp docs do
    [
      main: "readme",
      extras: ["README.md": [title: "Overview"], "CHANGELOG.md": []] ++ livebooks(),
      groups_for_extras: [Livebooks: livebooks()],
      assets: %{"assets" => "assets"},
      logo: "assets/space_tap_icon.svg",
      favicon: "assets/space_tap_icon.svg",
      source_ref: "v#{@version}"
    ]
  end

  # In the order of livebooks/README.md.
  defp livebooks do
    Enum.map(
      ~w(getting_started gaia_pleiades gavo nasa_exoplanet_archive tap_services_tour),
      &"livebooks/#{&1}.livemd"
    )
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end
end
