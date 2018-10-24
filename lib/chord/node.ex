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
              val = find_next_node(state.fingers, key, state.name)

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

  def find_next_node(fingers, key, me) do
    max_value = Enum.max(fingers)
    max_index = Enum.find_index(fingers, fn x -> x == max_value end)
    left_list = 0..max_index |> Enum.map(fn x -> Enum.at(fingers, x) end)

    right_list =
      if max_index + 1 < length(fingers) do
        (max_index + 1)..length(fingers) |> Enum.map(fn x -> Enum.at(fingers, x) end)
      else
        []
      end

    if length(right_list) == 0 do
      last = Enum.at(fingers, length(fingers) - 1)
      first = Enum.at(fingers, 0)

      if key >= last or key < me do
        last
      else
        less_than_me = fingers |> Enum.filter(fn x -> key >= x end)

        if length(less_than_me) == 0 do
          first
        else
          Enum.max(less_than_me)
        end
      end
    else
      if key <= me do
        less_than_me = right_list |> Enum.filter(fn x -> key >= x end)

        if length(less_than_me) == 0 do
          max_value
        else
          Enum.max(less_than_me)
        end
      else
        if(key >= max_value) do
          max_value
        else
          less_than_me = left_list |> Enum.filter(fn x -> key >= x end)

          if length(less_than_me) == 0 do
            Enum.at(fingers, 0)
          else
            Enum.max(less_than_me)
          end
        end
      end
    end
  end

  defp save_to_ets(name, connections, previous, fingers, keys) do
    :ets.insert(:node_lookup, {Integer.to_string(name), {connections, previous, fingers, keys}})
  end
end
