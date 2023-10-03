defmodule Membrane.AAC.Parser do
  @moduledoc """
  Parser for Advanced Audio Codec.

  Supports both plain and ADTS-encapsulated output (configured by `out_encapsulation`).
  Input with encapsulation `:none` is supported, but correct AAC stream format needs to be supplied with the stream.

  If PTS is absent, it calculates and puts one based on the sample rate.
  """
  use Membrane.Filter
  alias __MODULE__.{ADTS, Config}
  alias Membrane.{AAC, Buffer}

  def_input_pad :input,
    demand_unit: :buffers,
    accepted_format: any_of(AAC, Membrane.RemoteStream)

  def_output_pad :output, accepted_format: AAC

  def_options samples_per_frame: [
                spec: AAC.samples_per_frame(),
                default: 1024,
                description: "Count of audio samples in each AAC frame"
              ],
              out_encapsulation: [
                spec: AAC.encapsulation(),
                default: :ADTS,
                description: """
                Determines whether output AAC frames should be prefixed with ADTS headers
                """
              ],
              output_config: [
                spec:
                  :audio_specific_config
                  | :esds
                  | {:esds, avg_bit_rate :: non_neg_integer(), max_bit_rate :: non_neg_integer()}
                  | nil,
                default: nil,
                description: """
                Determines which config structure will be generated and included in
                output stream format as `config`. For `esds` config `avg_bit_rate` and `max_bit_rate` can
                be additionally provided and will be encoded in the `esds`. If not known they should be set to 0.
                """
              ]

  @type timestamp :: Ratio.t() | Membrane.Time.t()

  @impl true
  def handle_init(_ctx, options) do
    {output_config, options} = Map.pop!(options, :output_config)

    {output_config, avg_bit_rate, max_bit_rate} =
      case output_config do
        {:esds, avg_bit_rate, max_bit_rate} -> {:esds, avg_bit_rate, max_bit_rate}
        config -> {config, 0, 0}
      end

    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        leftover: <<>>,
        timestamp: 0,
        in_encapsulation: nil,
        output_config: output_config,
        avg_bit_rate: avg_bit_rate,
        max_bit_rate: max_bit_rate
      })

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, %AAC{} = stream_format, _ctx, state) do
    stream_format = Config.parse_config(stream_format)

    config = Config.generate_config(stream_format, state)

    {[
       stream_format:
         {:output, %{stream_format | encapsulation: state.out_encapsulation, config: config}}
     ], %{state | in_encapsulation: stream_format.encapsulation}}
  end

  @impl true
  def handle_stream_format(:input, %Membrane.RemoteStream{}, _ctx, state) do
    {[], %{state | in_encapsulation: :ADTS}}
  end

  @impl true
  def handle_process(:input, buffer, ctx, %{in_encapsulation: :ADTS} = state) do
    %{stream_format: stream_format} = ctx.pads.output
    timestamp = buffer.pts || state.timestamp

    {tags, payload} = parse_id3v4_tags(buffer.payload, [])

    case ADTS.parse_adts(state.leftover <> payload, stream_format, timestamp, state) do
      {:ok, {output, leftover, timestamp}} ->
        actions =
          Enum.map(output, fn
            {:buffer, buffer} ->
              value = correct_pts(buffer, tags)
              {:buffer, {:output, value}}

            {action, value} ->
              {action, {:output, value}}
          end)

        {actions ++ [redemand: :output], %{state | leftover: leftover, timestamp: timestamp}}

      {:error, reason} ->
        raise "Could not parse incoming buffer due to #{inspect(reason)}"
    end
  end

  @impl true
  def handle_process(:input, buffer, ctx, %{in_encapsulation: :none} = state) do
    timestamp = buffer.pts || ADTS.next_timestamp(state.timestamp, ctx.pads.output.stream_format)

    buffer = %{buffer | pts: timestamp}

    buffer =
      case state.out_encapsulation do
        :ADTS ->
          %Buffer{
            buffer
            | payload: ADTS.payload_to_adts(buffer.payload, ctx.pads.output.stream_format)
          }

        _other ->
          buffer
      end

    {[buffer: {:output, buffer}], %{state | timestamp: timestamp}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {[demand: {:input, size}], state}
  end

  defp correct_pts(buffer, tags) do
    case Enum.find(tags, fn {id, _val} -> id == "com.apple.streaming.transportStreamTimestamp" end) do
      nil -> buffer
      {_, pts} -> %Buffer{buffer | pts: Ratio.add(buffer.pts, pts)}
    end
  end

  defp parse_id3v4_tags(data, acc) do
    case parse_id3v4_tag(data) do
      {[], rest} -> {acc, rest}
      {tags, rest} -> parse_id3v4_tags(rest, acc ++ tags)
    end
  end

  # https://github.com/id3/ID3v2.4/blob/master/id3v2.40-structure.txt
  defp parse_id3v4_tag(
         <<"ID3", version::binary-size(2), flags::binary-size(1), size::binary-size(4),
           rest::binary>>
       ) do
    # Here we pattern match the combo of version-flags supported.
    <<4::8, _minor::8>> = version

    # <<unsynchronisation::1, extended::1, experimental::1, footer::1, 0::4>> = flags
    <<0::1, 0::1, 0::1, 0::1, 0::4>> = flags

    size = decode_synchsafe_integer(size)
    <<data::binary-size(size), rest::binary>> = rest
    {parse_id3_frames(data, []), rest}
  end

  defp parse_id3v4_tag(<<"ID3", version::binary-size(2), _rest::binary>>) do
    raise "Unsupported ID3 header version #{inspect(version)}"
  end

  defp parse_id3v4_tag(data), do: {[], data}

  defp parse_id3_frames(
         <<"PRIV", size::binary-size(4), flags::binary-size(2), rest::binary>>,
         acc
       ) do
    <<_status::binary-size(1), _format::binary-size(1)>> = flags

    size = decode_synchsafe_integer(size)
    <<data::binary-size(size), rest::binary>> = rest

    [owner_identifier, private_data] = :binary.split(data, <<0>>)
    tag = parse_priv_tag(owner_identifier, private_data)
    parse_id3_frames(rest, [tag | acc])
  end

  defp parse_id3_frames(<<>>, acc), do: Enum.reverse(acc)

  defp parse_priv_tag(id = "com.apple.streaming.transportStreamTimestamp", data) do
    # https://datatracker.ietf.org/doc/html/draft-pantos-http-live-streaming-19#section-3
    rem = bit_size(data) - 33
    <<_pad::size(rem), data::33-big>> = data
    secs = data / 90_000
    ns = Membrane.Time.nanoseconds(round(secs * 1_000_000_000))
    {id, ns}
  end

  defp parse_priv_tag(id, data), do: {id, data}

  defp decode_synchsafe_integer(binary) do
    import Bitwise

    binary
    |> :binary.bin_to_list()
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce(0, fn {el, index}, acc -> acc ||| el <<< (index * 7) end)
  end
end
