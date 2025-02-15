defmodule Exonerate do
  @moduledoc """
  An opinionated JSONSchema compiler for elixir.

  Currently supports JSONSchema drafts 4, 6, 7, 2019, and 2020.  *except:*

  - integer filters do not match exact integer floating point values.
  - multipleOf is not supported for the number type (don't worry, it IS supported
    for integers).  This is because Elixir does not support a floating point
    remainder guard, and also because it is impossible for a floating point to
    guarantee sane results (e.g. for IEEE Float64, `1.2 / 0.1 != 12`)
  - currently remoteref is not supported.

  For details, see:  http://json-schema.org

  Exonerate is automatically tested against the JSONSchema test suite.

  ## Usage

  Exonerate is 100% compile-time generated.  You should include Exonerate with
  the `runtime: false` option in `mix.exs`.

  ### In your module:

  ```
  defmodule MyModule do
    require Exonerate

    Exonerate.function_from_string(:def, :function_name, \"""
    {
      "type": "string"
    }
    \""")
  end
  ```

  The above module generates a function `MyModule.function_name/1` that takes an erlang JSON term
  (`string | number | array | map | bool | nil`) and validates it based on the the JSONschema.  If
  the term validates, it produces `:ok`.  If the term fails to validate, it produces
  `{:error, keyword}`, where the key `:json_pointer` and points to the error location in the passed
  parameter, the `:schema_pointers` points to the validation that failed, and `error_value` is the
  failing inner term.

  ## Metadata

  The following metadata are accessible for the entrypoint in the jsonschema, by passing the corresponding
  atom.

  | JSONschema tag | atom parameter |
  |----------------|----------------|
  | $id            | `:id`          |
  | $schema        | `:schema`      |
  | default        | `:default`     |
  | examples       | `:examples`    |
  | description    | `:description` |
  | title          | `:title`       |

  ## Options

  The following options are available:

  - `:format`: a map of JSONpointers to tags with corresponding `{"format" => "..."}` filters.

    Exonerate ships with filters for the following default content:
    - `date-time`
    - `date`
    - `time`
    - `ipv4`
    - `ipv6`

    To disable these filters, pass `false` to the path, e.g. `%{"/" => false}` or `%{"/foo/bar/" => false}`.
    To specify a custom format filter, pass either function/args or mfa to the path, e.g.
    `%{"/path/to/fun" => {Module, :fun, [123]}}` or if you want the f/a or mfa to apply to all tags of a
    given format string, create use the atom of the type name as the key for your map.

    The corresponding function will be called with thue candidate formatted string as the first argument
    and the supplied arguments after.  If you use the function/args (e.g. `{:private_function, [123]}`)
    it may be a private function in the same module.  The custom function should return `true` on
    successful validation and `false` on failure.

    `date-time` ships with the parameter `:utc` which you may pass as `%{"/path/to/date-time/" => [:utc]}` that
    forces the date-time to be an ISO-8601 datetime string.

  - `:entrypoint`: a JSONpointer to the internal location inside of a json document where you would like to start
    the JSONschema.  This should be in JSONPointer form.  See https://datatracker.ietf.org/doc/html/rfc6901 for
    more information about JSONPointer

  - `:decoder`: specify `{module, function}` to use as the decoder for the text that turns into JSON
    (e.g. YAML instead of JSON)

  - `:draft`: specifies any special draft information.  Defaults to "2020", which is intercompatible
    with `"2019"`.  `"4"`, `"6"`, and `"7"` are also supported.  Note: Validation is NOT performed on
    the schema, so intermingling draft components is possible (but not recommended).
  """

  alias Exonerate.Metadata
  alias Exonerate.Pointer
  alias Exonerate.Type
  alias Exonerate.Registry
  alias Exonerate.Validator

  @common_defaults [
    format: %{},
    decoder: {Jason, :decode!}
  ]

  @doc """
  generates a series of functions that validates a provided JSONSchema.

  Note that the `schema` parameter must be a string literal.
  """
  defmacro function_from_string(type, name, schema, opts \\ [])
  defmacro function_from_string(type, name, schema_ast, opts)  do
    opts = opts
    |> Keyword.merge(authority: Atom.to_string(name))
    |> resolve_opts(__CALLER__, @common_defaults)

    schema = schema_ast
    |> Macro.expand(__CALLER__)
    |> decode(opts)

    compile_json(type, name, schema, opts)
  end

  @doc """
  generates a series of functions that validates a JSONschema in a file at
  the provided path.

  Note that the `path` parameter must be a string literal.
  """
  defmacro function_from_file(type, name, path, opts \\ [])
  defmacro function_from_file(type, name, path, opts) do
    opts = opts
    |> Keyword.merge(authority: Atom.to_string(name))
    |> resolve_opts(__CALLER__, @common_defaults)

    {schema, extra} = path
    |> Macro.expand(__CALLER__)
    |> Registry.get_file
    |> case do
      {:cached, contents} -> {decode(contents, opts), [quote do @external_resource unquote(path) end]}
      {:loaded, contents} -> {decode(contents, opts), []}
    end

    quote do
      unquote_splicing(extra)
      unquote(compile_json(type, name, schema, opts))
    end
  end

  @spec precache_file!(Path.t) :: binary
  @doc "lets you precache a file so you don't have to repeat loading it twice"
  defdelegate precache_file!(path), to: Registry, as: :get_file!

  defp resolve_opts(opts, caller, defaults) do
    Enum.reduce(defaults, opts, fn {k, default}, opts ->
      if Keyword.has_key?(opts, k) do
        new_v = opts[k]
        |> Code.eval_quoted([], caller)
        |> elem(0)

        Keyword.put(opts, k, new_v)
      else
        Keyword.put(opts, k, default)
      end
    end)
  end

  defp compile_json(type, name, schema, opts) do
    entrypoint = opts
    |> Keyword.get(:entrypoint, "/")
    |> Pointer.from_uri

    impl = schema
    |> Validator.parse(entrypoint, opts)
    |> Validator.compile

    json_type = {:"#{name}_json", [], []}

    # let's see if there's anything leftover.
    dangling_refs = unroll_refs(schema)

    entrypoint_body = quote do
      try do
        unquote(Pointer.to_fun(entrypoint, opts))(value, "/")
      catch
        error = {:error, e} when is_list(e) -> error
      end
    end

    quote do
      @typep unquote(json_type) ::
        bool
        | nil
        | number
        | String.t
        | [unquote(json_type)]
        | %{String.t => unquote(json_type)}

      @spec unquote(name)(unquote(json_type)) :: :ok |
        {:error, [
          schema_pointer: Path.t,
          error_value: term,
          json_pointer: Path.t
        ]}

      unquote_splicing(Metadata.metadata_functions(name, schema, entrypoint))

      case unquote(type) do
        :def ->
          def unquote(name)(value), do: unquote(entrypoint_body)
        :defp ->
          defp unquote(name)(value), do: unquote(entrypoint_body)
      end

      unquote(impl)
      unquote(dangling_refs)
    end # |> Exonerate.Tools.inspect(name == :maxProperties_1)
  end

  defp decode(contents, opts) do
    case opts[:decoder] do
      {module, fun} ->
        apply(module, fun, [contents])
      {module, fun, extra_args} ->
        apply(module, fun, [contents | extra_args])
    end
  end

  defp unroll_refs(schema) do
    case Registry.needed(schema) do
      [] -> []
      list when is_list(list) ->
        ref_impls = Enum.map(list, fn ref ->
          schema
          |> Validator.parse(ref.pointer, authority: ref.authority)
          |> Validator.compile
        end)
        # keep going!  This schema might have created new refs.
        ref_impls ++ unroll_refs(schema)
    end
  end

  #################################################################
  ## PRIVATE HELPER MACROS
  ## used internally by macro generation functions

  @doc false
  def fun_to_path(fun) do
    fun
    |> to_string
    |> String.split("#/")
    |> tl()
    |> Enum.join
    |> amend_path
  end

  @doc false
  defmacro mismatch(value, path, opts \\ []) do
    schema_path! = __CALLER__.function
    |> elem(0)
    |> fun_to_path

    schema_path! = if guard = opts[:guard] do
      quote do
        Path.join(unquote(schema_path!), unquote(guard))
      end
    else
      schema_path!
    end

    extras = Keyword.take(opts, [:reason, :failures, :matches])

    quote do
      throw {:error,
      [schema_pointer: unquote(schema_path!),
      error_value: unquote(value),
      json_pointer: unquote(path)] ++ unquote(extras)}
    end
  end

  defp amend_path(path = ("/" <> _)), do: path
  defp amend_path(path), do: "/" <> path

  @doc false
  defmacro pipeline(variable_ast, path_ast, pipeline) do
    build_pipe(variable_ast, path_ast, pipeline)
  end

  defp build_pipe(input_ast, params_ast, [fun | rest]) do
    build_pipe({:|>, [], [input_ast, {fun, [], [params_ast]}]}, params_ast, rest)
  end
  defp build_pipe(input_ast, _params_ast, []), do: input_ast

  # TODO: generalize these.

  @doc false
  defmacro chain_guards(variable_ast, types) do
    types
    |> Enum.map(&apply_guard(&1, variable_ast))
    |> Enum.reduce(&{:or, [], [&1, &2]})
  end

  defp apply_guard(type, variable_ast), do: {Type.guard(type), [], [variable_ast]}
end
