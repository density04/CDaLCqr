# Simulation study: six estimators for penalised quantile regression

This folder contains the code used for the simulation study (100 replications,
72 settings).  Only code is included here; the generated result files are not
committed to the repository.

## Files

| File | Purpose |
|---|---|
| `scripts/grid6_task_n75.R` | One task: generate the data, fit one of the six methods, evaluate it and append one row to `results/worker_<id>.csv`. |
| `scripts/ma_lla.R` | Local linear approximation (LLA) implementation for the MA_M / MA_S baselines, built on `quantreg::rq.fit.fnc`. |
| `scripts/grid6_fail.R` | Writes a well-formed `status="failed"` row when a worker task times out or dies. |
| `scripts/make_tasks_n75.R` | Builds the complete task table (one row per fit). |
| `scripts/make_queue*.R`, `coordinator_n75.R`, `grid6_worker_dyn2.sh`, `grid6_launch_dyn2.sh`, `auto_chain_n75.sh` | Distributed execution: pull-based queue, single-writer coordinator, automatic block chaining. |
| `scripts/monitor_n75.sh`, `progress_n75.R`, `eta_n75.R` | Progress monitoring and ETA. |
| `scripts/summarize_settings_n75.R` | Aggregates `results/worker_*.csv` into per-setting tables. |
| `hosts.example.txt` | Template for the machine list used by the launcher. |

## Design

- `n = 75` subjects with 2 or 3 repeated observations each (`N` around 187-196),
  four ordinary covariates `X = (1, X1, X2, time)` and `p` compositional
  predictors `Z = log(C)` derived from a softmax of correlated normals.
- Four data-generating processes:

  - **Setup I** -- homoscedastic errors;
  - **Setup II** -- subject-level random intercepts;
  - **Setup III** -- heteroscedastic errors whose scale depends on `|Z beta|`;
  - **Setup IV** -- heteroscedastic errors plus subject-level random effects.

  The six true signals are the same in all setups; the remaining coefficients
  are zero.
- `p in {500, 600, 700, 800, 900, 1000}`, `tau in {0.2, 0.5, 0.8}`, 100
  replications (`seed = 2026 + replication`), so the full grid has
  `4 x 3 x 6 x 100 = 7,200` tasks per method (43,200 in total).
- Six methods: CDA_L / CDA_M / CDA_S (this package: convex adaptive lasso,
  MCP, SCAD) and MA_ALPqr / MA_M / MA_S (adaptive lasso via LP, MCP / SCAD
  via LLA).
- Lambda grids: 60-point convex grid `exp(seq(log 1e-4, log 0.3))` for
  CDA_L and MA_ALPqr; 30-point non-convex grid from `N/5000` to `N/200`
  (quadratically concentrated towards the dense end) for the four
  non-convex fits. Lambda is chosen by GIC.
- The study sets `CDA_PILOT_SCALE=0.5` for the CDA fits (pilot penalty
  halved), which puts the CDA adaptive-lasso pilot on the same scale as the
  LP adaptive-lasso baseline.

## Running one task

Install the package tarball from the repository root first:

```r
install.packages("CDaLCqr_0.1.0.tar.gz", repos = NULL, type = "source")
```

Then, from the repository root:

```bash
Rscript simulation/scripts/grid6_task_n75.R \
  "$PWD" I 0.5 500 1 CDA_M "$CDA_LIB_DIR"
```

`ROOT` is the repository root: outputs go to `ROOT/results/`, and
`ROOT/simulation/scripts/ma_lla.R` is sourced for MA_M / MA_S.  Rows are
appended to `results/worker_<worker>.csv` (one file per worker, so parallel
workers never write the same file).  `CDA_LIB_DIR` is passed to `.libPaths()`
so a specific installed version of CDaLCqr can be selected.

## Distributed execution

`make_tasks_n75.R` writes the task table, `make_queue_n75.R` turns it into a
queue, and `coordinator_n75.R` is the single writer that hands out ids.  Every
worker machine runs `grid6_worker_dyn2.sh` in a loop; `grid6_launch_dyn2.sh`
starts the worker pool on one machine and `hosts.example.txt` lists the
machines.  `auto_chain_n75.sh` starts the next block of replications as soon as
the previous one finishes, and `monitor_n75.sh` prints the number of completed
tasks.  The protocol is plain SSH + shared `queue/`, `done/` and `results/`
directories; no scheduler is required.

## Output

One row per task, 27 columns: setting `(setup, tau, p, replication, method)`,
`status`/`error`, `N`/`seed`, selected `lambda_best`, timings, the four AEE
measures, `SIZE`, `FP`, `FN`, `PCF` (exact recovery of the support and signs)
and convergence counters.  Failed fits are recorded with `status="failed"`
instead of being dropped, so completion rates can be reported per setting.
Aggregation is done by `scripts/summarize_settings_n75.R`, which reads every
`results/worker_*.csv` and prints mean AEE / SIZE / PCF per setting and
method; paired comparisons merge the per-method rows on
`(setup, tau, p, replication)`.
