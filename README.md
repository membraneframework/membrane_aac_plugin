# Membrane AAC plugin

[![Star Membrane on GitHub ★](https://img.shields.io/github/stars/membraneframework/membrane_core?style=flat&logo=github&label=Star%20Membrane%20on%20GitHub%20%E2%98%85&color=blue)](https://github.com/membraneframework/membrane_core)
[![Hex.pm](https://img.shields.io/hexpm/v/membrane_aac_plugin.svg)](https://hex.pm/packages/membrane_aac_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_aac_plugin)
[![CI](https://github.com/membraneframework/membrane_aac_plugin/actions/workflows/ci.yml/badge.svg)](https://github.com/membraneframework/membrane_aac_plugin/actions/workflows/ci.yml)

This package provides AAC parser and complimentary elements for AAC.

It is a part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_aac_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_aac_plugin, "~> 0.19.4"}
  ]
end
```

## Usage example
You can find examples of usage in the `examples/` directory.

To see how the parser can be used to payload AAC stream so that it can be put in the MP4 container, run:
```
elixir examples/add_and_put_in_mp4.exs
```

When the script terminates, you can play the result .mp4 file with the following command:
```
ffplay output.mp4
```

The documentation can be found at [Hex Docs](https://hexdocs.pm/membrane_aac_plugin).

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_aac_plugin)

[![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_aac_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
