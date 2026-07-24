# `docker/` — turbo-stack CI container

`Dockerfile.turbo-ci` builds the CI base image for the **CMake build system**
(the spack flavor). It bakes the repo's own Spack environment — `spack/spack.yaml`,
env name `turbo_stack` — so CI does not recompile the dependency stack (cmake,
ninja, gmake, OpenMPI, netcdf-fortran, pFUnit, AMReX) on every run.

Rebuilding that stack from source takes ~1 hour. Reusing a prebuilt image, a
turbo-stack build + full pFUnit suite for one backend takes ~8–9 minutes.

```
ghcr.io/turbo-esm/turbo-stack/turbo-ci:gcc-openmpi
```

| Tag | Meaning |
|---|---|
| `gcc-openmpi` | **Mutable** — what CI consumes. Published only from `main` |
| `gcc-openmpi-<short-sha>` | Immutable — always published; pin this to reproduce or bisect an image regression |
| `buildcache` | BuildKit layer cache, not a runnable image |

## The two workflows

| Workflow | Role |
|---|---|
| `.github/workflows/build-turbo-ci-container.yaml` | **Producer** — builds the image and pushes it to GHCR. Manual only (`workflow_dispatch`), so a merge never waits on a 1-hour build. |
| `.github/workflows/turbo-cmake-container-tests.yaml` | **Consumer** — runs `scripts/build_local_with_spack_env.sh --infra {TIM,FMS2} --tests` inside the image, on pushes to `main` and on PRs. |

This is additive to the legacy `build-tests.yaml` / `unit-tests.yaml`, which
exercise the **mkmf** `build.sh` path in the `ncarcisl/cisldev-*` containers.
Different build system, so the two do not overlap; retiring the legacy
workflows is a separate follow-up.

## Refreshing the image after a dependency change

Change `spack/spack.yaml` (or `spack/create_spack_environment.sh`, or
`Dockerfile.turbo-ci`), then run the producer — **Actions → Build turbo-stack CI
container → Run workflow**, or:

```bash
gh workflow run build-turbo-ci-container.yaml            # from main: refreshes gcc-openmpi
```

Nothing else picks the change up. The consumer always pulls the prebuilt
`gcc-openmpi` tag, so **a `spack.yaml` edit has no effect on CI until the image
is rebuilt** — that decoupling is deliberate (a merge shouldn't block on a 1-hour
build) but it is easy to forget.

To check that a recipe change even builds before you merge it, dispatch against
your branch — the run uses that branch's `Dockerfile.turbo-ci` and `spack.yaml`:

```bash
gh workflow run build-turbo-ci-container.yaml --ref my-branch
```

A branch run publishes only `gcc-openmpi-<sha>`, never the shared `gcc-openmpi`
tag, so it cannot hand the team an unvalidated image. To have CI actually *use*
that image, point the consumer's `container.image` at the sha tag temporarily.

## Pulling it locally

The package is **private** — TURBO-ESM policy does not allow public packages —
so an anonymous `docker pull` will fail. You need a one-time login with a
personal access token carrying the `read:packages` scope, and read access to
the package:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <your-github-username> --password-stdin
docker pull ghcr.io/turbo-esm/turbo-stack/turbo-ci:gcc-openmpi
```

If the pull 404s or reports `denied`, your account is probably missing package
access — ask a TURBO-ESM owner to add you under the package's **Manage access**.

## Building it locally

The build context is the repo root, so `spack/` is available to `COPY`. Only
`spack/` is used — `.dockerignore` keeps `submodules/` and `.git` out, so the
context stays small even in an initialized checkout.

```bash
docker buildx build -f docker/Dockerfile.turbo-ci -t turbo-ci:gcc-openmpi .
```

Overridable build args: `BASE_IMAGE` (default `ubuntu:24.04`) and `SPACK_REF`
(default `v1.2.2`, pinned for reproducibility).

## Running the CI build locally

The image sets `SPACK_ROOT` but deliberately does **not** activate the Spack
environment — the repo scripts own activation. Reproducing what CI does, against
a checkout whose submodules are already initialized:

```bash
docker run --rm -it -v "$PWD:/work" -w /work \
    turbo-ci:gcc-openmpi \
    bash -lc 'git config --global --add safe.directory "*" \
              && scripts/build_local_with_spack_env.sh --infra TIM --tests'
```

Two caveats:

- **Build artifacts land in your checkout owned by root**, since the container
  runs as root against a bind mount. Pass `--build_dir` to keep them somewhere
  disposable, or clean up afterwards.
- **MPI oversubscription.** The pFUnit suites run `mpirun -np 4`
  (`@test(npes=[1,2,4])`). On a machine with fewer than 4 slots, OpenMPI 5's
  PRRTE refuses to launch with "not enough slots"; export
  `PRTE_MCA_rmaps_default_mapping_policy=":oversubscribe"` (what the consumer
  workflow does). Running as root is already handled — the image sets
  `OMPI_ALLOW_RUN_AS_ROOT{,_CONFIRM}`, which OpenMPI 5 otherwise blocks.
