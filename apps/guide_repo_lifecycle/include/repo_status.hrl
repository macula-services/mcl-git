%% Bit flags for the repo aggregate's status, manipulated with evoq_bit_flags.
%% Powers of two: each flag owns one bit.
-define(REPO_INITIATED, 1).   %% 2^0
-define(REPO_ARCHIVED,  2).   %% 2^1
-define(REPO_PUBLIC,    4).   %% 2^2  anyone in the realm may fetch
