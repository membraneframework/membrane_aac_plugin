defmodule Membrane.AAC.Parser.Config do
  @moduledoc false

  require Membrane.Logger
  alias Membrane.AAC
  alias Membrane.AAC.Parser.{AudioSpecificConfig, Esds}

  @spec generate_config(AAC.t(), Membrane.Element.state()) :: AAC.config() | nil
  def generate_config(stream_format, state) do
    case state.output_config do
      :esds ->
        {:esds, Esds.generate_esds(stream_format, state)}

      :audio_specific_config ->
        {:audio_specific_config,
         AudioSpecificConfig.generate_audio_specific_config(stream_format)}

      nil ->
        nil
    end
  end

  @spec parse_config(AAC.t()) :: AAC.t()
  def parse_config(stream_format) do
    case stream_format.config do
      {:esds, esds} ->
        esds_stream_format = Esds.parse_esds(esds)

        [:sample_rate, :channels]
        |> Enum.map(fn field ->
          {field, Map.fetch!(esds_stream_format, field), Map.fetch!(stream_format, field)}
        end)
        |> Enum.filter(fn {_field, esds_field, stream_field} -> esds_field != stream_field end)
        |> Enum.each(fn {field, esds_field, stream_field} ->
          Membrane.Logger.warning("""
          #{inspect(field)} decoded from esds differs from stream_format:
          esds: #{inspect(esds_field)}
          stream_format: #{inspect(stream_field)}
          """)
        end)

        esds_stream_format

      {:audio_specific_config, audio_specific_config} ->
        AudioSpecificConfig.parse_audio_specific_config(audio_specific_config)

      nil ->
        stream_format
    end
  end
end
