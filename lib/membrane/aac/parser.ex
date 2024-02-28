defmodule Membrane.AAC.Parser do
  @moduledoc """
  Parser for Advanced Audio Codec.

  Supports both plain and ADTS-encapsulated output (configured by `out_encapsulation`). __jm__ and LATM(LOAS)
  Input with encapsulation `:none` is supported, but correct AAC stream format needs to be supplied with the stream.

  If PTS is absent, it calculates and puts one based on the sample rate.
  """
  use Membrane.Filter
  alias Membrane.StreamFormat
  alias __MODULE__.{ADTS, Utils, Config}
  # alias __MODULE__.LATM __jm__
  alias Membrane.{AAC, Buffer}

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: any_of(AAC, Membrane.RemoteStream)

  def_output_pad :output, flow_control: :manual, accepted_format: AAC

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
                Determines which config spec will be generated and included in
                output stream format as `config`. For `esds` config `avg_bit_rate` and `max_bit_rate` can
                be additionally provided and will be encoded in the `esds`. If not known they should be set to 0.
                """
              ]

  # __jm__ defstruct state?

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
        # __jm__ should start random for security reasons? if it gets initialized upon receiving the first (or first in sequence) packet, shouldn't this be nil instead?
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
    # __jm__ should we support streams where the format is this generic? I'd rather limit the supported fmts to AAC only
    {[], %{state | in_encapsulation: :ADTS}}
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, %{in_encapsulation: :ADTS} = state) do
    %{stream_format: stream_format} = ctx.pads.output
    timestamp = buffer.pts || state.timestamp
  end

  # @impl true
  # def handle_buffer(:input, buffer, ctx, %{in_encapsulation: :none} = state) do
  #   timestamp = buffer.pts || Utils.next_timestamp(state.timestamp, ctx.pads.output.stream_format)
  #   buffer = %{buffer | pts: timestamp |> Ratio.to_float() |> round()}

  #   buffer =
  #     case state.out_encapsulation do
  #       :ADTS ->
  #         %Buffer{
  #           buffer
  #           | payload: ADTS.payload_to_adts(buffer.payload, ctx.pads.output.stream_format)
  #         }

  #       :LOAS ->
  #         %Buffer{
  #           buffer
  #           | payload: raise("unimpl __jm__")
  #         }

  #       _other ->
  #         buffer
  #     end

  #   {[buffer: {:output, buffer}], %{state | timestamp: timestamp}}
  # end

  @impl true
  def handle_buffer(:input, buffer, ctx, %{in_encapsulation: in_encapsulation} = state) do
    stream_format = ctx.pads.output.stream_format

    # __jm__ list of tuples or tuple of lists? {[], [], []} is more readable cause already unzipped, but [{,,,}], assuming homogenous lists, assures lists are of equal length
    # option 2 this time to assure locality of data and limit memory consumption
    {{frames_with_header, frames, stream_formats}, leftover, timestamp} =
      do_handle_buffer(in_encapsulation, buffer, stream_format, state)

    buffers_to_send =
      case state.out_encapsulation do
        ^in_encapsulation ->
          frames_with_header

        :none ->
          frames

        :ADTS ->
          Enum.zip_with(
            frames,
            stream_formats,
            &ADTS.payload_to_adts/2
          )

        :LOAS ->
          raise "__jm__"
      end

    buffer_actions =
      Enum.map(buffers_to_send, fn buffer ->
        {:buffer, buffer}
      end)

    format_actions =
      Stream.map(stream_formats, fn format ->
        {:stream_format, format}
      end)

    # intersperse stream_formats between buffers
    # acc initial value must include current stream_format
    frames_with_fmt_transform = fn {chunk = {_frame, fmt}, stream_format} ->
      nil
    end

    # method 1
    # actions =
    #   {frames, stream_formats}
    #   |> Stream.zip()
    #   |> Stream.chunk_by(fn {_frame, stream_format} -> stream_format end)
    #   |> Stream.map(&Enum.unzip/1)
    #   |> Stream.flat_map(fn {chunk, [stream_format | _stream_format_repeated]} ->
    #     [chunk, stream_format]
    #   end)
    #   |> Enum.to_list()

    # method 2
    # {groups, last_unlabeled_group, latest_stream_format} =
    #   {frames, stream}
    #   |> Stream.zip()
    #   |> Enum.reduce({[], [], stream_format}, fn
    #     {frame, frame_stream_format}, {groups, curr_group, prev_stream_format} ->
    #       {groups, curr_group} =
    #         if frame_stream_format == prev_stream_format do
    #           {groups, curr_group}
    #         else
    #           labeled_group = [stream_format: prev_stream_format | curr_group]
    #           {[labeled_group | groups], []}
    #         end

    #       {groups, [buffer: frame | curr_group], frame_stream_format}
    #   end)

    # groups = [last_unlabeled_group | groups] |> Stream.concat() |> Stream.reverse()

    actions =
      buffer_actions ++
        if opt_new_stream_format,
          do: [stream_format: opt_new_stream_format],
          else: []

    {actions, %{state | leftover: leftover, timestamp: timestamp}}
  end

  @spec do_handle_buffer(
          AAC.encapsulation(),
          Membrane.Buffer.t(),
          AAC.t(),
          Membrane.Element.state()
        ) :: {:ok, {[binary()], AAC.t() | nil, binary(), timestamp()}} | {:error, any()}
  def do_handle_buffer(:none, buffer, stream_format, state) do
    timestamp = buffer.pts || Utils.next_timestamp(state.timestamp, stream_format)

    buffer = %{buffer | pts: timestamp |> Ratio.to_float() |> round()}

    {:ok, {{buffer}, state.leftover, timestamp}}
  end

  def do_handle_buffer(:ADTS, buffer, stream_format, state) do
    timestamp = buffer.pts || state.timestamp

    case ADTS.parse_adts(state.leftover <> buffer.payload, stream_format, timestamp, state) do
      # __jm__ (look at original) why does adts send redemand but :none does not?
      {:ok, result} ->
        result

      {:error, reason} ->
        raise "Could not parse incoming buffer due to #{inspect(reason)}"
    end
  end

  def do_handle_buffer(:LOAS, buffer, stream_format, state) do
    raise "__jm__"
  end

  @spec payload(binary(), AAC.encapsulation(), options()) :: {:ok, binary()} | {:error, any()}
  defp payload(frame, out_encapsulation, options)

  defp payload(frame, :none, _options), do: frame
  defp payload(frame, :ADTS, options = %AAC{}), do: ADTS.payload(frame, options)
  defp payload(frame, :LOAS, options), do: LOAS.payload(frame, options)

  defp payload(frame, :ADTS, _options), do: {:error, "__jm__ options are not stream format"}

  # naming: frame vs packet vs buffer

  # the problem with this parser is that it will now have to support 3 different IO combinations. ADTS shouldn't know out_encapsulation
  # since adts and loas are both encapsulations, we could easily split this into modules where the responsibility of delegation based on IO spec is isolated
  # identity should not touch the frame, only extract the desired info ->
end
