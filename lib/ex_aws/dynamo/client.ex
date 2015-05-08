defmodule ExAws.Dynamo.Client do
  use Behaviour

  @moduledoc """
  Defines a Dynamo Client

  By default you can use ExAws.Dynamo

  NOTE: When Mix.env in [:test, :dev] dynamo clients will run by default against
  Dynamodb local.

  ## Usage
  ```
  defmodule MyApp.Dynamo do
    use ExAws.Dynamo.Client, otp_app: :my_otp_app
  end
  ```

  In your config
  ```
  config :my_otp_app, :ex_aws,
    dynamodb: [], # Dynamo config goes here
  ```

  You can now use MyApp.Dynamo as the root module for the Dynamo api without needing
  to pass in a particular configuration.
  This enables different otp apps to configure their AWS configuration separately.

  The alignment with a particular OTP app while convenient is however entirely optional.
  The following also works:

  ```
  defmodule MyApp.Dynamo do
    use ExAws.Dynamo.Client

    def config_root do
      Application.get_all_env(:my_aws_config_root)
    end
  end
  ```
  ExAws now expects the config for that dynamo client to live under

  ```elixir
  config :my_aws_config_root
    dynamodb: [] # Dynamo config goes here
  ```

  Default config values can be found in ExAws.Config.

  ## General notes
  All options are handled as underscored atoms instead of camelcased binaries as specified
  in the Dynamo API. IE `IndexName` would be `:index_name`. Anywhere in the API that requires
  dynamo type annotation (`{"S":"mystring"}`) is handled for you automatically. IE

  ```elixir
  ExAws.Dynamo.scan("Users", expression_attribute_values: [api_key: "foo"])
  ```
  Transforms into a query of
  ```elixir
  %{"ExpressionAttributeValues" => %{api_key: %{"S" => "foo"}}, "TableName" => "Users"}
  ```

  Consult the function documentation to see precisely which options are handled this way.

  If you wish to avoid this kind of automatic behaviour you are free to specify the types yourself.
  IE:
  ```elixir
  ExAws.Dynamo.scan("Users", expression_attribute_values: [api_key: %{"B" => "Treated as binary"}])
  ```
  Becomes:
  ```elixir
  %{"ExpressionAttributeValues" => %{api_key: %{"B" => "Treated as binary"}}, "TableName" => "Users"}
  ```
  Alternatively, if what's being encoded is a struct, you're always free to implement ExAws.Dynamo.Encodable for that struct.

  ## Examples

  ```elixir
  defmodule User do
    @derive [ExAws.Dynamo.Encodable]
    defstruct [:email, :name, :age, :admin]
  end

  alias ExAws.Dynamo

  # Create a users table with a primary key of email [String]
  # and 1 unit of read and write capacity
  Dynamo.create_table("Users", "email", %{email: :string}, 1, 1)

  user = %User{email: "bubba@foo.com", name: "Bubba", age: 23, admin: false}
  # Save the user
  Dynamo.put_item("Users", user)

  # Retrieve the user by email and decode it as a User struct.
  result = Dynamo.get_item!("Users", %{email: user.email})
  |> Dynamo.Decoder.decode(as: User)

  assert user == result
  ```

  http://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Operations.html
  """

  ## Tables
  ######################

  @type table_name :: binary
  @type primary_key :: [{atom, binary}] | %{atom => binary}
  @type exclusive_start_key_vals :: [{atom, binary}] | %{atom => binary}
  @type expression_attribute_names_vals :: %{binary => binary}
  @type expression_attribute_values_vals :: [{atom, binary}] | %{atom => binary}
  @type return_consumed_capacity_vals ::
    :none |
    :total |
    :indexes
  @type select_vals ::
    :all_attributes |
    :all_projected_attributes |
    :specific_attributes |
    :count
  @type return_values_vals ::
    :none |
    :all_old |
    :updated_old |
    :all_new |
    :updated_new
  @type return_item_collection_metrics_vals ::
    :size |
    :none

  @doc "List tables"
  defcallback list_tables() :: ExAws.Request.response_t

  @doc "Create table"
  defcallback create_table(
    table_name      :: binary,
    primary_key     :: binary,
    key_definitions :: Keyword.t,
    read_capacity   :: pos_integer,
    write_capacity  :: pos_integer) :: ExAws.Request.response_t

  @doc "Create table with indices"
  defcallback create_table(
    table_name      :: binary,
    primary_key     :: binary,
    key_definitions :: [%{}],
    read_capacity   :: pos_integer,
    write_capacity  :: pos_integer,
    global_indexes  :: Keyword.t,
    local_indexes   :: Keyword.t) :: ExAws.Request.response_t

  @doc "Describe table"
  defcallback describe_table(name :: binary) :: ExAws.Request.response_t

  @doc "Update Table"
  defcallback update_table(name :: binary, attributes :: Keyword.t) :: ExAws.Request.response_t

  @doc "Delete Table"
  defcallback delete_table(table :: binary) :: ExAws.Request.response_t

  ## Records
  ######################

  @doc """
  Scan table

  Please read http://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Scan.html

  Parameters with keys that are automatically annotated with dynamo types are:
  `[:exclusive_start_key, :expression_attribute_names]`
  """
  @type scan_opts :: [
    {:exclusive_start_key, exclusive_start_key_vals} |
    {:expression_attribute_names, expression_attribute_names_vals} |
    {:expression_attribute_values, expression_attribute_values_vals} |
    {:filter_expression, binary} |
    {:index_name, binary} |
    {:limit, pos_integer} |
    {:projection_expression, binary} |
    {:return_consumed_capacity, return_consumed_capacity_vals} |
    {:segment, non_neg_integer} |
    {:select, select_vals} |
    {:total_segments, pos_integer}]
  defcallback scan(table_name :: table_name) :: ExAws.Request.response_t
  defcallback scan(table_name :: table_name, opts :: scan_opts) :: ExAws.Request.response_t


  @doc """
  Stream records from table

  Same as scan/1,2 but the records are a stream which will automatically handle pagination

  ```elixir
  {:ok, %{"Items" => items}} = Dynamo.stream_scan("Users")
  items |> Enum.to_list #=> Returns every item in the Users table.
  ```
  """
  defcallback stream_scan(table_name :: table_name) :: ExAws.Request.response_t
  defcallback stream_scan(table_name :: table_name, opts :: scan_opts) :: ExAws.Request.response_t

  @doc """
  Same as stream_scan/1,2 but raises BadMatch unless
  {:ok, %{"Items" => items}} = Dynamo.stream_scan
  """
  defcallback stream_scan!(table_name :: table_name) :: Enumerable.t
  defcallback stream_scan!(table_name :: table_name, opts :: scan_opts) :: Enumerable.t

  @doc """
  Query Table

  Please read: http://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Query.html

  Parameters with keys that are automatically annotated with dynamo types are:
  `[:exclusive_start_key, :expression_attribute_names]`
  """
  @type query_opts :: [
    {:consistent_read, boolean} |
    {:exclusive_start_key, exclusive_start_key_vals} |
    {:expression_attribute_names, expression_attribute_names_vals} |
    {:expression_attribute_values, expression_attribute_values_vals} |
    {:filter_expression, binary} |
    {:index_name, binary} |
    {:key_condition_expression, binary} |
    {:limit, pos_integer} |
    {:projection_expression, binary} |
    {:return_consumed_capacity, return_consumed_capacity_vals} |
    {:scan_index_forward, boolean} |
    {:select, select_vals}]
  defcallback query(table_name :: table_name) :: ExAws.Request.response_t
  defcallback query(table_name :: table_name, opts :: query_opts) :: ExAws.Request.response_t

  @doc """
  Stream records from table

  Same as query/1,2 but the records are a stream which will automatically handle pagination

  ```elixir
  {:ok, %{"Items" => items}} = Dynamo.stream_query("Users", filter_expression: "api_key = :api_key", expression_attribute_values: [api_key: "api_key_i_want"])
  items |> Enum.to_list #=> Returns every item in the Users table with an api_key == "api_key_i_want".
  ```
  """
  defcallback stream_query(table_name :: table_name) :: ExAws.Request.response_t
  defcallback stream_query(table_name :: table_name, opts :: query_opts) :: ExAws.Request.response_t

  @doc """
  Same as stream_query/1,2 but raises BadMatch unless
  {:ok, %{"Items" => items}} = Dynamo.stream_query
  """
  defcallback stream_query!(table_name :: table_name) :: Enumerable.t
  defcallback stream_query!(table_name :: table_name, opts :: query_opts) :: Enumerable.t

  @doc """
  Get up to 100 items (16mb)

  Map of table names to request parameter maps.
  http://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_BatchGetItem.html

  Parameters with keys that are automatically annotated with dynamo types are:
  `[:keys]`

  ```elixir
  Dynamo.batch_get_item(%{
    "Users" => [
      consistent_read: true,
      keys: [
        [api_key: "key1"],
        [api_key: "api_key2"]
      ]
    ],
    "Subscriptions" => %{
      keys: [
        %{id: "id1"}
      ]
    }
  })
  ```
  As you see you're largely free to use either keyword args or maps in the body. A map
  is required for the argument itself because the table names are most often binaries, and I refuse
  to inflict proplists on anyone.

  """
  @type batch_get_item_opts :: [
    {:return_consumed_capacity, return_consumed_capacity_vals}
  ]
  @type get_item :: [
    {:consistent_read, boolean} |
    {:keys, [primary_key]}
  ]
  defcallback batch_get_item(%{table_name => get_item}) :: ExAws.Request.response_t
  defcallback batch_get_item(%{table_name => get_item}, opts :: batch_get_item_opts) :: ExAws.Request.response_t

  @doc """
  Put or delete up to 25 items (16mb)

  Map of table names to request parameter maps.
  http://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_BatchWriteItem.html

  Parameters with keys that are automatically annotated with dynamo types are:
  `[:keys]`
  """
  @type write_item :: [
    [delete_request: [key: primary_key]] |
    [put_request: [item: %{}]]
  ]
  @type batch_write_item_opts :: [
    {:return_consumed_capacity, return_consumed_capacity_vals} |
    {:return_item_collection_metrics, return_item_collection_metrics_vals}
  ]
  defcallback batch_write_item(%{table_name => [write_item]}) :: ExAws.Request.response_t
  defcallback batch_write_item(%{table_name => [write_item]}, opts :: batch_write_item_opts) :: ExAws.Request.response_t

  @doc "Put item in table"
  @type put_item_opts :: [
    {:condition_expression, binary} |
    {:expression_attribute_names, expression_attribute_names_vals} |
    {:expression_attribute_values, expression_attribute_values_vals} |
    {:return_consumed_capacity, return_consumed_capacity_vals} |
    {:return_item_collection_metrics, return_item_collection_metrics_vals } |
    {:return_values, return_values_vals}
  ]
  defcallback put_item(table_name :: table_name, record :: %{}) :: ExAws.Request.response_t
  defcallback put_item(table_name :: table_name, record :: %{}, opts :: put_item_opts) :: ExAws.Request.response_t

  @doc "Get item from table"
  @type get_item_opts :: [
    {:consistent_read, boolean} |
    {:expression_attribute_names, expression_attribute_names_vals} |
    {:projection_expression, binary} |
    {:return_consumed_capacity, return_consumed_capacity_vals}
  ]
  defcallback get_item(table_name :: table_name, primary_key :: primary_key) :: ExAws.Request.response_t
  defcallback get_item(table_name :: table_name, primary_key :: primary_key, opts :: get_item_opts) :: ExAws.Request.response_t

  @doc "Get an item from a dynamo table, and raise if it does not exist or there is an error"
  defcallback get_item!(table_name :: table_name, primary_key :: primary_key) :: %{}
  defcallback get_item!(table_name :: table_name, primary_key :: primary_key, opts :: get_item_opts) :: %{}

  @doc """
  Update item in table

  For update_args format see
  http://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_UpdateItem.html
  """
  @type update_item_opts :: [
    {:condition_expression, binary} |
    {:expression_attribute_names, expression_attribute_names_vals} |
    {:expression_attribute_values, expression_attribute_values_vals} |
    {:return_consumed_capacity, return_consumed_capacity_vals} |
    {:return_item_collection_metrics, return_item_collection_metrics_vals } |
    {:return_values, return_values_vals } |
    {:update_expression, binary}
  ]
  defcallback update_item(table_name :: table_name, primary_key :: primary_key, opts :: update_item_opts) :: ExAws.Request.response_t

  @doc "Delete item in table"
  @type delete_item_opts :: [
    {:condition_expression, binary} |
    {:expression_attribute_names, expression_attribute_names_vals} |
    {:expression_attribute_values, expression_attribute_values_vals} |
    {:return_consumed_capacity, return_consumed_capacity_vals} |
    {:return_item_collection_metrics, return_item_collection_metrics_vals } |
    {:return_values, return_values_vals}
  ]
  defcallback delete_item(table_name :: table_name, primary_key :: primary_key) :: ExAws.Request.response_t
  defcallback delete_item(table_name :: table_name, primary_key :: primary_key, opts :: delete_item_opts) :: ExAws.Request.response_t

  @doc """
  Enables custom request handling.

  By default this just forwards the request to the `ExAws.Dynamo.Request.request/2`.
  However, this can be overriden in your client to provide pre-request adjustments to headers, params, etc.
  """
  defcallback request(data :: %{}, action :: atom)

  @doc "Service"
  defcallback service() :: atom

  @doc "Retrieves the root AWS config for this client"
  defcallback config_root() :: Keyword.t

  @doc "Returns the canonical configuration for this service"
  defcallback config() :: Keyword.t

  defmacro __using__(opts) do
    boilerplate = __MODULE__
    |> ExAws.Client.generate_boilerplate(opts)

    quote do
      unquote(boilerplate)

      @doc false
      def request(data, action) do
        ExAws.Dynamo.Request.request(__MODULE__, action, data)
      end

      @doc false
      def service, do: :dynamodb

      defoverridable config_root: 0, request: 2
    end
  end

end
