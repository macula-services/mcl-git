# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

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
