defmodule Membrane.AAC.Parser.Helper do
  @moduledoc false
  # Resources:
  # https://wiki.multimedia.cx/index.php/ADTS
  use Bunch
  alias Membrane.{AAC, Buffer, Time}

  @header_size 7
  @crc_size 2

  @spec parse_adts(binary, AAC.t() | nil, AAC.Parser.timestamp(), %{
          samples_per_frame: AAC.samples_per_frame(),
          encapsulation: AAC.encapsulation()
        }) ::
          {:ok,
           {[{:stream_format, AAC.t()} | {:buffer, Buffer.t()}], binary, AAC.Parser.timestamp()}}
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

  @spec next_timestamp(any(), AAC.t()) :: AAC.Parser.timestamp()
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

  @spec generate_audio_specifig_config(AAC.t()) :: binary()
  def generate_audio_specifig_config(stream_format) do
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

  @spec parse_esds(binary()) ::
          %{profile: AAC.profile(), samples_per_frame: AAC.samples_per_frame()}
  def parse_esds(esds) do
    stream_priority = 0

    {esds, <<>>} = unpack_esds_section(esds, 3)
    <<_elementary_stream_id::16, ^stream_priority, rest::binary>> = esds

    {section_4, esds_section_6} = unpack_esds_section(rest, 4)
    {<<2>>, <<>>} = unpack_esds_section(esds_section_6, 6)

    # 64 = mpeg4-audio
    object_type_id = 64
    # 5 = audio
    stream_type = 5
    upstream_flag = 0
    reserved_flag_set_to_1 = 1
    buffer_size = 0

    <<^object_type_id, ^stream_type::6, ^upstream_flag::1, ^reserved_flag_set_to_1::1,
      ^buffer_size::24, _max_bit_rate::32, _avg_bit_rate::32, esds_section_5::binary>> = section_4

    {section_5, <<>>} = unpack_esds_section(esds_section_5, 5)

    depends_on_core_coder = 0
    extension_flag = 0

    <<aot_id::5, _frequency_id::4, _channel_config_id::4, frame_length_id::1,
      ^depends_on_core_coder::1, ^extension_flag::1>> = section_5

    %{
      profile: AAC.aot_id_to_profile(aot_id),
      samples_per_frame: AAC.frame_length_id_to_samples_per_frame(frame_length_id)
    }
  end

  defp unpack_esds_section(section, section_no) do
    type_tag = <<128, 128, 128>>

    <<^section_no::8-integer, ^type_tag::binary-size(3), payload_size::8-integer, rest::binary>> =
      section

    <<payload::binary-size(payload_size), rest::binary>> = rest
    {payload, rest}
  end

  @spec generate_esds(AAC.t(), Membrane.Element.state()) :: binary()
  def generate_esds(stream_format, state) do
    aot_id = Membrane.AAC.profile_to_aot_id(stream_format.profile)
    frequency_id = Membrane.AAC.sample_rate_to_sampling_frequency_id(stream_format.sample_rate)
    channel_config_id = Membrane.AAC.channels_to_channel_config_id(stream_format.channels)

    frame_length_id =
      Membrane.AAC.samples_per_frame_to_frame_length_id(stream_format.samples_per_frame)

    depends_on_core_coder = 0
    extension_flag = 0

    section5 =
      <<aot_id::5, frequency_id::4, channel_config_id::4, frame_length_id::1,
        depends_on_core_coder::1, extension_flag::1>>
      |> generate_esds_section(5)

    # 64 = mpeg4-audio
    object_type_id = 64
    # 5 = audio
    stream_type = 5
    upstream_flag = 0
    reserved_flag_set_to_1 = 1
    buffer_size = 0

    section4 =
      <<object_type_id, stream_type::6, upstream_flag::1, reserved_flag_set_to_1::1,
        buffer_size::24, state.max_bit_rate::32, state.avg_bit_rate::32, section5::binary>>
      |> generate_esds_section(4)

    section6 = <<2>> |> generate_esds_section(6)

    elementary_stream_id = 1
    stream_priority = 0

    <<elementary_stream_id::16, stream_priority, section4::binary, section6::binary>>
    |> generate_esds_section(3)
  end

  defp generate_esds_section(payload, section_no) do
    type_tag = <<128, 128, 128>>
    <<section_no, type_tag::binary, byte_size(payload), payload::binary>>
  end
end
