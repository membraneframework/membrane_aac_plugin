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

        if esds_stream_format.sample_rate != stream_format.sample_rate,
          do:
            Membrane.Logger.warning(
              "Sample rate field decoded from esds differs from stream_format:\nesds:#{inspect(esds_stream_format)}\nstream_format:#{inspect(stream_format)}"
            )

        if esds_stream_format.channels != stream_format.channels,
          do:
            Membrane.Logger.warning(
              "Channels field decoded from esds differs from stream_format:\nesds:#{inspect(esds_stream_format)}\nstream_format:#{inspect(stream_format)}"
            )

        esds_stream_format

      {:audio_specific_config, audio_specific_config} ->
        AudioSpecificConfig.parse_audio_specific_config(audio_specific_config)

      nil ->
        stream_format
    end
  end
end
