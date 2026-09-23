# mcl-git

**Git over the mesh.** `git clone mesh://io.macula/<repo_id>` clones a repository
held by an mcl-git node, and `git push` pushes back to it, with no forge and no DNS
in between: the bytes travel through Macula stations on the post-quantum wire
(macula 12).

The server side is an mcl_om service. The client side is `git-remote-mesh`, a
git remote helper shipped in the same release and image.

## How it works

```
git clone mesh://io.macula/repo-…       mcl-git node
    │                                        │
git-remote-mesh ── macula call ──▶ station ──▶ mcl-git/upload_pack  → git upload-pack --stateless-rpc
 (your node id)                              mcl-git/receive_pack → git receive-pack --stateless-rpc
```

git itself runs on both ends. The helper sends git's own stateless-rpc requests
(protocol v2 `ls-refs` and `fetch` for reads, the classic `receive-pack` exchange
for pushes) as one mesh call each, and hands the answers back to git. On the
server, every repository is a bare repository on disk. Its dossier (who owns it,
its name, every push) is event-sourced in a reckon-db store.

## Procedures

All nine are registered under the org `mcl-git`, as `mcl-git/<name>`, in the realm
the node is admitted to. Text fields go out as CBOR text and git bytes as CBOR
bytes.

| Procedure | Payload | Who may |
|---|---|---|
| `initiate_repo` | `name`; optional `description`, `visibility` (`public`/`private`, default private), `default_branch` (default `main`), `tags` | an **initiator** (see below); the caller becomes the owner. Answers `repo_id`. |
| `rename_repo` | `repo_id`, `new_name` | the owner |
| `set_repo_description` | `repo_id`, `description` | the owner |
| `archive_repo` | `repo_id`, optional `reason` | the owner. This is final: the repo can still be read, but refuses every change. |
| `get_repo_by_id` | `repo_id` | anyone for a public repo, only the owner for a private one |
| `list_repos_by_owner` | `owner` (node id, hex) | the owner sees all of them; anyone else sees the public ones |
| `search_repos_by_tag` | `tag` | public repos, plus the caller's own private ones |
| `upload_pack` | `repo_id`, `stdin` (a v2 request) | anyone for a public repo, only the owner for a private one. Answers `stdout`. |
| `receive_pack` | `repo_id`, and `advertise` = 1 or `stdin` (the update and its pack) | the owner, never on an archived repo. Answers `stdout`. |

**Identity.** "The caller" is the node id macula authenticates on the wire and
merges into the payload. A `caller` or `owner` field that a payload carries itself
is ignored. A private repository answers `not_found` to everyone but its owner,
which is the same answer a missing repository gets.

**Initiators.** Every repository is a directory on the serving node's disk, so
`initiate_repo` fails closed. The caller's node id must be listed in
`MCL_GIT_INITIATORS`, and an empty list admits nobody.

**Pushes are announced.** After a push, `<realm>/mcl-git/git/repos/refs_advanced_v1`
carries `repo_id`, `pusher`, `advanced_at` and the `advances` (ref, old oid, new
oid). This fact is published by a process manager from the `refs_advanced_v1`
domain event; its shape is a public contract.

## Using it: git-remote-mesh

Put the release's `bin/` on `PATH` (the image already does this), then set the
environment the helper dials with:

```sh
export MACULA_STATION_SEEDS=station-fi-helsinki.macula.io      # host[:port],...
export MACULA_STATION_NODE_IDS=<64-hex node id of that station>  # index for index
export MCL_GIT_REALM_KEY=<hex of the realm's public signing key>

git clone mesh://io.macula/repo-0190…
git push origin main
```

The helper uses this machine's **one stored macula identity** (macula's
`node_identity_path`, `~/.local/share/macula/identity.key` by default). That node
id is who owns the repositories you initiate and who may push to them, so keep
it. A container that runs the helper needs that file on a volume.

## Running the service

`deploy/docker-compose.yml` lists everything the service reads: the realm tag,
name and key, the initiators, the pinned station seeds, and two volumes. One
volume holds the node identity. The other, `/data`, holds the event store with
the repositories beside it under `/data/repos`. `/health` is on port **8471**.
The realm must admit the node's org `mcl-git` before its procedures can be
called.

## Layout

| App | Department | What it does |
|---|---|---|
| `guide_repo_lifecycle` | CMD | the repo aggregate (owner rule, archive is final), the initiate, rename, set_repo_description, archive and advance_refs desks, the four lifecycle procedures, and the process manager that announces pushes |
| `project_repos` | PRJ | the repos read model, and `repo_access` (who may read or change a repo) |
| `query_repos` | QRY | the three lookups |
| `serve_git_over_mesh` | | bare repositories on disk, `upload_pack` and `receive_pack` |
| `git_wire` | | the git smart protocol as both ends speak it: pkt-line, v2 ls-refs and fetch, receive-pack, and running git without a shell |
| `git_remote_mesh` | | the remote helper (client), loaded in the release, run by `bin/git-remote-mesh` |
| `mcl_git` | | the mcl_om service: the nine procedures, the store, `/health` |

## Limits

- **One mesh frame per call, 16 MiB.** A fetch's pack must fit in one reply.
  A fetch names what the local repository already holds, so a fetch after
  the clone carries only the new objects, but the clone itself carries
  everything. The server stops git at 15 MiB and answers `pack_too_large`.
  A push whose commands and pack exceed a frame is refused by macula before
  it reaches the server. There is no streamed fetch or push yet.
- **25 s per git run.** macula 12's `macula_response` gives a handler 30 s,
  a fixed value, and after that tells the caller `temporary_relay_failure`
  while the handler keeps running. The server stops git at 25 s
  (`git_timeout`), so a caller always hears the real outcome.
- **At most 8 git processes per node.** Beyond that a call gets `busy`.
- **The owner may force-push and delete refs.** The server leaves
  `receive.denyNonFastForwards` and `receive.denyDeletes` at git's defaults.
  git's own fast-forward check on the client is the only guard.
- **Archiving during a push.** The server checks whether the repository is
  archived before and under the push lock. An archive that lands after that
  second check and before git finishes leaves the push on disk, unrecorded,
  and logs it as an error.
- **git on both ends.** The image carries git; a client already has it.

## Development

The gates are run inside the CI image, as root:

```sh
rebar3 lint
rebar3 as test eunit     # real git, a real reckon-db store; no mesh
rebar3 dialyzer
```

`git_remote_mesh_tests` runs real `git clone`, `git push` and `git pull` through
the helper, over a loopback transport. `mcl_git_store_tests` runs the lifecycle
and a push on a real store.

## Provenance

Recuperated from hecate-daemon's git-over-mesh apps (`serve_git_over_mesh`,
`guide_repo_lifecycle`, `project_repos`, `query_repos`, `announce_ref_updates`),
where `git clone mesh://` was verified end to end on one machine on 2026-04-21
(hecate-daemon `072220a`). It has been rebuilt on mcl_om and macula 12, with
three changes:

- Procedures are org-namespaced, and every id travels in the payload.
- The owner is the wire-authenticated caller.
- The ref updates come from diffing refs around `receive-pack`, where they used
  to come from a post-receive hook socket.

## License

Apache-2.0.
