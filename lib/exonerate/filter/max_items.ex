defmodule Exonerate.Filter.MaxItems do
  @moduledoc false
  
  @behaviour Exonerate.Filter
  @derive Exonerate.Compiler
  @derive {Inspect, except: [:context]}

  alias Exonerate.Validator
  defstruct [:context, :count]

  import Validator, only: [fun: 2]

  def parse(artifact, %{"maxItems" => count}) do

    %{artifact |
      needs_accumulator: true,
      needs_array_in_accumulator: true,
      accumulator_pipeline: [fun(artifact, "maxItems") | artifact.accumulator_pipeline],
      accumulator_init: Map.put(artifact.accumulator_init, :index, 0),
      filters: [%__MODULE__{context: artifact.context, count: count} | artifact.filters]}
  end

  def compile(filter = %__MODULE__{count: count}) do
    {[], [
      quote do
        defp unquote(fun(filter, "maxItems"))(acc, {path, _}) do
          if acc.index >= unquote(count) do
            Exonerate.mismatch(acc.array, path)
          end
          acc
        end
      end
    ]}
  end
end
