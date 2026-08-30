-module(chama_auth).

-export([hash_password/1, verify_password/2]).

%% Simple salted SHA-256 hashing. Good enough to avoid storing plaintext
%% passwords for this small internal tool; swap for bcrypt/argon2 (e.g.
%% via the `erlpass` or `bcrypt` hex packages) before any real deployment.
-define(SALT, <<"chama-static-salt-v1">>).

hash_password(Plain) when is_binary(Plain) ->
    Hash = crypto:hash(sha256, <<?SALT/binary, Plain/binary>>),
    binary:encode_hex(Hash).

verify_password(Plain, StoredHash) when is_binary(Plain), is_binary(StoredHash) ->
    hash_password(Plain) =:= StoredHash.
