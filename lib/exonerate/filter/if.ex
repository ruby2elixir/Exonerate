defmodule Exonerate.Filter.If do
  @moduledoc false

  @behaviour Exonerate.Filter
  @derive Exonerate.Compiler
  @derive {Inspect, except: [:context]}

  alias Exonerate.Validator

  import Validator, only: [fun: 2]

  defstruct [:context, :schema, :then, :else]


  @impl true
  def parse(context = %Validator{}, %{"if" => _}) do

    schema = Validator.parse(
      context.schema,
      ["if" | context.pointer],
      authority: context.authority,
      format: context.format,
      draft: context.draft)

    module = %__MODULE__{context: context, schema: schema, then: context.then, else: context.else}

    %{context |
      children: [module | context.children],
      combining: [module | context.combining]}
  end

  def combining(filter, value_ast, path_ast) do
    quote do
      unquote(fun(filter, ["if", ":test"]))(unquote(value_ast), unquote(path_ast))
    end
  end

  def compile(filter = %__MODULE__{}) do
    then_clause = if filter.then do
      quote do
        unquote(fun(filter, "then"))(value, path)
      end
    else
      :ok
    end

    else_clause = if filter.else do
      quote do
        unquote(fun(filter, "else"))(value, path)
      end
    else
      :ok
    end

    [quote do
      defp unquote(fun(filter, ["if", ":test"]))(value, path) do
        conditional = try do
          unquote(fun(filter, "if"))(value, path)
        catch
          error = {:error, list} when is_list(list) -> error
        end

        case conditional do
          :ok -> unquote(then_clause)
          {:error, _} -> unquote(else_clause)
        end
      end
      unquote(Validator.compile(filter.schema))
    end]
  end
end
