# CDaLCqr

`CDaLCqr` is an R package for penalized longitudinal log-contrast quantile regression with high-dimensional compositional covariates. It provides a coordinate descent algorithm with a smoothed quantile loss and a zero-sum constraint on the compositional coefficients. The available penalties are adaptive Lasso, MCP, and SCAD.

The package accompanies the manuscript *A Unified Coordinate Descent Framework for Penalized Longitudinal Log-Contrast Quantile Regression*.

## Installation

After uploading this package source to a GitHub repository named `CDaLCqr`, replace `YOUR_USERNAME` with the repository owner's GitHub username or organization name:

```r
install.packages("remotes")
remotes::install_github("YOUR_USERNAME/CDaLCqr")
```

The package contains C++ code, so installing from source requires a working R compiler toolchain. On Windows, install the Rtools version appropriate for your R version.

## Example

The design matrix must have one row per observation. Put the `r` unpenalized covariates first, followed by the `p` log-transformed compositional covariates. Include an intercept column yourself when needed. Pass the number of subjects as `n` and a response vector with one value per row of `x` as `y`.

```r
set.seed(104)
n <- 10L
N <- 3L * n
composition <- matrix(rexp(N * 3L) + 0.1, nrow = N, ncol = 3L)
z <- log(composition / rowSums(composition))
x <- cbind(1, rnorm(N), z)
y <- drop(x %*% c(0.4, -0.6, 1, -1, 0) + rnorm(N, sd = 0.3))

set.seed(73)
fit <- CDaLCqr::CDaLCqr(
  x = x, y = y, r = 2L, p = 3L, n = n, tau = 0.5,
  ini = 1L, lambda = c(0.01, 0.1), penalty = "Adaptive Lasso",
  kk = 0.1, eps = 1e-5, maxit = 10000L
)

fit$alp_rq               # coefficients for the unpenalized covariates
fit$beta_rq              # coefficients for the compositional covariates
fit$lambda_best          # lambda selected by GIC
fit$path_diagnostics     # iterations, convergence, and constraint residual
```

Use `penalty = "MCP", a = 3` or `penalty = "SCAD", a = 3.7` for the other penalties. The default penalty is adaptive Lasso, and the default initialization is `ini = 1`. The earlier input `penalty = "CONVEX"` is also accepted for adaptive Lasso.

Pass `lambda = NULL` to generate a candidate sequence automatically. The call must include the `lambda` argument, even when its value is `NULL`.

The returned `lambda_GIC` and `lambda_grid` give the GIC values and candidate tuning parameters. `path_diagnostics` reports whether each candidate fit met the convergence tolerance. The reported coefficients correspond to the selected candidate.
