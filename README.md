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

The `simulation/` folder contains the core code of the study:

```
simulation/
├── README.md            # design, parameter settings, output format
└── scripts/
    ├── fit_task.R       # one fit: data generation + one estimator + evaluation
    └── ma_baselines.R   # MA baselines (ALPqr, LLA MCP / SCAD)
```

A single fit can be run without any scheduler.  Install the package first (see
above), then from the repository root:

```bash
export CDA_LIB_DIR="$HOME/R/library"     # library holding CDaLCqr 0.1.0
Rscript simulation/scripts/fit_task.R \
  "$PWD" I 0.5 500 1 CDA_M "$CDA_LIB_DIR"
```

The argument order is `ROOT SETUP TAU P REPLICATION METHOD LIB_DIR [WORKER_ID]`;
the row is appended to `results/worker_<WORKER_ID>.csv`.  `NSUBJ` (default 75)
sets the number of subjects, and `CDA_R_LIBS` lists additional library paths
(for example the library holding `quantreg`) when they are not on the default
search path.

The full study is a loop over 4 data-generating processes × 3 quantile levels ×
6 dimensions `p` × 100 replications × 6 estimators; the loop is shown in
`simulation/README.md`.  Seeds are `2026 + replication`, so every fit is
independently reproducible.

## Reproducibility notes

- All simulation results in the paper are based on 100 replications; seeds are
  `2026 + replication`, so every task is independently reproducible.
- The estimators share the same data, lambda grids and GIC rule; the pilot
  penalty of the CDA methods is scaled by `CDA_PILOT_SCALE` (0.5 in the paper)
  to align the pilot with the LP adaptive-lasso baseline.
- The package tarball is the exact version used for the study (0.1.0).

## Citation

If you use CDaLCqr in your work, please cite the accompanying paper.

## License

GPL (>= 2), as declared in the package `DESCRIPTION`.
