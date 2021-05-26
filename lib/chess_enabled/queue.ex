defmodule ChessEnabled.Queue do
  import Ecto.Query, warn: false
  alias ChessEnabled.Repo

  alias ChessEnabled.Accounts.User
  alias ChessEnabled.Queue.Person
  alias ChessEnabled.Queue.CC, as: QueueCC
  alias ChessEnabled.Players.Player
  alias ChessEnabled.Matches.Match
  alias ChessEnabled.Pieces.Piece
  alias ChessEnabled.Moves.Move

  def list_queued(user_id) do
    Repo.transaction(fn ->
      Repo.query!("set transaction isolation level repeatable read")

      list_query = from p in Person,
                        select: p,
                        where: p.user_id == ^user_id
      list = list_query
             |> Repo.all()

      user_query = from u in User,
                        select: [u.id, u.next_idx],
                        where: u.id == ^user_id,
                        limit: 1
      [[_, next_idx]] = user_query
                        |> Repo.all()

      proc = Enum.reduce(list, [], fn (cur, acc) ->
        next = %{
          type: cur.type,
        }
        [next | acc]
      end)

      {:ok, next_idx - 1, proc}
    end)
  end

  def join_queue!(user_id, type) do
    try do
      Repo.transaction(fn ->
        Repo.query!("set transaction isolation level repeatable read")

        # queue cc
        queue_cc_query = from c in QueueCC,
                           update: [set: [next_idx: c.next_idx + 1]],
                           where: c.type == ^type
        queue_cc_query
        |> Repo.update_all([])

        # get original user
        user_query = from u in User,
                       select: [u.id, u.next_idx],
                       where: u.id == ^user_id,
                       limit: 1
        [[_, user_idx]] = user_query
                          |> Repo.all()

        # lock session
        inc_idx_query = from u in User,
                          update: [set: [next_idx: u.next_idx + 1]],
                          where: u.id == ^user_id
        inc_idx_query
        |> Repo.update_all([])

        # check if valid game + set take amount
        take = case type do
          "chess" ->
            2
          _ ->
            raise "game type not supported"
        end

        # check if user is already queued
        # (not relying on unique index here bc in future can queue for multiple games)
        queued_query = from p in Person,
                         select: count(p.user_id),
                         where: p.user_id == ^user_id,
                         group_by: p.user_id
        queued = queued_query
                 |> Repo.all()

        if length(queued) > 0 && hd(queued) > 0 do
          raise "already queued"
        end

        # check if user is already in a match
        active_matches_query = from p in Player,
                                 select: count(p.user_id),
                                 join: m in Match, on: p.match_id == m.id and not m.closed,
                                 where: p.user_id == ^user_id
        active_matches = active_matches_query
                         |> Repo.all()

        if length(active_matches) > 0 && hd(active_matches) > 0 do
          raise "already in a match"
        end

        # now insert new person
        %Person {
          type: type,
          user_id: user_id,
        }
        |> Repo.insert!

        # see if we can make a match
        matched_query = from p in Person,
                          select: p,
                          where: p.type == ^type,
                          order_by: [asc: p.updated_at],
                          limit: ^take
        matched = matched_query
        |> Repo.all()

        if length(matched) == 2 do
          matched
          |> Enum.each(fn (cur) ->
            cur
            |> Repo.delete!
          end)

          match = %Match {
            type: type,
            closed: false,
            next_idx: 0,
          }
          |> Repo.insert!


          {_, users} = Enum.reduce(matched, {0, []}, fn (cur, {idx, acc}) ->
            user_idx = if cur.user_id != user_id do
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

              user_idx
            else
              user_idx
            end

            player = %Player {
              idx: idx,
              status: "pending", # pending, accepted, readying, turn, waiting, won, lost, tied
              elo_delta: nil,
              user_id: cur.user_id,
              match_id: match.id,
              inserted_at: match.inserted_at, # important to keep this the same
              updated_at: match.inserted_at,
            }
            |> Repo.insert!

            case type do
              "chess" ->
                uuids = {
                  UUID.uuid4, UUID.uuid4, UUID.uuid4, UUID.uuid4,
                  UUID.uuid4, UUID.uuid4, UUID.uuid4, UUID.uuid4,
                  UUID.uuid4, UUID.uuid4, UUID.uuid4, UUID.uuid4,
                  UUID.uuid4, UUID.uuid4, UUID.uuid4, UUID.uuid4,
                  UUID.uuid4, UUID.uuid4, UUID.uuid4, UUID.uuid4,
                  UUID.uuid4, UUID.uuid4, UUID.uuid4, UUID.uuid4,
                  UUID.uuid4, UUID.uuid4, UUID.uuid4, UUID.uuid4,
                  UUID.uuid4, UUID.uuid4, UUID.uuid4, UUID.uuid4,
                }

                Piece
                |> Repo.insert_all([
                  %{id: elem(uuids, 0),  type: "pawn",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 1),  type: "pawn",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 2),  type: "pawn",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 3),  type: "pawn",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 4),  type: "pawn",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 5),  type: "pawn",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 6),  type: "pawn",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 7),  type: "pawn",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 8),  type: "rook",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 9),  type: "knight", match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 10), type: "bishop", match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 11), type: "queen",  match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 12), type: "king",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 13), type: "bishop", match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 14), type: "knight", match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                  %{id: elem(uuids, 15), type: "rook",   match_id: match.id, inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                ])

                case idx do
                  0 ->
                    Move
                    |> Repo.insert_all([
                      %{idx: -1, row: 6, col: 0, player_id: player.id, piece_id: elem(uuids, 0),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 6, col: 1, player_id: player.id, piece_id: elem(uuids, 1),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 6, col: 2, player_id: player.id, piece_id: elem(uuids, 2),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 6, col: 3, player_id: player.id, piece_id: elem(uuids, 3),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 6, col: 4, player_id: player.id, piece_id: elem(uuids, 4),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 6, col: 5, player_id: player.id, piece_id: elem(uuids, 5),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 6, col: 6, player_id: player.id, piece_id: elem(uuids, 6),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 6, col: 7, player_id: player.id, piece_id: elem(uuids, 7),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 7, col: 0, player_id: player.id, piece_id: elem(uuids, 8),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 7, col: 1, player_id: player.id, piece_id: elem(uuids, 9),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 7, col: 2, player_id: player.id, piece_id: elem(uuids, 10), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 7, col: 3, player_id: player.id, piece_id: elem(uuids, 11), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 7, col: 4, player_id: player.id, piece_id: elem(uuids, 12), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 7, col: 5, player_id: player.id, piece_id: elem(uuids, 13), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 7, col: 6, player_id: player.id, piece_id: elem(uuids, 14), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 7, col: 7, player_id: player.id, piece_id: elem(uuids, 15), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                    ])
                  1 ->
                    Move
                    |> Repo.insert_all([
                      %{idx: -1, row: 1, col: 0, player_id: player.id, piece_id: elem(uuids, 0),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 1, col: 1, player_id: player.id, piece_id: elem(uuids, 1),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 1, col: 2, player_id: player.id, piece_id: elem(uuids, 2),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 1, col: 3, player_id: player.id, piece_id: elem(uuids, 3),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 1, col: 4, player_id: player.id, piece_id: elem(uuids, 4),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 1, col: 5, player_id: player.id, piece_id: elem(uuids, 5),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 1, col: 6, player_id: player.id, piece_id: elem(uuids, 6),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 1, col: 7, player_id: player.id, piece_id: elem(uuids, 7),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 0, col: 0, player_id: player.id, piece_id: elem(uuids, 8),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 0, col: 1, player_id: player.id, piece_id: elem(uuids, 9),  inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 0, col: 2, player_id: player.id, piece_id: elem(uuids, 10), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 0, col: 3, player_id: player.id, piece_id: elem(uuids, 11), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 0, col: 4, player_id: player.id, piece_id: elem(uuids, 12), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 0, col: 5, player_id: player.id, piece_id: elem(uuids, 13), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 0, col: 6, player_id: player.id, piece_id: elem(uuids, 14), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                      %{idx: -1, row: 0, col: 7, player_id: player.id, piece_id: elem(uuids, 15), inserted_at: DateTime.utc_now, updated_at: DateTime.utc_now},
                    ])
                end
            end

            {idx + 1, [{cur.user_id, user_idx} | acc]}
          end)

          match = %{
            type: type,
            closed: false,
            idx: match.next_idx - 1,
            status: "pending",
            elo_delta: nil,
            match_id: match.id,
            inserted_at: match.inserted_at,
          }

          {:ok, users, match}
        else
          {:ok, [user_idx], nil}
        end
      end)
    rescue err ->
      stacktrace = __STACKTRACE__
      case err do
        %Postgrex.Error{} ->
          if err.postgres.code == :serialization_failure || err.postgres.code == :deadlock_detected do
            IO.puts("retrying..")
            join_queue!(user_id, type)
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

  def leave_queue!(user_id, type) do
    try do
      Repo.transaction(fn ->
        Repo.query!("set transaction isolation level repeatable read")

        # get original user
        user_query = from u in User,
                          select: [u.id, u.next_idx],
                          where: u.id == ^user_id,
                          limit: 1
        [[_, user_idx]] = user_query
                          |> Repo.all()

        # lock session
        inc_idx_query = from u in User,
                             update: [set: [next_idx: u.next_idx + 1]],
                             where: u.id == ^user_id
        inc_idx_query
        |> Repo.update_all([])

        # check if user is not queued
        queued_query = from p in Person,
                         select: count(p.user_id),
                         where: p.user_id == ^user_id and p.type == ^type,
                         group_by: p.user_id
        queued = queued_query
                 |> Repo.all()

        if length(queued) == 0 do
          raise "not queued"
        end

        # delete person
        unqueue_query = from p in Person,
                          select: p,
                          where: p.user_id == ^user_id and p.type == ^type
        unqueue_query
        |> Repo.delete_all()

        {:ok, [user_idx]}
      end)
    rescue err ->
      stacktrace = __STACKTRACE__
      case err do
        %Postgrex.Error{} ->
          if err.postgres.code == :serialization_failure || err.postgres.code == :deadlock_detected do
            IO.puts("retrying..")
            leave_queue!(user_id, type)
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
end
