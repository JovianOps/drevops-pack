# DrevOps Pack

**One Docker image. Every DrevOps tool. No local PHP/Composer setup.**

A single container that bundles all [drevops](https://github.com/orgs/drevops) tools behind a unified `drevops` command. Just build, run, and go.

## what this is

instead of installing 7+ drevops packages individually (with all their composer dependencies), this repo builds one Docker image with everything bundled. The `drevops` dispatcher command routes to whichever tool you need.

## quick start

```bash
# build the image
docker build -t drevops-pack .

# use it — works from any directory
docker run --rm -it -v "$PWD:/work" drevops-pack drevops list
docker run --rm -it -v "$PWD:/work" drevops-pack drevops vortex-tooling ci
```

## the drevops command

once inside the container (or if you copy the binary out), the dispatcher works like:

```
drevops <command>              # run a command if the name is unique
drevops <tool> <command>       # run a command from a specific tool
drevops <tool>/<command>       # single-token form
drevops list                   # show bundled tools and commands
drevops doctor                 # verify the bundle is healthy
drevops version                # show bundled tool versions
drevops help                   # show usage
```

example:
```
$ drevops list
TOOL                 VERSION  KIND             STATUS
vortex-tooling       1.1.3    composer-scripts ok
eddy-tooling        1.0.5    composer-bin      ok
behat-steps         *        composer-lib      ok
str2name             *        composer-bin      unavailable
...

  TOOL                  COMMAND
  vortex-tooling        ci
  vortex-tooling        coverage
  eddy-tooling          eddy
  behat-steps           behat
```

## host-side wrapper

`src/drevops.sh` is a thin wrapper for host usage — it runs the container with your working directory mounted, forwarding env vars if you want:

```bash
# symlink it so it's on your PATH
ln -s /path/to/this/repo/src/drevops.sh /usr/local/bin/drevops
drevops status   # runs inside the container against your project
```

env vars:
- `DREVOPS_IMAGE` — image to use (default: `drevops-pack:latest`)
- `DREVOPS_DOCKER=1` — also mount the Docker socket (for tools that call docker)
- `DREVOPS_ENV_PASSTHROUGH` — space-separated env var names to forward into the container

## what's bundled

see [`tools.json`](tools.json) for the full list. each entry is a composer package from the `drevops/*` org:

| tool | kind | description |
|------|------|-------------|
| vortex-tooling | composer-scripts | main CI/dev scripts |
| eddy-tooling | composer-bin | standalone binary tools |
| behat-steps | composer-lib | behat step definitions |
| behat-screenshot | composer-lib | behat screenshot extension |
| str2name | composer-bin | string-to-name converter (optional) |
| shellvar | composer-bin | shell variable helper (optional) |
| customizer | composer-lib | theme customizer (optional) |
| drupal-helpers | composer-lib | drupal helpers (optional) |

optional tools are skipped if they fail to install — required tools will fail the build.

## how it works

**`build/install-tools.sh`** — reads `tools.json`, runs `composer require` for each tool in an isolated prefix, discovers executables via `composer.json` bin declarations or shebang scripts, and writes two manifest files:
- `commands.tsv` — maps `tool → command → executable path`
- `tools.tsv` — tracks `name → version → kind → package → status`

**`image/drevops`** — a bash dispatcher that reads those manifests and routes commands.

**Dockerfile** — multi-stage: PHP 8.3 build stage installs everything via `install-tools.sh`, runtime stage copies the bundle + `drevops` binary.

## development

```bash
# build locally
docker build -t drevops-pack:dev .

# test the dispatcher
docker run --rm -v "$PWD:/work" drevops-pack:dev drevops doctor

# update bundled tools
# edit tools.json, then rebuild
```

## license

MIT — see [LICENSE](LICENSE)
