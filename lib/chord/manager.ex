defmodule Chord.Manager do
  use GenServer
  alias Chord.Node

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: :manager)
  end

  @spec establish_successor_connections() :: any()
  def establish_successor_connections do
    GenServer.call(:manager, {:establish})
  end

  def generate_keys do
    GenServer.call(:manager, {:generate_keys})
  end

  def get_all_nodes do
    GenServer.call(:manager, {:get_all_nodes})
  end

  def init({nodes, m_bits}) do
    nodes = nodes |> Enum.sort()

    map = %{nodes: nodes, m_bits: m_bits, hops: []}
    {:ok, map}
  end

  def handle_call({:establish}, _from, state) do
    state.nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, index} ->
      {next_node, prev_node} = find_next_prev(index, state.nodes)
      Node.add_connections(node, [next_node], [prev_node])
      {"ds", "dsf"}
    end)

    {:reply, state.m_bits, state}
  end

  def handle_call({:generate_keys}, _from, state) do
    keys =
      state.nodes
      |> Enum.slice(1, length(state.nodes))
      |> Enum.map(fn x -> Node.generate_keys(x) end)

    keys = keys |> Enum.reduce([], fn x, acc -> acc ++ x end)

    {:reply, keys, Map.put(state, :keys, keys)}
  end

  def handle_call({:get_all_nodes}, _from, state) do
    {:reply, state.nodes, state}
  end

  def find_next_prev(index, nodes) do
    next_index = mod(index + 1, length(nodes))
    prev_index = mod(index - 1, length(nodes))
    next_node = Enum.at(nodes, next_index)
    prev_node = Enum.at(nodes, prev_index)
    {next_node, prev_node}
  end

  defp mod(x, y) when x > 0, do: rem(x, y)
  defp mod(x, y) when x < 0, do: rem(x, y) + y
  defp mod(0, _y), do: 0
end
