defmodule Formex.Ecto.ChangesetValidator do
  @behaviour Formex.Validator
  alias Formex.Form
  alias Formex.Field
  alias Ecto.Changeset

  @moduledoc """
  Changeset validator adapter for Formex

  # Why?

  Validators was introduced in Formex 0.5, in older versions validation was perfomred via
  Changesets. So if you already have a project with older Formex, you would have to rewrite all
  validations. But you can also use this validator instead.

  Anyway, you can use any validator with any forms that uses Ecto.

  # Limitations

  * can be used only with Ecto schemas.
  * `length` validation for collections doesn't work.
    Maybe there is a way to fix it. If really need this now - use Vex validator instead.

  # Installation

  See `Formex.Validator` docs.

  # Usage

  ```
  defmodule App.UserType do
    use Formex.Type
    use Formex.Ecto.Type
    use Formex.Ecto.ChangesetValidator # <- add this
  ```

  ## Inside the build_form

  ```
  def build_form(form) do
    form
    |> add(:username, :text_input, validation: [
      :required
    ])
    |> add(:email, :text_input, validation: [
      required: [message: "give me your email!"],
      format: [arg: ~r/@/]
    ])
    |> add(:age, :text_input, validation: [
      :required,
      inclusion: [arg: 13..100, message: "you must be 13."]
    ])
  end
  ```

  Keys from `validation` list are converted to `validate_` functions from
  `Ecto.Changeset`. For example `required` -> `Ecto.Changeset.validate_required/3`.

  Value is list of options. If function requires additional argument
  (e.g. `Ecto.Changeset.validate_format/4` needs format as third argument)
  it must be passed as `:arg` option.

  ## Outside the build_form

  There is `c:changeset_validation/2` callback where is passed changeset struct as argument.
  You can use `Ecto.Changeset.add_error/4` to add errors to fields that exists in that form.

  You cannot alter data from here. This changeset is used only to pass errors. If you want to
  modify changeset, use `c:Formex.Ecto.Type.changeset_after_create_callback/2` instead

  ```
  def build_form(form) do
    form
    |> add(:username, :text_input)
    # ...
  end

  def changeset_validation(changeset, _form) do
    add_error(:username, "error message")
  end
  ```

  """

  defmacro __using__([]) do
    quote do
      @behaviour Formex.Ecto.ChangesetValidator
      import Ecto.Changeset

      def changeset_validation(changeset, _form) do
        changeset
      end

      defoverridable [changeset_validation: 2]
    end
  end

  @spec validate(Form.t) :: Form.t
  def validate(form) do
    # should be used `create_changeset` for collections validation
    # anyway, `length` doesn't validate empty collections

    changeset = Formex.Ecto.Changeset.create_changeset_without_embedded(form)

    errors_fields = form
    |> Form.get_fields_validatable
    |> Enum.flat_map(fn item ->
      validate_field(changeset, item)
    end)

    errors_changeset = form.type.changeset_validation(changeset, form).errors

    errors = errors_fields ++ errors_changeset
    |> Enum.reduce([], fn ({key, val}, acc) ->
      Keyword.update(acc, key, [val], &([val|&1]))
    end)

    form
    |> Map.put(:errors, errors)
  end

  @spec validate_field(changeset :: Changeset.t, field :: Field.t) :: List.t
  defp validate_field(changeset, field) do
    field.validation
    |> Enum.reduce(changeset, fn (validation, changeset) ->
      {name, opts} = case validation do
        {name, opts} when is_list(opts)
          -> {name, opts}
        name
          -> {name, []}
      end

      {arg, opts} = Keyword.pop(opts, :arg)

      args = if arg do
        [changeset, field.name, arg, opts]
      else
        [changeset, field.name, opts]
      end

      name = "validate_"<>to_string(name) |> String.to_atom

      apply(Changeset, name, args)
    end)
    |> Map.get(:errors)
  end

  @callback changeset_validation(changeset :: Changeset.t, form :: Form.t) :: Form.t

end