# kittylitter

Distribution wrapper for the [OMP-enabled Alleycat fork](https://github.com/johannhipp/alleycat/tree/omp-support). Ships the daemon to npm, Homebrew, and the platform installer scripts under the kittylitter brand.

The wrapper itself is a 3-line `main()` that re-exports `alleycat::run("kittylitter")`. All daemon behavior lives in the alleycat crate; this crate exists so cargo-dist sees a `kittylitter` package name and produces correctly-named artifacts (`kittylitter-installer.sh`, `kittylitter.rb`, `kittylitter` on npm).

## Cutting a release

1. Push the OMP bridge changes to `johannhipp/alleycat` on `omp-support` (or upstream the same changes).
2. Keep the `alleycat` dependency on `branch = "omp-support"` and refresh it with `./tools/scripts/update-alleycat-main.sh --kittylitter`.
3. Bump `version` in this crate's `Cargo.toml` and the version of the kittylitter binary tracking it.
4. Tag `vX.Y.Z` on the litter repo. The `release.yml` workflow at the repo root builds and publishes.
