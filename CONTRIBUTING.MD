# Contributing to DrevOps Pack

thanks for wanting to make this better.

## setup

you need docker. that's it.

```bash
# clone
git clone https://github.com/JovianOps/drevops-pack.git
cd drevops-pack

# build
docker build -t drevops-pack:dev .

# test
docker run --rm -v "$PWD:/work" drevops-pack:dev drevops doctor
```

## adding a tool

1. add an entry to `tools.json`:
```json
{
  "name": "my-tool",
  "kind": "composer-bin",
  "package": "drevops/my-tool",
  "version": "^1.0"
}
```

2. rebuild and test:
```bash
docker build -t drevops-pack:dev .
docker run --rm -v "$PWD:/work" drevops-pack:dev drevops my-tool --help
```

## tool kinds

| kind | what it does |
|------|-------------|
| `composer-bin` | exposes declared `bin` executables |
| `composer-scripts` | exposes executable scripts in `scripts_dir` (default: `src/`) |
| `composer-lib` | library only — no direct commands, but its classes are available to other tools |

## running tests

Dispatcher and host-wrapper tests (no Docker):

```bash
bash tests/run.sh
```

Image smoke tests:

1. `docker run --rm ... doctor` — all tools check out
2. `docker run --rm -v "$PWD:/work" ... <tool> <command>` — each command works

## submitting changes

1. fork it
2. `git checkout -b feat/your-thing`
3. make your changes
4. rebuild and verify
5. `git commit -am 'add: your thing'`
6. open a PR

## issues

open an issue with:
- the tool/command you're trying to use
- what you expected vs what happened
- your docker/podman version
