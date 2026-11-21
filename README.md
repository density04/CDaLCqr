# CDaLCqr

R package and reproducible simulation code for **coordinate descent estimation of
longitudinal quantile regression with high-dimensional compositional
covariates** (CDA-LCQR).

The repository is intentionally kept small and simple:

| Content | Description |
| --- | --- |
| `CDaLCqr_0.1.0.tar.gz` | Source package (install it directly with R) |
| `China_AIC_Panel_2016-2023.xlsx` | Example data: Chinese AIC / household panel, 2016--2023 |
| `simulation/` | All code of the simulation study reported in the paper |
| `README.md` | This file |
| `LICENSE.md`, `CITATION.cff` | License and citation information |

The repository ships code and example data only; generated simulation
outputs are not included.

## Install the package

```r
install.packages("CDaLCqr_0.1.0.tar.gz", repos = NULL, type = "source")
```

Requirements: R (>= 3.5), Rcpp, RcppEigen, quantreg.  RcppEigen is header-only
and is pulled in at compile time; on a fresh machine install the runtime
dependencies first:

```r
install.packages(c("Rcpp", "RcppEigen", "quantreg"))
```

The package contains C++ code, so a working compiler toolchain is required.  On
Windows install the Rtools version matching your R version.

## Quick start

```r
library(CDaLCqr)

# x: N x (r + p) model matrix, unpenalized covariates first, then log(C)
# y: response, one value per row of x
# n: number of subjects (N >= n for longitudinal data)
fit <- CDaLCqr(x = cbind(1, time, z), y = y, r = 2, p = 40, n = 75, tau = 0.5,
               penalty = "Adaptive Lasso")

fit$alp_rq            # coefficients of the unpenalized covariates
fit$beta_rq           # coefficients of the compositional covariates
fit$lambda_best       # lambda selected by GIC
fit$path_diagnostics  # GIC, iterations and convergence per lambda
```

The three penalties of the paper are selected with `penalty = "Adaptive Lasso"`
(default), `"MCP"` or `"SCAD"`.  The non-convex penalties require the shape
parameter, e.g. `penalty = "MCP", a = 1.05` or `penalty = "SCAD", a = 2.01`.
Pass `lambda = NULL` (or omit it) to generate the default grid, and see
`?CDaLCqr` for the complete argument list.

## Example data

`China_AIC_Panel_2016-2023.xlsx` contains the panel used for the real-data
illustration:

- 84 region-year observations from 16 regions, years 2016--2023;
- columns `Year`, `Region`, `Centered_year`, `Y` (response) and `W1`--`W44`
  (expenditure shares that sum to one in every row);
- the compositional covariates are `z = log(W)`.

A complete example:

```r
library(readxl)
library(CDaLCqr)

d  <- read_excel("China_AIC_Panel_2016-2023.xlsx")
z  <- log(as.matrix(d[, paste0("W", 1:44)]))
x  <- cbind(1, d$Centered_year, z)

fit <- CDaLCqr(x = x, y = d$Y, r = 2, p = 44, n = nrow(d), tau = 0.5)
sum(abs(fit$beta_rq) >= 1e-5)   # number of selected compositional covariates
```

## Simulation study

The `simulation/` folder is self-contained:

```
simulation/
├── README.md              # data-generating processes, estimators, seeds
└── scripts/
    ├── grid6_task_n75.R   # one replication: DGP + six estimators
    ├── ma_lla.R           # MA baselines (ALPqr, MCP, SCAD)
    ├── grid6_fail.R       # failsafe re-run of crashed tasks
    ├── make_tasks_n75.R   # build the complete task table
    ├── make_queue_n75.R   # (re)build a queue from a task table
    ├── coordinator_n75.R  # single-writer coordinator for the queue
    ├── grid6_launch_dyn2.sh, grid6_worker_dyn2.sh
    ├── coord_watch_n75.sh, auto_chain_n75.sh
    ├── monitor_n75.sh, progress_n75.R, eta_n75.R
    ├── summarize_settings_n75.R
    └── hosts.example.txt  # machine list template
```

A single replication can be run without any scheduler:

```bash
Rscript simulation/scripts/grid6_task_n75.R <task_id>
```

The production run used 100 replications × 72 settings × 6 estimators, seeds
`2026 + replication`, and a dynamic pull queue over several Linux machines; see
`simulation/README.md` for the exact protocol and output format.

## Reproducibility notes

- All simulation results in the paper are based on 100 replications; seeds are
  `2026 + replication`, so every task is independently reproducible.
- The estimators share the same data, lambda grids and GIC rule; the pilot
  penalty of the CDA methods is scaled by `CDA_PILOT_SCALE` (0.5 in the paper)
  to align the pilot with the LP adaptive-lasso baseline.
- The package tarball is the exact version used for the study (0.1.0).

## Citation

If you use this code, please cite the paper (see `CITATION.cff` for the current
BibTeX entry).

## License

GPL (>= 2), see `LICENSE.md`.
