defmodule Membrane.AAC.Parser.Helper do
  @moduledoc false
  # Resources:
  # https://wiki.multimedia.cx/index.php/ADTS
  use Bunch
  alias Membrane.{AAC, Buffer, Time}

  @header_size 7
  @crc_size 2

  @spec parse_adts(binary, AAC.t() | nil, AAC.Parser.timestamp_t(), %{
          samples_per_frame: AAC.samples_per_frame_t(),
          encapsulation: AAC.encapsulation_t()
        }) ::
          {:ok,
           {[{:stream_format, AAC.t()} | {:buffer, Buffer.t()}], binary, AAC.Parser.timestamp_t()}}
          | {:error, :invalid_adts_header}
  def parse_adts(data, stream_format, timestamp, options) do
    with {:ok, {output, {rest, timestamp}}} <-
           Bunch.List.try_unfoldr({data, stream_format, timestamp}, &do_parse_adts(&1, options)) do
      {:ok, {List.flatten(output), rest, timestamp}}
    end
  end

  defp do_parse_adts({data, stream_format, timestamp}, options)
       when byte_size(data) > @header_size + @crc_size do
    withl header:
            {:ok, frame_stream_format, header, crc, frame_length} <- parse_header(data, options),
          header: :ok <- verify_header(header, crc),
          do: adts_size = byte_size(header) + byte_size(crc),
          payload: {:frame, frame, rest} <- extract_frame(data, adts_size, frame_length, options) do
      stream_format =
        if stream_format == frame_stream_format,
          do: [],
          else: [stream_format: frame_stream_format]

      buffer = [buffer: %Buffer{pts: timestamp, payload: frame}]

      {:ok,
       {:cont, stream_format ++ buffer,
        {rest, frame_stream_format, next_timestamp(timestamp, frame_stream_format)}}}
    else
      header: :error -> {:error, :invalid_adts_header}
      payload: :no_frame -> {:ok, {:halt, {data, timestamp}}}
    end
  end

  defp do_parse_adts({data, _stream_format, timestamp}, _options),
    do: {:ok, {:halt, {data, timestamp}}}

  defp parse_header(
         <<0xFFF::12, _id::1, _layer::2, protection_absent::1, profile_id::2,
           sampling_frequency_id::4, _priv_bit::1, channel_config_id::3, _originality::1,
           _home::1, _copyright_id_bit::1, _copyright_id_start::1, frame_length::13,
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

    stream_format = %AAC{
      profile: AAC.aot_id_to_profile(profile_id + 1),
      sample_rate: AAC.sampling_frequency_id_to_sample_rate(sampling_frequency_id),
      channels: AAC.channel_config_id_to_channels(channel_config_id),
      frames_per_buffer: aac_frames_cnt + 1,
      samples_per_frame: options.samples_per_frame,
      encapsulation: options.out_encapsulation
    }

    {:ok, stream_format, header, crc, frame_length}
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
  def next_timestamp(timestamp, stream_format) do
    use Ratio

    timestamp +
      Ratio.new(
        stream_format.samples_per_frame * stream_format.frames_per_buffer * Time.second(),
        stream_format.sample_rate
      )
  end

  @spec payload_to_adts(binary(), AAC.t()) :: binary()
  def payload_to_adts(payload, %AAC{} = stream_format) do
    frame_length = 7 + byte_size(payload)
    freq_index = stream_format.sample_rate |> AAC.sample_rate_to_sampling_frequency_id()
    channel_config = stream_format.channels |> AAC.channels_to_channel_config_id()
    profile = AAC.profile_to_aot_id(stream_format.profile) - 1

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
      0::1,
      # copyright identification start
      0::1,
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
        samples_per_frame: if(frame_length_flag == 0, do: 1024, else: 960)
      }
end
