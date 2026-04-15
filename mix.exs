defmodule Membrane.AAC.MixProject do
  use Mix.Project

  @version "0.19.2"
  @github_url "https://github.com/membraneframework/membrane_aac_plugin"

  def project do
    [
      app: :membrane_aac_plugin,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),

      # hex
      description: "Parses AAC bitstreams and extracts metadata for MP4 muxing.",
      package: package(),

      # docs
      name: "Membrane AAC plugin",
      source_url: @github_url,
      homepage_url: "https://membraneframework.org",
      docs: docs(),
      aliases: [docs: ["docs", &prepend_llms_links/1]]
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.AAC]
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      }
    ]
  end

  defp deps do
    [
      {:membrane_core, "~> 1.0"},
      {:bunch, "~> 1.0"},
      {:membrane_aac_format, "~> 0.8.0"},
      {:membrane_file_plugin, "~> 0.16.0", only: :test},

      # Dev
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer() do
    opts = [
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

defp prepend_llms_links(_) do
  path = "doc/llms.txt"

  if File.exists?(path) do
    existing = File.read!(path)

    header =
      "- [Membrane Core AI Skill](https://hexdocs.pm/membrane_core/skill.md)\n" <>
        "- [Membrane Core](https://hexdocs.pm/membrane_core/llms.txt)\n\n"

    File.write!(path, header <> existing)
  end
end

end
