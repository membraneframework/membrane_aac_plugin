defmodule Membrane.AAC.Parser.AudioSpecificConfig do
  @moduledoc """
  Utility functions for parsing and generating Audio Specific Config.

  It's structure is described in section 1.6.2.1 of ISO/IEC 14496-3.
  """

  alias Membrane.AAC

  @spec generate_audio_specific_config(AAC.t()) :: binary()
  def generate_audio_specific_config(stream_format) do
    aot = AAC.profile_to_aot_id(stream_format.profile)
    sr_index = AAC.sample_rate_to_sampling_frequency_id(stream_format.sample_rate)
    channel_configuration = AAC.channels_to_channel_config_id(stream_format.channels)

    frame_length_flag =
      case stream_format.samples_per_frame do
        960 -> 1
        1024 -> 0
      end

    <<aot::5, sr_index::4, channel_configuration::4, frame_length_flag::1, 0::1, 0::1>>
  end

  @spec parse_audio_specific_config(binary()) :: AAC.t()
  def parse_audio_specific_config(
        <<profile::5, sr_index::4, channel_configuration::4, frame_length_flag::1, _rest::bits>>
      ),
      do: %AAC{
        profile: AAC.aot_id_to_profile(profile),
        mpeg_version: 4,
        sample_rate: AAC.sampling_frequency_id_to_sample_rate(sr_index),
        channels: AAC.channel_config_id_to_channels(channel_configuration),
        encapsulation: :none,
        samples_per_frame: if(frame_length_flag == 0, do: 1024, else: 960)
      }
end
