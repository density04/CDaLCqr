# Simulation study: six estimators for penalised quantile regression

Core code for the simulation study in the paper.  Only the implementation of the
data-generating processes, the six estimators, the evaluation and the parameter
settings are kept here; the cluster scheduler used for the production run is not
part of the repository.

## Files

| File | Purpose |
|---|---|
| `scripts/fit_task.R` | One fit: generate one data set, run one of the six estimators, evaluate it and append one row to `results/worker_<id>.csv`. |
| `scripts/ma_baselines.R` | Adaptive-lasso (LP), MCP and SCAD (LLA) baselines of Ma, built on `quantreg::rq.fit.fnc`. |

Requirements: R (>= 3.5) with `quantreg` and `MASS`, plus `CDaLCqr` 0.1.0
(install the tarball in the repository root).

## Design

- `n = 75` subjects with 2 or 3 repeated observations each (`N` around 187--196),
  four unpenalised covariates `X = (1, X1, X2, time)` and `p` compositional
  predictors `Z = log(C)` derived from a softmax of correlated normals.
- Four data-generating processes:

  - **Setup I** -- homoscedastic errors;
  - **Setup II** -- subject-level random intercepts;
  - **Setup III** -- heteroscedastic errors whose scale depends on `|Z beta|`;
  - **Setup IV** -- heteroscedastic errors plus subject-level random effects.

  The six true signals are the same in all setups; the remaining coefficients
  are zero.
- `p in {500, 600, 700, 800, 900, 1000}`, `tau in {0.2, 0.5, 0.8}`, 100
  replications, so one estimator is evaluated in `4 x 3 x 6 x 100 = 7,200`
  settings (43,200 fits in total).
- Six estimators: `CDA_L` / `CDA_M` / `CDA_S` (this package: convex adaptive
  lasso, MCP, SCAD) and `MA_ALPqr` / `MA_M` / `MA_S` (adaptive lasso via LP,
  MCP / SCAD via LLA).
- Lambda is chosen by GIC on a fixed grid; the number of selected coefficients
  is counted with threshold `1e-5`.

## Parameter settings

| Quantity | Value |
|---|---|
| subjects (`NSUBJ` environment variable) | 75 |
| unpenalised covariates `r` | 4 |
| seed | `2026 + replication` |
| `eps` (CDA stopping tolerance) | `3e-6` |
| `maxit` | `300000` |
| `mu` (augmented Lagrangian) | 10 |
| `kk` (concave-penalty approximation) | 0.1 |
| `CDA_PILOT_SCALE` | 0.5 |
| convex lambda grid (CDA_L, MA_ALPqr) | 60 points, `exp(seq(log 1e-4, log 0.3))` |
| non-convex lambda grid (CDA_M, CDA_S, MA_M, MA_S) | 30 points, `exp(log(N/5000) + (log(N/200) - log(N/5000)) * (1 - (1 - u)^2))`, `u` uniform on `[0, 1]` |
| GIC | `log(loss) + (size - 1) * log(p) * log(log(n)) / n` |
| selection threshold | `1e-5` |

`CDA_PILOT_SCALE = 0.5` halves the pilot penalty of the CDA adaptive lasso,
which puts its initialisation on the same scale as the LP adaptive-lasso
baseline.

## Running one fit

Install the package tarball from the repository root, then run from the
repository root:

```bash
export CDA_LIB_DIR="$HOME/R/library"     # library holding CDaLCqr 0.1.0
Rscript simulation/scripts/fit_task.R \
  "$PWD" I 0.5 500 1 CDA_M "$CDA_LIB_DIR"
```

The argument order is `ROOT SETUP TAU P REPLICATION METHOD LIB_DIR [WORKER_ID]`.
`ROOT` is the repository root: the row is appended to
`ROOT/results/worker_<WORKER_ID>.csv`, and `ma_baselines.R` is sourced from
`ROOT/simulation/scripts/` for the MA estimators.  `CDA_LIB_DIR` is passed to
`.libPaths()` so a specific installed version of CDaLCqr can be selected; the
optional `CDA_R_LIBS` variable adds further library paths (separated by
`.Platform$path.sep`) when packages such as `quantreg` are installed elsewhere.
`NSUBJ` overrides the number of subjects.

## Running the full grid

The full study is a loop over the four dimensions, for example

```bash
ROOT=$PWD
LIB=${CDA_LIB_DIR:-$HOME/R/library}
for p in 500 600 700 800 900 1000; do
  for setup in I II III IV; do
    for tau in 0.2 0.5 0.8; do
      for rep in $(seq 1 100); do
        for method in CDA_L CDA_M CDA_S MA_ALPqr MA_M MA_S; do
          Rscript simulation/scripts/fit_task.R \
            "$ROOT" "$setup" "$tau" "$p" "$rep" "$method" "$LIB" adhoc
        done
      done
    done
  done
done
```

This is the same loop that was distributed over several machines for the paper;
each worker simply writes `results/worker_<id>.csv` with its own `id`, so the
files never overlap and can be merged afterwards.

## Output

One row per fit, 27 columns: setting `(setup, tau, p, replication, method)`,
`status`/`error`, `N`/`seed`, selected `lambda_best`, timings, the four AEE
measures, `SIZE`, `FP`, `FN`, `PCF` (exact recovery of the support and signs)
and convergence counters.  Failed fits are recorded with `status="failed"`
instead of being dropped, so completion rates can be reported per setting.
