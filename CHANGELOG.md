# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Changed

- macula `>= 12.2.1`: a procedure's own refusal (`not_owner`, `not_found`,
  `not_an_initiator`, ...) reaches the caller as `handler_error` with its
  reason (macula#28); under 12.2.0 it arrived as `unknown_error`.
- mcl_om `~> 0.28`, macula `~> 12.2`. `upload_pack` and `receive_pack` declare
  `handler_timeout_ms` 300000, so a git run may take 270 s (was 25 s, under
  macula's fixed 30 s). The helper waits 330 s.
- The push announcement is published through `mcl_om_pubsub`, whose watcher
  keeps a failed announcement from taking the process manager down with it.
- mcl_om `~> 0.27`, which has no barrel_docdb and so no rocksdb. The image and CI
  no longer install rocksdb's build or runtime packages.
- The boot claim carries `MCL_SERVICE_NAME` (`mcl-git`, set in the image) and
  `MCL_BOX` (required by the compose file), so the realm's Providers desk shows
  which host asks.

### Added

- `git mesh` (bin/git-mesh). `git mesh whoami` prints this machine's node id.
  `git mesh init <name>` initiates a repository as that node and prints its
  `mesh://` URL. The README walks from zero to `git clone mesh://`.
- Git over the mesh on macula 12, recuperated from hecate-daemon's
  git-over-mesh apps.
- Nine procedures under `mcl-git`: `initiate_repo`, `rename_repo`,
  `set_repo_description` and `archive_repo`; the lookups `get_repo_by_id`,
  `list_repos_by_owner` and `search_repos_by_tag`; and the git procedures
  `upload_pack` (protocol v2 ls-refs and fetch) and `receive_pack`.
- Ownership by the wire-authenticated caller. Only the owner may change or push
  to a repository, and a private repository is invisible to everyone else.
  `initiate_repo` is fail-closed behind `MCL_GIT_INITIATORS`.
- The `refs_advanced_v1` domain event on every push, announced on the mesh as
  `<realm>/mcl-git/git/repos/refs_advanced_v1`.
- `git-remote-mesh`, the git remote helper (clone, fetch, push), shipped in the
  release as `bin/git-remote-mesh`.
