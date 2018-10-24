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
              # IO.puts("Search key - #{search_key_random} starting from #{node}")
              _base = Enum.at(node_list, 0)

              {_key, hops_till_now} =
                find_key_process(
                  node,
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
      # summed_nodes =
      #   1..m_bits
      #   |> Enum.map(fn k ->
      #     new_number = (x + :math.pow(2, k - 1)) |> trunc()
      #     finder(nodes, new_number, index)
      #   end)

      # summed_nodes = Enum.filter(summed_nodes, fn x -> x != nil end)
      # IO.puts("finger nodes #{inspect(summed_nodes)}")
      generated_fingers = figure_out_finger_nodes(nodes, index, x, m_bits)
      IO.puts("generated finger nodes for node : #{index}")

      Chord.Node.add_fingers(x, generated_fingers)
    end)
  end

  def upper_arr(number_list, start_index, last_index, curr, curr_bits, m_bits, result) do
    cond do
      start_index >= last_index ->
        {result, curr_bits}

      curr_bits == m_bits ->
        {result, curr_bits}

      true ->
        current_list_value = Enum.at(number_list, start_index)
        added = :math.pow(2, curr_bits) + curr

        ans =
          if(current_list_value > added) do
            new_list = result ++ [current_list_value]

            upper_arr(
              number_list,
              start_index,
              last_index,
              curr,
              curr_bits + 1,
              m_bits,
              new_list
            )
          else
            new_list = result ++ []
            upper_arr(number_list, start_index + 1, last_index, curr, curr_bits, m_bits, new_list)
          end

        ans
    end
  end

  def lower_arr(
        number_list,
        start_index,
        last_index,
        last_number,
        current_number,
        curr_bits,
        m_bits,
        result
      ) do
    cond do
      start_index == last_index ->
        {result, curr_bits}

      curr_bits == m_bits ->
        {result, curr_bits}

      true ->
        current_list_value = Enum.at(number_list, start_index)
        added = ((current_number + :math.pow(2, curr_bits)) |> trunc()) - last_number

        ans =
          if(current_list_value > added) do
            new_list = result ++ [current_list_value]

            # IO.puts(
            #   "This the diff from orginal #{added} with currenvalue #{inspect(new_list)} and for #{
            #     current_number
            #   } and #{last_number}"
            # )

            lower_arr(
              number_list,
              start_index,
              last_index,
              last_number,
              current_number,
              curr_bits + 1,
              m_bits,
              new_list
            )
          else
            lower_arr(
              number_list,
              start_index + 1,
              last_index,
              last_number,
              current_number,
              curr_bits,
              m_bits,
              result
            )
          end

        ans
    end
  end

  # def y(number_list, my_index, end_index, curr, curr_bits, m_bits, result) do
  #   {l, x} = lower_arr(number_list, my_index, end_index, curr, curr_bits, m_bits, result)
  # end

  def figure_out_finger_nodes(number_list, my_index, curr, m_bits) do
    start = my_index
    end_index = length(number_list)

    {first_half, bits_consumed} =
      upper_arr(number_list, start, end_index, Enum.at(number_list, my_index), 0, m_bits, [])

    {second_half, _} =
      lower_arr(
        number_list,
        0,
        my_index,
        Enum.at(number_list, length(number_list) - 1),
        curr,
        bits_consumed,
        m_bits,
        []
      )

    # IO.puts("first #{inspect(first_half)} second #{inspect(second_half)}")
    y = first_half ++ second_half
    # IO.puts("Complete list #{inspect(y)}")
    y
  end

  def find_key_process(caller_, key, hops_till_now, node_list_len, caller) do
    ans = Chord.Node.check_key(caller_, key, hops_till_now + 1)
    max_possible = :math.log2(node_list_len) |> trunc()

    if hops_till_now >= node_list_len do
      # Will never use this just in case
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
