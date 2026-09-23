%% @doc Who is calling, as mcl-git records it.
%%
%% macula merges the wire-authenticated caller into a map payload as its
%% 32-byte node key id, overwriting any `caller' the payload itself carried,
%% so it cannot be spoofed. mcl-git keeps it as lowercase hex: that is the
%% form in events, in the read model and in replies. Anything else (no
%% caller, not a map, not a key id) is no identity at all.
-module(repo_caller).

-export([id/1]).

-spec id(term()) -> binary() | undefined.
id(Payload) when is_map(Payload) -> hex(mcl_om_wire:caller(Payload));
id(_NotAMap)                     -> undefined.

hex(<<_:256>> = KeyId) -> binary:encode_hex(KeyId, lowercase);
hex(_Other)            -> undefined.
