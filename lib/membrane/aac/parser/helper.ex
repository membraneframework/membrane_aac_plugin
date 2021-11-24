defmodule Membrane.AAC.Parser.Helper do
  @moduledoc false
  # Resources:
  # https://wiki.multimedia.cx/index.php/ADTS
  use Bunch
  alias Membrane.{AAC, Buffer, Time}

  @header_size 7
  @crc_size 2

  @spec parse_adts(binary, AAC.t(), AAC.Parser.timestamp_t(), %{
          samples_per_frame: AAC.samples_per_frame_t(),
          encapsulation: AAC.encapsulation_t()
        }) ::
          {:ok, {[{:caps, AAC.t()} | {:buffer, Buffer.t()}], binary, AAC.Parser.timestamp_t()}}
          | {:error, :adts_header}
  def parse_adts(data, caps, timestamp, options) do
    with {:ok, {output, {rest, timestamp}}} <-
           Bunch.List.try_unfoldr({data, caps, timestamp}, &do_parse_adts(&1, options)) do
      {:ok, {List.flatten(output), rest, timestamp}}
    end
  end

  defp do_parse_adts({data, caps, timestamp}, options)
       when byte_size(data) > @header_size + @crc_size do
    withl header: {:ok, frame_caps, header, crc, frame_length} <- parse_header(data, options),
          header: :ok <- verify_header(header, crc),
          do: adts_size = byte_size(header) + byte_size(crc),
          payload: {:frame, frame, rest} <- extract_frame(data, adts_size, frame_length, options) do
      caps = if caps == frame_caps, do: [], else: [caps: frame_caps]
      buffer = [buffer: %Buffer{payload: frame, metadata: %{timestamp: timestamp}}]
      {:ok, {:cont, caps ++ buffer, {rest, frame_caps, next_timestamp(timestamp, frame_caps)}}}
    else
      header: :error -> {:error, :adts_header}
      payload: :no_frame -> {:ok, {:halt, {data, timestamp}}}
    end
  end

  defp do_parse_adts({data, _caps, timestamp}, _options), do: {:ok, {:halt, {data, timestamp}}}

  defp parse_header(
         <<0xFFF::12, _version::1, 0::2, protection_absent::1, profile_id::2,
           sampling_frequency_id::4, _priv_bit::1, channel_config_id::3, _::4, frame_length::13,
           _buffer_fullness::11, aac_frames_cnt::2, rest::binary>> = data,
         options
       )
       when sampling_frequency_id <= 12 do
    <<header::binary-size(@header_size), ^rest::binary>> = data

    crc =
      if protection_absent == 1 do
        <<>>
      else
        <<crc::16, _rest::binary>> = rest
        crc
      end

    caps = %AAC{
      profile: AAC.aot_id_to_profile(profile_id + 1),
      sample_rate: AAC.sampling_frequency_id_to_sample_rate(sampling_frequency_id),
      channels: AAC.channel_config_id_to_channels(channel_config_id),
      frames_per_buffer: aac_frames_cnt + 1,
      samples_per_frame: options.samples_per_frame,
      encapsulation: options.out_encapsulation
    }

    {:ok, caps, header, crc, frame_length}
  end

  defp parse_header(_payload, _options), do: :error

  defp verify_header(_header, <<>>), do: :ok

  defp verify_header(header, crc) do
    if crc == CRC.crc_16(header), do: :ok, else: :error
  end

  defp extract_frame(data, _adts_size, size, %{out_encapsulation: :ADTS}) do
    case data do
      <<frame::binary-size(size), rest::binary>> -> {:frame, frame, rest}
      _other -> :no_frame
    end
  end

  defp extract_frame(data, adts_size, size, %{out_encapsulation: :none}) do
    frame_size = size - adts_size

    case data do
      <<_adts::binary-size(adts_size), frame::binary-size(frame_size), rest::binary>> ->
        {:frame, frame, rest}

      _other ->
        :no_frame
    end
  end

  @spec next_timestamp(any(), AAC.t()) :: AAC.Parser.timestamp_t()
  def next_timestamp(timestamp, caps) do
    use Ratio

    timestamp +
      Ratio.new(caps.samples_per_frame * caps.frames_per_buffer * Time.second(), caps.sample_rate)
  end

  @spec payload_to_adts(binary(), AAC.t()) :: binary()
  def payload_to_adts(payload, %AAC{} = caps) do
    frame_length = 7 + byte_size(payload)
    freq_index = caps.sample_rate |> AAC.sample_rate_to_sampling_frequency_id()
    channel_config = caps.channels |> AAC.channels_to_channel_config_id()
    profile = AAC.profile_to_aot_id(caps.profile) - 1

    header = <<
      # sync
      0xFFF::12,
      # id
      0::1,
      # layer
      0::2,
      # protection_absent
      1::1,
      # profile
      profile::2,
      # sampling frequency index
      freq_index::4,
      # private_bit
      0::1,
      # channel configuration
      channel_config::3,
      # original_copy
      0::1,
      # home
      0::1,
      # copyright identification bit
      1::1,
      # copyright identification start
      1::1,
      # aac frame length
      frame_length::13,
      # adts buffer fullness (signalling VBR - most decoders don't care anyway)
      0x7FF::11,
      # number of raw data blocks in frame - 1
      0::2
    >>

    header <> payload
  end

  @spec parse_audio_specific_config!(binary()) :: AAC.t()
  def parse_audio_specific_config!(
        <<profile::5, sr_index::4, channel_configuration::4, frame_length_flag::1, _rest::bits>>
      ),
      do: %AAC{
        profile: AAC.aot_id_to_profile(profile),
        mpeg_version: 4,
        sample_rate: AAC.sampling_frequency_id_to_sample_rate(sr_index),
        channels: AAC.channel_config_id_to_channels(channel_configuration),
        encapsulation: :none,
        samples_per_frame: if(frame_length_flag == 1, do: 1024, else: 960)
      }
end
