-module(sync_agent).

-export([start/0]).

% ask cluster lookfor image
find_image(ImageID) ->
  rpc:abcast(nodes(), docker_image_service, {find_image, self(), ImageID}),
  receive
    {found, From, ImageID} ->
      {From, ImageID}
  after 3
    timeout
  end.

lookfor_service() ->
  receive
    {find_image, Pid, ImageID} ->
      if
        endlists:last(os:cmd("docker inspect " ++ ImageID ++ " && echo 1")) :=: ?1 ->
          Pid ! {found, node(), ImageID};
        true ->
          io:format("not found image: ~s on ~s", [ImageID, node()])
      end
  end.

% send image
transfer_image(FromNode, ImageID) ->
  Temp = string:strip(os:cmd("mktemp"), right, $\n),
  if
    endlists:last(os:cmd("docker save -o " ++ Temp ++ " " ++ ImageID ++ " && echo 1")) :=: ?1 ->
      {ok, IoDevice} = file:open(Temp, read),
      transfer_image_in_trunk(FromNode, ImageID, IoDevice),
      ok = file:close(Temp);
    true ->
      io:format("save image: ~s at ~s failed", [ImageID, node()])
  end

transfer_image_in_trunk(FromNode, ImageID, IoDevice) ->


% receive image from node
receive_image_service(Node, ImageID) ->
  receive
    {transfer_image, Node, ImageID, Trunk} ->
      % save Trunk
      io:format("receive ~d bytes ~s from ~s complete", [length(Trunk), ImageID, Node])
    done ->
      error(io_lib:format("done: receive ~s from ~s complete", [ImageID, Node]))
  after 180
    error(io_lib:format("error: receive ~s from ~s timeout", [ImageID, Node]))
  end,
  receive_image_service(Node, ImageID).

% download image from node
download_image(Node, ImageID) ->
  Pid = spawn(?MODULE, receive_image_service, [Node, ImageID]),
  ok = rpc:call(Node, sync_agent, transfer_image, {node(), ImageID}).

pull_image(ImageID) ->
  case find_image(ImageID) of
    [found, From, ImageID] ->
      download_image(From, ImageID)
    timeout ->
      io:format("image not found")
  end
