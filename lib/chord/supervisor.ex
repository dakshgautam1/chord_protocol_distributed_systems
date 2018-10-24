defmodule Chord.Supervisor do
  use Supervisor
  alias Chord.Node
  alias Chord.Manager

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def hashFunction(hashThisString, mValue) do
    hashedString = Base.encode16(:crypto.hash(:sha, hashThisString)) |> String.slice(0..mValue)
    numberIdentifier = String.to_integer(hashedString, 16)
    numberIdentifier
  end

  def dummy_hash() do
    s = "12345"
    y1 = :crypto.hash(:sha256, s) |> Base.encode16()
    y = String.slice(y1, 0..2)
    y = String.to_integer(y, 16)
    m = round(getm(y))
    m1 = round(:math.pow(2, m) - 1)

    # new m
    m2 = check_m_value(m1, m, 10000)

    # new m1
    max = round(:math.pow(2, m2) - 1)
    {max, m2}
  end

  def check_m_value(m1, m, n) do
    if m1 < n do
      m = m + 1
      m1 = round(:math.pow(2, m) - 1)
      check_m_value(m1, m, n)
    else
      m
    end
  end

  def getm(x) when x > 15 do
    z = Enum.random(120..175)
    div(z, 10)
  end

  def getm(x) when x <= 15 do
    x
  end

  def random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.url_encode64() |> binary_part(0, length)
  end

  def generate_randomized_name(set, m) do
    new_value = :rand.uniform(m)

    case MapSet.member?(set, new_value) do
      true ->
        generate_randomized_name(set, m)

      false ->
        updated_set = MapSet.put(set, new_value)
        {updated_set, new_value}
    end
  end

  def init(args) do
    {nodes, _} = args

    children = [
      {Registry, keys: :unique, name: Chord.Registry}
    ]

    {max, m_bits} = dummy_hash()

    server_random_names =
      1..nodes
      |> Enum.reduce({MapSet.new(), []}, fn _x, {result_map, result_list} ->
        {new_set, new_value} = generate_randomized_name(result_map, max)
        {new_set, result_list ++ [new_value]}
      end)

    {_, node_names} = server_random_names

    node_server_names =
      node_names
      |> Enum.with_index()
      |> Enum.map(fn {name, index} ->
        {name, String.to_atom("node_server_#{index}")}
      end)

    # |> Enum.map(fn node ->

    #   {,
    #    "node_server_#{node}" |> String.to_atom()}
    # end)

    # Path.expand('./text.txt')
    # |> Path.absname()
    # |> File.write("#{inspect(node_server_names)}", [:write])

    node_server_children =
      node_server_names
      |> Enum.map(fn {node, node_atom} ->
        %{
          id: node_atom,
          start: {Node, :start_link, [node]}
        }
      end)

    children = children ++ node_server_children

    node_server_names_string =
      node_server_names
      |> Enum.map(fn {node, _} -> node end)

    node_server_names_string = node_server_names_string |> Enum.sort()

    children =
      children ++
        [
          %{
            id: Manager,
            start: {Manager, :start_link, [{node_server_names_string, m_bits}]}
          }
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
