defmodule Membrane.AAC.Parser.Config do
  @moduledoc false
  
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
        Map.merge(stream_format, Esds.parse_esds(esds))

      {:audio_specific_config, config} ->
        AudioSpecificConfig.parse_audio_specific_config(config)

      nil ->
        stream_format
    end
  end
end
