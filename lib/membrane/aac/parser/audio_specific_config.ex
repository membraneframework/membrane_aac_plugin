defmodule Membrane.AAC.Parser.AudioSpecificConfig do
  @moduledoc """
  Utility functions for parsing and generating Audio Specific Config.

  It's spec is described in section 1.6.2.1 of ISO/IEC 14496-3.
  """

  alias Membrane.AAC

  @type parse_error ::
          :too_short
          | {:unsupported_audio_object_type_id, 0..31}
          | {:unsupported_sampling_frequency_id, 13..14}
          | {:unsupported_channel_config_id, 8..15}

  # the ids of AAC.audio_object_type_id(), AAC.sampling_frequency_id() and AAC.channel_config_id()
  @audio_object_type_ids [1, 2, 3, 4, 5, 29]
  @sampling_frequency_ids Enum.to_list(0..12) ++ [15]
  @channel_config_ids 0..7

  @spec generate_audio_specific_config(AAC.t()) :: binary()
  def generate_audio_specific_config(stream_format) do
    aot = AAC.profile_to_aot_id(stream_format.profile)
    frequency_id = AAC.sample_rate_to_sampling_frequency_id(stream_format.sample_rate)
    channel_config_id = AAC.channels_to_channel_config_id(stream_format.channels)
    frame_length_id = AAC.samples_per_frame_to_frame_length_id(stream_format.samples_per_frame)

    depends_on_core_coder = 0
    extension_flag = 0

    custom_frequency = if frequency_id == 15, do: <<stream_format.sample_rate::24>>, else: <<>>

    <<aot::5, frequency_id::4, custom_frequency::binary, channel_config_id::4, frame_length_id::1,
      depends_on_core_coder::1, extension_flag::1>>
  end

  @spec parse_audio_specific_config(binary()) :: AAC.t()
  def parse_audio_specific_config(audio_specific_config) do
    case parse(audio_specific_config) do
      {:ok, stream_format} ->
        stream_format

      {:error, reason} ->
        raise "Cannot parse Audio Specific Config #{inspect(audio_specific_config)}: " <>
                inspect(reason)
    end
  end

  @doc """
  Parses an Audio Specific Config.

  Returns an error when the config is too short or when `Membrane.AAC` has no counterpart
  for its audio object type, sampling frequency or channel configuration.
  """
  @spec parse(binary()) :: {:ok, AAC.t()} | {:error, parse_error()}
  def parse(audio_specific_config) do
    with <<aot_id::5, frequency_id::4, rest::bitstring>> <- audio_specific_config,
         custom_frequency_length = if(frequency_id == 15, do: 24, else: 0),
         <<custom_frequency::integer-size(^custom_frequency_length), channel_config_id::4,
           frame_length_id::1, _rest::bits>> <- rest,
         :ok <- validate_ids(aot_id, frequency_id, channel_config_id) do
      sample_rate =
        if frequency_id == 15,
          do: custom_frequency,
          else: AAC.sampling_frequency_id_to_sample_rate(frequency_id)

      channels =
        case AAC.channel_config_id_to_channels(channel_config_id) do
          :AOT_specific -> nil
          channels when is_integer(channels) -> channels
        end

      {:ok,
       %AAC{
         profile: AAC.aot_id_to_profile(aot_id),
         mpeg_version: 4,
         sample_rate: sample_rate,
         channels: channels,
         encapsulation: :none,
         samples_per_frame: AAC.frame_length_id_to_samples_per_frame(frame_length_id),
         config: {:audio_specific_config, audio_specific_config}
       }}
    else
      {:error, reason} -> {:error, reason}
      too_short when is_bitstring(too_short) -> {:error, :too_short}
    end
  end

  defp validate_ids(aot_id, frequency_id, channel_config_id) do
    cond do
      aot_id not in @audio_object_type_ids ->
        {:error, {:unsupported_audio_object_type_id, aot_id}}

      frequency_id not in @sampling_frequency_ids ->
        {:error, {:unsupported_sampling_frequency_id, frequency_id}}

      channel_config_id not in @channel_config_ids ->
        {:error, {:unsupported_channel_config_id, channel_config_id}}

      true ->
        :ok
    end
  end
end
