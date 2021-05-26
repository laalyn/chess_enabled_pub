defmodule ChessEnabled.Matches do
  import Ecto.Query, warn: false
  alias ChessEnabled.Repo

  alias ChessEnabled.Accounts.User
  alias ChessEnabled.Players.Player
  alias ChessEnabled.Matches.Match
  alias ChessEnabled.Moves.Move
  alias ChessEnabled.Pieces.Piece

  alias ChessEnabled.Codes

  # TODO cleaner idx implementation
  #   right now it just happens to work

  def get_match(match_id) do
    try do
      Repo.transaction(fn ->
        Repo.query!("set transaction isolation level repeatable read")

        get_match_imp(match_id)
      end)
    rescue err ->
      stacktrace = __STACKTRACE__
      case err do
        %Postgrex.Error{} ->
          if err.postgres.code == :serialization_failure || err.postgres.code == :deadlock_detected do
            IO.puts("retrying..")
            get_match(match_id)
          else
            IO.inspect(stacktrace)
            raise err
          end
        err ->
          IO.inspect(stacktrace)
          raise err
      end
    end
  end

  defp get_match_imp(match_id) do
    # TODO have code that can scale up to multiple game types

    # matches: {type, next_idx}, [players: {status}, moves (top): {pieces}, moves (aggregated): {time_spent, running}]
    match_query = from m in Match,
                       select: m,
                       where: m.id == ^match_id
    match = match_query
            |> Repo.all()

    if length(match) == 0 do
      raise Codes.nonexistent
    end

    [match] = match

    if match.closed do
      raise Codes.closed
    end

    match_idx = match.next_idx - 1

    players_query = from p in Player,
                         select: p,
                         where: p.match_id == ^match_id
    players = players_query
              |> Repo.all()

    # if timed out on accept, delete it
    if (hd(players).status == "pending" || hd(players).status == "accepted") && abs(DateTime.diff(DateTime.utc_now, hd(players).inserted_at, :second)) >= 30 do
      clear_match_imp(hd(players).match_id)

      raise Codes.nonexistent
    end

    # get pieces (last idx)
    pieces_query =
"(select distinct on (moves.piece_id) moves.row, moves.col, players.user_id, pieces.id, pieces.type from moves
join players on moves.player_id = players.id
join pieces on moves.piece_id = pieces.id
where pieces.match_id = '#{match_id}'
order by moves.piece_id, moves.idx desc)
intersect
(select distinct on (moves.row, moves.col) moves.row, moves.col, players.user_id, pieces.id, pieces.type from moves
join players on moves.player_id = players.id
join pieces on moves.piece_id = pieces.id
where pieces.match_id = '#{match_id}'
order by moves.row, moves.col, moves.idx desc)
"
    pieces = pieces_query
             |> Repo.query!

    pieces = Enum.map(pieces.rows, fn ([row, col, user_id, piece_id, type]) ->
      user_id = Ecto.UUID.cast!(user_id)
      piece_id = Ecto.UUID.cast!(piece_id)

      %{
        row: row,
        col: col,
        user_id: user_id,
        id: piece_id,
        type: type,
      }
    end)

    moves_query = from m in Move,
                       join: p in Player, on: m.player_id == p.id,
                       select: m,
                       where: p.match_id == ^match_id, # could use distinct
                       order_by: [asc: m.idx]
    moves = moves_query
            |> Repo.all()

    players = Enum.reduce(players, %{}, fn (cur, acc) ->
      player_id = cur.id

      # aggregate the moves
      {_, time_spent} = Enum.reduce(moves, {0, 0}, fn (cur, {last_timestamp, time_spent}) ->
        if cur.idx == -1 || cur.player_id != player_id do
          {cur.updated_at, time_spent}
        else
          {cur.updated_at, time_spent + abs(DateTime.diff(cur.updated_at, last_timestamp, :microsecond))}
        end
      end)

      # get last turn timestamp
      running = if cur.status == "turn" do
        # get last move
        last_move_query = from m in Move,
                               join: p in Player, on: m.player_id == p.id,
                               select: m.updated_at,
                               where: p.match_id == ^match_id,
                               order_by: [desc: m.idx],
                               limit: 1
        [last_move_timestamp] = last_move_query
                                |> Repo.all()

        last_move_timestamp
      else
        false
      end

      entry = %{
        color: (if cur.idx == 0, do: "white", else: "black"),
        time_spent: time_spent,
        running: running,
      }

      IO.inspect(time_spent)

      acc
      |> Map.put(cur.user_id, entry)
    end)

    # if time spent is over 10 minutes, close the match
    players
    |> Enum.each(fn ({key, val}) ->
      if div(val.time_spent + (if val.running, do: abs(DateTime.diff(DateTime.utc_now, val.running, :microsecond)), else: 0), 60_000_000) >= 10 do
        close_match_imp(match.id)

        raise Codes.closed
      end
    end)

    match = %{
      players: players,
      pieces: pieces,
    }

    {:ok, match_idx, match}
  end

  def list_matches(user_id) do
    try do
      Repo.transaction(fn ->
        Repo.query!("set transaction isolation level repeatable read")

        list_query = from p in Player,
                       where: p.user_id == ^user_id,
                       join: m in Match, on: p.match_id == m.id,
                       select: [p, m],
                       order_by: [desc: p.updated_at]
        list = list_query
               |> Repo.all()

        user_query = from u in User,
                       select: [u.id, u.next_idx],
                       where: u.id == ^user_id,
                       limit: 1
        [[_, next_idx]] = user_query
                          |> Repo.all()

        # get the top match if not closed to 'fix' it
        list = if length(list) > 0 do
          [player, match] = hd(list)
          if !match.closed do
            try do
              get_match_imp(match.id)
              list
            rescue err ->
              good = case err do
                %RuntimeError{message: message} ->
                  cond do
                    message == Codes.nonexistent || message == Codes.closed ->
                      true
                    true ->
                      false
                  end
                _ ->
                  false
              end

              if good do
                tl list
              else
                IO.inspect(__STACKTRACE__)
                raise err
              end
            end
          else
            list
          end
        else
          list
        end

        matches = Enum.map(list, fn ([player, match]) ->
          %{
            type: match.type,
            closed: match.closed,
            idx: match.next_idx - 1,
            status: player.status,
            elo_delta: player.elo_delta,
            match_id: match.id,
            inserted_at: match.inserted_at,
          }
        end)

        elo = Enum.reduce(matches, 1200, fn (cur, acc) ->
          if cur.elo_delta != nil do
            acc + cur.elo_delta
          else
            acc
          end
        end)

        num_wins_query = from p in Player,
                       select: count(p),
                       where: p.user_id == ^user_id and p.status == "won"
        num_wins = num_wins_query
               |> Repo.all()

        num_wins = if length(num_wins) == 0, do: 0, else: hd num_wins

        {:ok, next_idx - 1, %{list: matches, elo: elo, wins: num_wins}}
      end)
    rescue err ->
      stacktrace = __STACKTRACE__
      case err do
        %Postgrex.Error{} ->
          if err.postgres.code == :serialization_failure || err.postgres.code == :deadlock_detected do
            IO.puts("retrying..")
            list_matches(user_id)
          else
            IO.inspect(stacktrace)
            raise err
          end
        err ->
          IO.inspect(stacktrace)
          raise err
      end
    end
  end

  def send_move!(user_id, match_id, piece_id, to_r, to_c) do
    try do
      Repo.transaction(fn ->
        Repo.query!("set transaction isolation level repeatable read")

        # get original match
        match_query = from m in Match,
                        select: [m.id, m.next_idx, m.closed],
                        where: m.id == ^match_id
        [[_, match_idx, closed]] = match_query
                                   |> Repo.all()
        # TODO error handle if match doesn't exist

        if closed do
          raise "match is closed"
        end

        # lock session
        inc_idx_query = from m in Match,
                          update: [set: [next_idx: m.next_idx + 1]],
                          where: m.id == ^match_id
        inc_idx_query
        |> Repo.update_all([])

        # check if user is part of match and if already accepted or not
        user_match_query = from p in Player,
                             select: p,
                             where: p.user_id == ^user_id and p.match_id == ^match_id
        user_match = user_match_query
                     |> Repo.all()

        if length(user_match) == 0 do
          raise "not member of match"
        end

        if hd(user_match).status != "turn" do
          raise "not your turn"
        end

        player_id = hd(user_match).id

        player_idx = hd(user_match).idx

        color = if player_idx == 0, do: "white", else: "black"

        # make a move
        # get original piece
        piece_query = from m in Move,
                        select: [m.row, m.col],
                        where: m.player_id == ^player_id and m.piece_id == ^piece_id,
                        order_by: [desc: m.idx],
                        limit: 1
        piece = piece_query
                |> Repo.all()

        if length(piece) == 0 do
          raise "not your piece"
        end

        [[from_r, from_c]] = piece

        # build the board
        # get pieces (last idx)
        pieces_query =
"(select distinct on (moves.piece_id) moves.row, moves.col, moves.player_id, pieces.type from moves
join pieces on moves.piece_id = pieces.id
where pieces.match_id = '#{match_id}'
order by moves.piece_id, moves.idx desc)
intersect
(select distinct on (moves.row, moves.col) moves.row, moves.col, moves.player_id, pieces.type from moves
join pieces on moves.piece_id = pieces.id
where pieces.match_id = '#{match_id}'
order by moves.row, moves.col, moves.idx desc)
"
        pieces = pieces_query
                 |> Repo.query!

        pieces = Enum.map(pieces.rows, fn ([row, col, player_id, type]) ->
          user_id = Ecto.UUID.cast!(user_id)
          piece_id = Ecto.UUID.cast!(piece_id)

          %{
            row: row,
            col: col,
            player_id: player_id,
            type: type,
          }
        end)

        # using 'vector' (log N)
        board = Enum.reduce(pieces, %{}, fn (cur, acc) ->
          player_id = Ecto.UUID.cast!(cur.player_id)

          row = (if acc[cur.row] === nil, do: %{}, else: acc[cur.row])
                |> Map.put(cur.col, %{player_id: player_id, type: cur.type})

          acc
          |> Map.put(cur.row, row)
        end)

        # now we have (from | to)_(r | c) and the board, we can start validating
        [to_r, to_c] # from_(*) is always legitimate
        |> Enum.each(fn (cur) ->
          if cur < 0 || cur >= 8 do
            raise "destination not in bounds"
          end
        end)

        if from_r == to_r && from_c == to_c do
          raise "you must move somewhere"
        end

        if board[to_r][to_c] !== nil && board[to_r][to_c].player_id == player_id do
          raise "cannot conquer your own color"
        end

        delta_r = to_r - from_r
        delta_c = to_c - from_c
        case board[from_r][from_c].type do
          "pawn" ->
            starting = from_r == (if color == "white", do: 6, else: 1)

            delta_r = if color != "white" do
              -delta_r
            else
              delta_r
            end

            cond do
              abs(delta_c) > 1 ->
                raise "pawn moved too much horizontally"
              delta_r > 0 ->
                raise "pawn cannot move downwards"
              delta_r < (if starting, do: -2, else: -1) ->
                raise "pawn moved too high"
              delta_r == 0 ->
                raise "pawn must end up higher"
              delta_r == -1 && abs(delta_c) == 1 ->
                if board[to_r][to_c] === nil do
                  raise "no pieces for pawn to conquer"
                end
              true ->
                if board[to_r][to_c] !== nil do
                  raise "pawn cannot conquer going forward"
                end
            end
          "rook" -> nil
            if delta_r != 0 && delta_c != 0 do
              raise "rook cannot move diagonally"
            end
          "knight" -> nil
            cond do
              abs(delta_r) == 2 && abs(delta_c) != 1 ->
                raise "knight can only move horizontally by 1 if you move vertically by 2"
              abs(delta_r) == 1 && abs(delta_c) != 2 ->
                raise "knight can only move vertically by 2 if you move horizontally by 1"
              abs(delta_r) > 2 && abs(delta_c) > 2 ->
                raise "knight moved too much"
              true ->
                nil
            end
          "bishop" -> nil
            if abs(delta_r) != abs(delta_c) do
              raise "bishop can only move diagonally"
            end
          "queen" -> nil
            if abs(delta_r) != abs(delta_c) && delta_r != 0 && delta_c != 0 do
              raise "diagonal move of queen must be perfect"
            end
          "king" -> nil
            if abs(delta_r) > 1 || abs(delta_c) > 1 do
              raise "king cannot move more than one step"
            end
        end

        if board[from_r][from_c].type != "knight" do
          dir_r = cond do
            delta_r < 0 ->
              -1
            delta_r > 0 ->
              1
            true ->
              0
          end

          dir_c = cond do
            delta_c < 0 ->
              -1
            delta_c > 0 ->
              1
            true ->
              0
          end

          st = {from_r + dir_r, from_c + dir_c}
          ed = {to_r, to_c}
          dir = {dir_r, dir_c}

          check_path(board, st, ed, dir)
        end

        # get last move idx
        last_move_idx_query = from m in Move,
                                join: p in Player, on: m.player_id == p.id,
                                select: [m.idx],
                                where: p.match_id == ^match_id,
                                order_by: [desc: m.idx],
                                limit: 1
        last_move_idx = last_move_idx_query
                        |> Repo.all()

        [[last_move_idx]] = last_move_idx

        # make a new move
        move = %Move {
          idx: last_move_idx + 1,
          row: to_r,
          col: to_c,
          player_id: player_id,
          piece_id: piece_id,
        }
        |> Repo.insert!

        # change turn
        change_turn_cur_query = from p in Player,
                                  update: [set: [status: "waiting"]],
                                  where: p.id == ^player_id
        change_turn_cur_query
        |> Repo.update_all([])

        change_turn_next_query = from p in Player,
                                   update: [set: [status: "turn"]],
                                   where: p.idx == ^rem(player_idx + 1, 2) and p.match_id == ^match_id # TODO hardcoded for now
        change_turn_next_query
        |> Repo.update_all([])

        # get user time spent
        moves_query = from m in Move,
                           join: p in Player, on: m.player_id == p.id,
                           select: m,
                           where: p.match_id == ^match_id,
                           order_by: [asc: m.idx]
        moves = moves_query
                |> Repo.all()

        {_, time_spent} = Enum.reduce(moves, {0, 0}, fn (cur, {last_timestamp, time_spent}) ->
          if cur.idx == -1 || cur.player_id != player_id do
            {cur.updated_at, time_spent}
          else
            {cur.updated_at, time_spent + abs(DateTime.diff(cur.updated_at, last_timestamp, :microsecond))}
          end
        end)

        # close match if king is dead
        if board[to_r][to_c] !== nil && board[to_r][to_c].type == "king" do
          {:ok, match_idx, users} = close_match_imp(match_id)

          {:ok, match_idx, time_spent, move.inserted_at, from_r, from_c, to_r, to_c, true, users}
        else
          {:ok, match_idx, time_spent, move.inserted_at, from_r, from_c, to_r, to_c, false, nil}
        end
      end)
    rescue err ->
      stacktrace = __STACKTRACE__
      case err do
        %Postgrex.Error{} ->
          if err.postgres.code == :serialization_failure || err.postgres.code == :deadlock_detected do
            IO.puts("retrying..")
            send_move!(user_id, match_id, piece_id, to_r, to_c)
          else
            IO.inspect(stacktrace)
            raise err
          end
        err ->
          IO.inspect(stacktrace)
          raise err
      end
    end
  end

  defp check_path(board, {st_r, st_c} = st, ed, {dir_r, dir_c} = dir) do
    if st != ed do
      if board[st_r][st_c] !== nil do
        raise "piece's path is blocked"
      end

      check_path(board, {st_r + dir_r, st_c + dir_c}, ed, dir)
    end
  end

  def accept_match!(user_id, match_id) do
    try do
      Repo.transaction(fn ->
        Repo.query!("set transaction isolation level repeatable read")

        # get original match
        match_query = from m in Match,
                        select: [m.id, m.next_idx],
                        where: m.id == ^match_id
        [[_, match_idx]] = match_query
                           |> Repo.all()
        # TODO error handle if match doesn't exist

        # lock session
        inc_idx_query = from m in Match,
                          update: [set: [next_idx: m.next_idx + 1]],
                          where: m.id == ^match_id
        inc_idx_query
        |> Repo.update_all([])

        # check if user is part of match and if already accepted or not
        user_match_query = from p in Player,
                             select: p,
                             where: p.user_id == ^user_id and p.match_id == ^match_id
        user_match = user_match_query
                     |> Repo.all()

        if length(user_match) == 0 do
          raise "not member of match"
        end

        if hd(user_match).status != "pending" do
          raise "already accepted"
        end

        # modify the player
        mod_player = from p in Player,
                       update: [set: [status: "accepted"]],
                       where: p.user_id == ^user_id and p.match_id == ^match_id
        mod_player
        |> Repo.update_all([])

        # check if any players still need to accept
        rin = from p in Player,
                select: count(p),
                where: p.status == "pending" and p.match_id == ^match_id
        saber = rin
                |> Repo.all()

        open = length(saber) == 0 || hd(saber) == 0

        if open do
          mod_first_player = from p in Player,
                               update: [set: [status: "turn"]],
                               where: p.idx == 0 and p.match_id == ^match_id
          mod_first_player
          |> Repo.update_all([])

          mod_other_players = from p in Player,
                                update: [set: [status: "waiting"]],
                                where: p.idx > 0 and p.match_id == ^match_id
          mod_other_players
          |> Repo.update_all([])

          clean_move_timestamps = from m in Move,
                                    join: p in Player, on: m.player_id == p.id,
                                    update: [set: [updated_at: ^DateTime.utc_now]],
                                    where: p.idx == 0 and p.match_id == ^match_id
          clean_move_timestamps
          |> Repo.update_all([])
        end

        {:ok, match_idx, open}
      end)
    rescue err ->
      stacktrace = __STACKTRACE__
      case err do
        %Postgrex.Error{} ->
          if err.postgres.code == :serialization_failure || err.postgres.code == :deadlock_detected do
            IO.puts("retrying..")
            accept_match!(user_id, match_id)
          else
            IO.inspect(stacktrace)
            raise err
          end
        err ->
          IO.inspect(stacktrace)
          raise err
      end
    end
  end

  def clear_match!(match_id) do
    try do
      Repo.transaction(fn ->
        Repo.query!("set transaction isolation level repeatable read")

        clear_match_imp(match_id)
      end)
    rescue err ->
      stacktrace = __STACKTRACE__
      case err do
        %Postgrex.Error{} ->
          if err.postgres.code == :serialization_failure || err.postgres.code == :deadlock_detected do
            IO.puts("retrying..")
            clear_match!(match_id)
          else
            IO.inspect(stacktrace)
            raise err
          end
        err ->
          IO.inspect(stacktrace)
          raise err
      end
    end
  end

  defp clear_match_imp(match_id) do
    # check if match exists
    players_query = from p in Player,
                         select: p,
                         where: p.match_id == ^match_id
    players = players_query
              |> Repo.all()

    if length(players) == 0 do
      raise Codes.nonexistent
    end

    # check if match can even be cleared
    # match is started when both parties are on readying or higher
    if !(hd(players).status == "pending" || hd(players).status == "accepted") do
      raise Codes.moved_on
    end

    if abs(DateTime.diff(DateTime.utc_now, hd(players).inserted_at, :second)) < 30 do
      raise Codes.too_early
    end

    users = Enum.reduce(players, [], fn (cur, acc) ->
      # get the user_id and increment idx
      user_query = from u in User,
                        select: [u.id, u.next_idx],
                        where: u.id == ^cur.user_id,
                        limit: 1
      [[_, user_idx]] = user_query
                        |> Repo.all()

      inc_idx_query = from u in User,
                           update: [set: [next_idx: u.next_idx + 1]],
                           where: u.id == ^cur.user_id
      inc_idx_query
      |> Repo.update_all([])

      [{cur.user_id, user_idx} | acc]
    end)

    # delete match (players will be deleted too due to cascade delete)
    match_query = from m in Match,
                       select: m,
                       where: m.id == ^match_id
    match_query
    |> Repo.delete_all()

    {:ok, users, match_id}
  end

  def close_match!(match_id) do
    try do
      Repo.transaction(fn ->
        Repo.query!("set transaction isolation level repeatable read")

        close_match_imp(match_id)
      end)
    rescue err ->
      stacktrace = __STACKTRACE__
      case err do
        %Postgrex.Error{} ->
          if err.postgres.code == :serialization_failure || err.postgres.code == :deadlock_detected do
            IO.puts("retrying..")
            close_match!(match_id)
          else
            IO.inspect(stacktrace)
            raise err
          end
        err ->
          IO.inspect(stacktrace)
          raise err
      end
    end
  end

  defp close_match_imp(match_id) do
    # check players and existence
    players_query = from p in Player,
                      select: p,
                      where: p.match_id == ^match_id
    players = players_query
              |> Repo.all()

    if length(players) == 0 do
      raise Codes.nonexistent
    end

    if hd(players).status == "won" || hd(players).status == "tied" || hd(players).status == "lost" do
      raise Codes.moved_on
    end

    if !(hd(players).status == "turn" || hd(players).status == "waiting") do
      raise "match didn't even start yet"
    end

    # get original match
    match_query = from m in Match,
                    select: [m.id, m.next_idx],
                    where: m.id == ^match_id
    [[_, match_idx]] = match_query
                       |> Repo.all()

    # lock session
    inc_idx_query = from m in Match,
                      update: [set: [next_idx: m.next_idx + 1]],
                      where: m.id == ^match_id
    inc_idx_query
    |> Repo.update_all([])

    moves_query = from m in Move,
                    join: p in Player, on: m.player_id == p.id,
                    select: m,
                    where: p.match_id == ^match_id, # could use distinct
                    order_by: [asc: m.idx]
    moves = moves_query
            |> Repo.all()

    # get pieces (last idx)
    pieces_query =
"(select distinct on (moves.piece_id) moves.row, moves.col, pieces.id, pieces.type from moves
join pieces on moves.piece_id = pieces.id
where pieces.match_id = '#{match_id}'
order by moves.piece_id, moves.idx desc)
intersect
(select distinct on (moves.row, moves.col) moves.row, moves.col, pieces.id, pieces.type from moves
join pieces on moves.piece_id = pieces.id
where pieces.match_id = '#{match_id}'
order by moves.row, moves.col, moves.idx desc)
"
    pieces = pieces_query
             |> Repo.query!

    pieces = Enum.map(pieces.rows, fn ([row, col, id, type]) ->
      id = Ecto.UUID.cast!(id)
      %{
        row: row,
        col: col,
        id: id,
        type: type,
      }
    end)

    {kings_cnt, kings_ids} = Enum.reduce(pieces, {0, []}, fn (cur, {cnt, ids}) ->
      if cur.type == "king" do
        {cnt + 1, [cur.id | ids]}
      else
        {cnt, ids}
      end
    end)

    # ret style:
    {loser, close, players} = if kings_cnt < 2 do
      # one king left
      remaining_king_id = hd kings_ids

      # grab player that owns remaining king_id
      move_query = from m in Move,
                     join: p in Piece, on: m.piece_id == p.id,
                     select: [m, p],
                     where: m.piece_id == ^remaining_king_id and p.match_id == ^match_id,
                     limit: 1
      [[move, _]] = move_query
                    |> Repo.all()

      winning_player_id = move.player_id

      losing_player_id = Enum.reduce(players, nil, fn (cur, acc) ->
        if cur.id != winning_player_id do
          cur.id
        else
          acc
        end
      end)

      players = Enum.reduce(players, %{}, fn (cur, acc) ->
        acc
        |> Map.put(cur.user_id, %{id: cur.id})
      end)

      {losing_player_id, true, players}
    else
      # check if match can even be closed
      # a match can only be closed when one total used time is 10 minutes or more
      players = Enum.reduce(players, %{}, fn (cur, acc) ->
        player_id = cur.id

        # aggregate the moves
        {_, time_spent} = Enum.reduce(moves, {0, 0}, fn (cur, {last_timestamp, time_spent}) ->
          if cur.idx == -1 || cur.player_id != player_id do
            {cur.updated_at, time_spent}
          else
            {cur.updated_at, time_spent + abs(DateTime.diff(cur.updated_at, last_timestamp, :microsecond))}
          end
        end)

        # get last turn timestamp
        running = if cur.status == "turn" do
          # get last move
          last_move_query = from m in Move,
                                 join: p in Player, on: m.player_id == p.id,
                                 select: m.updated_at,
                                 where: p.match_id == ^match_id,
                                 order_by: [desc: m.idx],
                                 limit: 1
          [last_move_timestamp] = last_move_query
                                  |> Repo.all()

          last_move_timestamp
        else
          false
        end

        entry = %{
          id: player_id,
          time_spent: time_spent,
          running: running,
          real_time_spent: time_spent + (if running, do: abs(DateTime.diff(DateTime.utc_now, running, :microsecond)), else: 0),
        }

        acc
        |> Map.put(cur.user_id, entry)
      end)

      IO.inspect(players)

      # {nil, _, false} -> too early to decide
      # {nil, _, true} -> tied
      # {player_id, _, true} -> player with id player_id lost, and the other won
      {loser, _, close} = Enum.reduce(players, {nil, nil, false}, fn ({key, val}, {loser, real_time_spent, close}) ->
        if div(val.real_time_spent, 60_000_000) >= 10 do
          cond do
            loser === nil || val.real_time_spent > real_time_spent ->
              {val.id, val.real_time_spent, true}
            div(abs(val.real_time_spent - real_time_spent), 1_000_000) < 1 ->
              # subsecond gets spared, players are tied
              {nil, nil, true}
            true ->
              {loser, real_time_spent, close}
          end
        else
          {loser, real_time_spent, close}
        end
      end)

      {loser, close, players}
    end

    if close do
      if loser === nil do
        set_tied_query = from p in Player,
                           update: [set: [status: "tied"]],
                           where: p.match_id == ^match_id
        set_tied_query
        |> Repo.update_all([])

        [player1_user_id, player2_user_id] = Enum.map(players, fn ({key, val}) ->
          key
        end)

        # calculate elo delta
        player1_num_wins_query = from p in Player,
                                    select: count(p),
                                    where: p.user_id == ^player1_user_id and p.status == "won"
        player1_num_wins = player1_num_wins_query
                         |> Repo.all()

        player1_num_wins = if length(player1_num_wins) == 0, do: 0, else: hd player1_num_wins

        player2_num_wins_query = from p in Player,
                                     select: count(p),
                                     where: p.user_id == ^player2_user_id and p.status == "won"
        player2_num_wins = player2_num_wins_query
                          |> Repo.all()

        player2_num_wins = if length(player2_num_wins) == 0, do: 0, else: hd player2_num_wins

        # get elo for each user
        player1_matches_query = from p in Player,
                                   join: m in Match, on: p.match_id == m.id,
                                   select: [p.elo_delta],
                                   where: p.user_id == ^player1_user_id and m.closed,
                                   order_by: [asc: p.inserted_at]
        player1_matches = player1_matches_query
                        |> Repo.all()

        player1_elo = Enum.reduce(player1_matches, 1200, fn ([cur], acc) ->
          if cur != nil do
            acc + cur
          else
            acc
          end
        end)

        player2_matches_query = from p in Player,
                                    join: m in Match, on: p.match_id == m.id,
                                    select: [p.elo_delta],
                                    where: p.user_id == ^player2_user_id and m.closed,
                                    order_by: [asc: p.inserted_at]
        player2_matches = player2_matches_query
                         |> Repo.all()

        player2_elo = Enum.reduce(player2_matches, 1200, fn ([cur], acc) ->
          if cur != nil do
            acc + cur
          else
            acc
          end
        end)

        player1_prov = player1_num_wins < 10
        player2_prov = player2_num_wins < 10

        player1_k = if player1_prov || player1_prov == player2_prov do
          k_calc = cond do
            player1_elo < 2100 ->
              32
            player1_elo < 2400 ->
              24
            true ->
              16
          end
          max(800 / (player1_num_wins + 1), k_calc)
        else
          0
        end

        player2_k = if player2_prov || player2_prov == player1_prov do
          k_calc = cond do
            player2_elo < 2100 ->
              32
            player2_elo < 2400 ->
              24
            true ->
              16
          end
          max(800 / (player2_num_wins + 1), k_calc)
        else
          0
        end

        percent_transferred = 1 - 1 / (1 + :math.pow(10, ((player1_elo - player2_elo) / 400))) - 0.5 # tied

        IO.puts("player1's k: #{player1_k}")
        IO.puts("player2's k: #{player2_k}")
        IO.puts("percent transferred: #{percent_transferred}")

        player1_elo_delta = -round(player1_k * percent_transferred)
        player2_elo_delta = round(player2_k * percent_transferred)

        player1_elo_delta = if player1_elo + player1_elo_delta < 100, do: player1_elo - 100, else: player1_elo_delta
        player2_elo_delta = if player2_elo + player2_elo_delta < 100, do: player2_elo - 100, else: player2_elo_delta

        # set elo deltas
        set_player1_elo_delta_query = from p in Player,
                                         update: [set: [elo_delta: ^player1_elo_delta]],
                                         where: p.user_id == ^player1_user_id and p.match_id == ^match_id
        set_player1_elo_delta_query
        |> Repo.update_all([])

        set_player2_elo_delta_query = from p in Player,
                                          update: [set: [elo_delta: ^player2_elo_delta]],
                                          where: p.user_id == ^player2_user_id and p.match_id == ^match_id
        set_player2_elo_delta_query
        |> Repo.update_all([])
      else
        # at least one of them are overtime
        # so the winner is the one with less time elapsed
        set_loser_query = from p in Player,
                            update: [set: [status: "lost"]],
                            where: p.id == ^loser and p.match_id == ^match_id
        set_loser_query
        |> Repo.update_all([])

        # increment wins first, then set elo
        set_winner_query = from p in Player,
                             update: [set: [status: "won"]],
                             where: p.id != ^loser and p.match_id == ^match_id
        set_winner_query
        |> Repo.update_all([])

        IO.inspect(players)
        loser_user_id = Enum.reduce(players, nil, fn ({key, val}, acc) ->
          IO.inspect(val)
          if val.id == loser do
            key
          else
            acc
          end
        end)

        winner_user_id = Enum.reduce(players, nil, fn ({key, val}, acc) ->
          if val.id != loser do
            key
          else
            acc
          end
        end)

        # calculate elo delta
        loser_num_wins_query = from p in Player,
                                 select: count(p),
                                 where: p.user_id == ^loser_user_id and p.status == "won"
        loser_num_wins = loser_num_wins_query
                         |> Repo.all()

        loser_num_wins = if length(loser_num_wins) == 0, do: 0, else: hd loser_num_wins

        winner_num_wins_query = from p in Player,
                                  select: count(p),
                                  where: p.user_id == ^winner_user_id and p.status == "won"
        winner_num_wins = winner_num_wins_query
                          |> Repo.all()

        winner_num_wins = if length(winner_num_wins) == 0, do: 0, else: hd winner_num_wins

        # get elo for each user
        loser_matches_query = from p in Player,
                                join: m in Match, on: p.match_id == m.id,
                                select: [p.elo_delta],
                                where: p.user_id == ^loser_user_id and m.closed,
                                order_by: [asc: p.inserted_at]
        loser_matches = loser_matches_query
                        |> Repo.all()

        loser_elo = Enum.reduce(loser_matches, 1200, fn ([cur], acc) ->
          if cur != nil do
            acc + cur
          else
            acc
          end
        end)

        winner_matches_query = from p in Player,
                                 join: m in Match, on: p.match_id == m.id,
                                 select: [p.elo_delta],
                                 where: p.user_id == ^winner_user_id and m.closed,
                                 order_by: [asc: p.inserted_at]
        winner_matches = winner_matches_query
                         |> Repo.all()

        winner_elo = Enum.reduce(winner_matches, 1200, fn ([cur], acc) ->
          if cur != nil do
            acc + cur
          else
            acc
          end
        end)

        loser_prov = loser_num_wins < 10
        winner_prov = winner_num_wins < 10

        loser_k = if loser_prov || loser_prov == winner_prov do
          k_calc = cond do
            loser_elo < 2100 ->
              32
            loser_elo < 2400 ->
              24
            true ->
              16
          end
          max(800 / (loser_num_wins + 1), k_calc)
        else
          0
        end

        winner_k = if winner_prov || winner_prov == loser_prov do
          k_calc = cond do
            winner_elo < 2100 ->
              32
            winner_elo < 2400 ->
              24
            true ->
              16
          end
          max(800 / winner_num_wins, k_calc)
        else
          0
        end

        percent_transferred = 1 - 1 / (1 + :math.pow(10, ((loser_elo - winner_elo) / 400)))

        IO.puts("loser's k: #{loser_k}")
        IO.puts("winner's k: #{winner_k}")
        IO.puts("percent transferred: #{percent_transferred}")

        loser_elo_delta = -round(loser_k * percent_transferred)
        winner_elo_delta = round(winner_k * percent_transferred)

        loser_elo_delta = if loser_elo + loser_elo_delta < 100, do: loser_elo - 100, else: loser_elo_delta
        winner_elo_delta = if winner_elo + winner_elo_delta < 100, do: winner_elo - 100, else: winner_elo_delta

        # set elo deltas
        set_loser_elo_delta_query = from p in Player,
                                      update: [set: [elo_delta: ^loser_elo_delta]],
                                      where: p.id == ^loser and p.match_id == ^match_id
        set_loser_elo_delta_query
        |> Repo.update_all([])

        set_winner_elo_delta_query = from p in Player,
                                       update: [set: [elo_delta: ^winner_elo_delta]],
                                       where: p.id != ^loser and p.match_id == ^match_id
        set_winner_elo_delta_query
        |> Repo.update_all([])
      end

      # get all players yet again ...
      players_query = from p in Player,
                           select: p,
                           where: p.match_id == ^match_id
      players = players_query
                |> Repo.all()

      users = Enum.reduce(players, [], fn (cur, acc) ->
        # get the user_id and increment idx
        user_query = from u in User,
                          select: [u.id, u.next_idx],
                          where: u.id == ^cur.user_id,
                          limit: 1
        [[_, user_idx]] = user_query
                          |> Repo.all()

        inc_idx_query = from u in User,
                             update: [set: [next_idx: u.next_idx + 1]],
                             where: u.id == ^cur.user_id
        inc_idx_query
        |> Repo.update_all([])

        [{cur.user_id, user_idx} | acc]
      end)

      # close the match
      close_match_query = from m in Match,
                               update: [set: [closed: true]],
                               where: m.id == ^match_id
      close_match_query
      |> Repo.update_all([])

      {:ok, match_idx, users}
    else
      raise Codes.too_early
    end
  end
end
