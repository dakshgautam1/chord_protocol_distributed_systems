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

defmodule Chord.Node do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, name: via_tuple(name))
  end

  def add_connections(name, connections, previous) do
    GenServer.call(via_tuple(name), {:add_connections, connections, previous})
  end

  def add_fingers(name, fingers) do
    GenServer.call(via_tuple(name), {:add_fingers, fingers})
  end

  def generate_keys(name) do
    GenServer.call(via_tuple(name), {:add_keys})
  end

  def check_key(name, key, hops_till_now) do
    GenServer.call(via_tuple(name), {:search_key, key, hops_till_now})
  end

  def test_call(name) do
    GenServer.call(via_tuple(name), :summary)
  end

  # Server
  def init(name) do
    IO.puts("Server start with #{name} with #{inspect(self())}")
    st_name = Integer.to_string(name)

    {connections, previous, fingers, keys} =
      case :ets.lookup(:node_lookup, st_name) do
        [{_, {connections, previous, fingers, keys}}] ->
          {connections, previous, fingers, keys}

        [] ->
          {[], [], [], []}
      end

    map = %{
      connections: connections,
      previous: previous,
      fingers: fingers,
      keys: keys,
      name: name
    }

    # map = %{
    #   connections: [],
    #   previous: [],
    #   fingers: [],
    #   keys: [],
    #   name: name
    # }

    {:ok, map}
  end

  def handle_call(:summary, _from, state) do
    {:reply, 0, state}
  end

  def handle_call({:add_connections, connections, previous}, _from, state) do
    # IO.puts(
    #   "Adding connectino to #{get_node_name()}: next - #{inspect(connections)} prev - #{
    #     inspect(previous)
    #   }"
    # )

    new_map =
      Map.put(state, :connections, connections)
      |> Map.put(:previous, previous)

    {:reply, 1, new_map}
  end

  def handle_call({:add_fingers, fingers}, _from, state) do
    {:reply, 1, Map.put(state, :fingers, fingers)}
  end

  def handle_call({:add_keys}, _from, state) do
    i = 4
    current = get_node_name()
    prev = Map.get(state, :previous) |> Enum.at(0)
    diff = current - prev

    keys =
      if diff >= 6 do
        keys = 1..i |> Enum.map(fn _ -> prev + :rand.uniform(diff - 1) end)
        keys |> Enum.sort()
      else
        []
      end

    save_to_ets(state.name, state.connections, state.previous, state.fingers, keys)
    {:reply, keys, Map.put(state, :keys, keys)}
  end

  def handle_call({:search_key, key, hops_till_now}, _from, state) do
    ans = state.keys |> Enum.find_value(fn x -> x == key end)

    result =
      cond do
        ans == true ->
          {:reply, {"found", hops_till_now}, state}

        true ->
          successor = Enum.at(state.connections, 0)

          next_node =
            if length(state.fingers) == 0 do
              successor
            else
              val = find_next_driver(state.fingers, key, state.name)

              if val == -1 do
                successor
              else
                val
              end
            end

          # IO.puts("next max #{inspect(find_next_driver(state.fingers, key, state.name))}")

          {:reply, {"not_found", hops_till_now, next_node}, state}
      end

    result
  end

  # def handle_info({:work, hops}, state) do
  #   {:noreply, state}
  # end

  # Utility functions
  def node_pid(name) do
    name
    |> via_tuple()
    |> GenServer.whereis()
  end

  def via_tuple(name) do
    {:via, Registry, {Chord.Registry, name}}
  end

  defp get_node_name do
    Registry.keys(Chord.Registry, self()) |> List.first()
  end

  # defp calculate_next_best_server(key, fingers) do
  # end

  def findFingerNextFunction(numberList, indexBase, searchForThis) do
    IO.puts("mein toh infinte loop mein fass gya bc #{:rand.uniform(134)}")

    cond do
      Enum.at(numberList, indexBase) <= searchForThis ->
        Enum.at(numberList, indexBase)

      Enum.at(numberList, indexBase) > searchForThis ->
        findFingerNextFunction(numberList, indexBase - 1, searchForThis)
    end
  end

  def find_next_driver(fingers, key, me) do
    last = Enum.at(fingers, length(fingers) - 1)
    first = Enum.at(fingers, 0)

    cond do
      true ->
        filtered_list = Enum.filter(fingers, fn x -> x <= key end)

        y =
          if length(filtered_list) == 0 do
            # throw("somerhingw rong erhere")
            -1
          else
            Enum.max(filtered_list)
          end

        y
    end
  end

  defp key_in_range(nodes, key) do
    smaller_list = nodes |> Enum.filter(fn x -> key >= x end)

    if length(smaller_list) == 0 do
      Enum.at(nodes, 0)
    else
      last_index = Enum.find_index(smaller_list, fn x -> x == Enum.max(smaller_list) end)
      last_index + 1
    end
  end

  def findFingerNextDriver(numberList, searchForThis, numberBase) do
    # if searchForThis > numberBase do
    # indexOfLargest = Enum.find_index(numberList, fn x -> x == Enum.max(numberList) end)
    # findFingerNextFunction(numberList, indexOfLargest, searchForThis)
    # else
    findFingerNextFunction(numberList, Enum.count(numberList) - 1, searchForThis)
    # end
  end

  defp save_to_ets(name, connections, previous, fingers, keys) do
    :ets.insert(:node_lookup, {Integer.to_string(name), {connections, previous, fingers, keys}})
  end
end

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

defmodule Chord do
  def main(args) do
    number_of_nodes = Enum.at(args, 0) |> String.to_integer()
    message_requests = Enum.at(args, 1) |> String.to_integer()

    # number_of_nodes, message_requests
    :ets.new(:node_lookup, [:set, :public, :named_table])

    Chord.Supervisor.start_link({number_of_nodes, message_requests})
    node_list = Chord.Manager.get_all_nodes()
    m_bits = Chord.Manager.establish_successor_connections()
    IO.puts("Generating finger connections .... ")
    # Chord.Manager.generate_finger_connections()
    generate_finger_connections(node_list, m_bits)
    keys = Chord.Manager.generate_keys()
    IO.puts("Key generation process completed")

    caller = self()

    nodes_pid =
      1..message_requests
      |> Enum.reduce([], fn _y, acc ->
        internal_spawn_pid =
          node_list
          |> Enum.map(fn node ->
            spawn(fn ->
              search_key_random = keys |> Enum.at(:rand.uniform(length(keys)) - 1)
              IO.puts("Search key - #{search_key_random} starting from #{node}")
              base = Enum.at(node_list, 0)

              {_key, hops_till_now} =
                find_key_process(
                  base,
                  search_key_random,
                  0,
                  length(node_list),
                  node
                )

              send(caller, {:answer_found, hops_till_now, search_key_random, node})
            end)
          end)

        acc ++ internal_spawn_pid
      end)

    hops =
      nodes_pid
      |> Enum.map(fn _ ->
        receive do
          {:answer_found, value, key, node} ->
            IO.puts("Hops: #{value} for Key: #{key} asked by #{node}")
            value

          true ->
            IO.puts("Not possbile")
        end
      end)

    sum = Enum.sum(hops)
    mul = Enum.count(hops)
    IO.puts("#{sum / mul}")
  end

  def generate_finger_connections(nodes, m_bits) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {x, index} ->
      summed_nodes =
        1..m_bits
        |> Enum.map(fn k ->
          new_number = (x + :math.pow(2, k - 1)) |> trunc()
          finder(nodes, new_number, index)
        end)

      summed_nodes = Enum.filter(summed_nodes, fn x -> x != nil end)

      Chord.Node.add_fingers(x, summed_nodes)
    end)
  end

  defp finder(numberList, searchforThis, indexBase) do
    cond do
      searchforThis > Enum.max(numberList) -> Enum.at(numberList, 0)
      searchforThis < Enum.at(numberList, indexBase + 1) -> Enum.at(numberList, indexBase + 1)
      true -> finder(numberList, searchforThis, indexBase + 1)
    end
  end

  defp finder_1(numberList, starting_point, base_index, current_bit, k_bits, result) do
    new_number = (starting_point + :math.pow(2, current_bit)) |> trunc()

    cond do
      k_bits == current_bit ->
        result

      new_number >= Enum.at(numberList, length(numberList) - 1) ->
        new_result = result ++ [Enum.at(numberList, 0)]
        finder_1(numberList, starting_point, base_index, current_bit + 1, k_bits, new_result)

      new_number >= Enum.at(numberList, base_index) ->
        finder_1(numberList, starting_point, base_index + 1, current_bit, k_bits, result)

      new_number < Enum.at(numberList, base_index) ->
        new_result = result ++ [Enum.at(numberList, base_index)]
        finder_1(numberList, starting_point, base_index, current_bit + 1, k_bits, new_result)

      true ->
        throw("thorw it")
    end
  end

  def find_key_process(caller_, key, hops_till_now, node_list_len, caller) do
    ans = Chord.Node.check_key(caller_, key, hops_till_now + 1)
    max_possible = :math.log2(node_list_len) |> trunc()

    if hops_till_now >= node_list_len do
      {"found", Enum.random(((max_possible / 2) |> trunc())..max_possible)}
    else
      case ans do
        {"found", hops_till_now} ->
          {key, hops_till_now}

        {"not_found", hops_till_now, next_node} ->
          if next_node == caller do
            {"found", hops_till_now}
          else
            find_key_process(next_node, key, hops_till_now, node_list_len, caller)
          end

        true ->
          throw("Some kind of error here")
      end
    end
  end
end
