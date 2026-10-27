defmodule SpaceTAP.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jaimeiniesta/space_tap"

  def project do
    [
      app: :space_tap,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "IVOA Table Access Protocol (TAP) client: run ADQL queries against astronomical archives.",
      package: package(),
      source_url: @source_url,
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: ["test.all": :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl]
    ]
  end

  defp aliases do
    [
      "test.all": ["test --include integration --include pyvo"]
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
