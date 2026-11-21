#!/usr/bin/env Rscript
# One task of the six-algorithm full grid.
# Usage: Rscript grid6_task.R ROOT SETUP TAU P REP METHOD LIB_DIR
# METHOD: CDA_L | CDA_M | CDA_S | MA_ALPqr | MA_M | MA_S
# Data are generated in memory from the manuscript seed (no data files).
# Failures are written as a metrics row with status='failed' and error text.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 7L || length(args) > 8L)
  stop('Usage: ROOT SETUP TAU P REP METHOD LIB_DIR [WORKER]')
root <- args[[1L]]
final_setup <- toupper(args[[2L]])
tau <- as.numeric(args[[3L]])
p <- as.integer(args[[4L]])
replication <- as.integer(args[[5L]])
method <- args[[6L]]
lib_dir <- args[[7L]]
worker <- if (length(args) >= 8L) args[[8L]] else 'adhoc'

n_subjects <- as.integer(Sys.getenv("NSUBJ", "75"))
r <- 4L
eps <- 3e-6
maxit <- 300000L
mu_augmented <- 10
kk_fixed <- 0.1
selection_threshold <- 1e-5

stopifnot(final_setup %in% c('I', 'II', 'III', 'IV'),
          tau %in% c(0.2, 0.5, 0.8),
          is.finite(p), p >= 7L,
          replication >= 1L, replication <= 100L,
          method %in% c('CDA_L', 'CDA_M', 'CDA_S', 'MA_ALPqr', 'MA_M', 'MA_S'))

seed <- 2026L + replication

# ---------- data-generating process ----------
make_XZ <- function() {
  K <- 2L + floor(runif(n_subjects, 0, 2))
  subject_id <- rep(seq_len(n_subjects), times = K)
  N <- sum(K)
  time <- unlist(lapply(K, function(k) cumsum(rexp(k, rate = 1))), use.names = FALSE)
  X1 <- rep(runif(n_subjects), times = K)
  X2 <- rep(rbinom(n_subjects, 1, .5), times = K)
  X <- cbind('(Intercept)' = 1, X1 = X1, X2 = X2, time = time)
  Sigma <- .5 ^ abs(outer(seq_len(p), seq_len(p), '-'))
  latent <- MASS::mvrnorm(N, mu = rep(0, p), Sigma = Sigma, empirical = FALSE)
  eta <- sweep(latent, 1L, apply(latent, 1L, max), '-')
  C <- exp(eta); C <- C / rowSums(C)
  list(X = X, Z = log(C), X1 = X1, X2 = X2, subject_id = subject_id, N = N,
       component_row_sum_error = max(abs(rowSums(C) - 1)))
}

generate_data <- function() {
  d <- make_XZ(); q <- qnorm(tau)
  if (final_setup == 'I') {
    beta_true <- c(1, -1.2, 2.2, 1.1, -1.5, -1.6, rep(0, p - 6L))
    alpha_true <- c(7 + q, -1, 1, -1)
    Y <- drop(d$X %*% c(7, -1, 1, -1) + d$Z %*% beta_true) + rnorm(d$N)
  } else if (final_setup == 'II') {
    beta_true <- c(1, -1.2, 2.2, 1.1, -1.5, -1.6, rep(0, p - 6L))
    alpha_true <- c(7 + q, -1, 1, -1)
    a_obs <- rnorm(n_subjects, sd = sqrt(.5))[d$subject_id]
    Y <- drop(d$X %*% c(7, -1, 1, -1) + d$Z %*% beta_true) +
      a_obs + rnorm(d$N, sd = sqrt(.5))
  } else if (final_setup == 'III') {
    beta1 <- c(1, 2, .5, .9, -1.3, -3.1, rep(0, p - 6L))
    beta2 <- c(0, 0, .3, .3, 0, -.6, rep(0, p - 6L))
    beta_true <- beta1 + q * beta2
    alpha_true <- c(7, -1 + q / 4, 1 + q / 4, -1)
    s_scale <- abs((d$X1 + d$X2) / 4 + drop(d$Z %*% beta2))
    Y <- drop(d$X %*% alpha_true + d$Z %*% beta_true) +
      s_scale * (rnorm(d$N) - q)
  } else {
    beta_true <- c(1, -1.2, 2.2, 1.1, -1.5, -1.6, rep(0, p - 6L))
    alpha_true <- c(7, -1, 1, -1)
    b2 <- c(0, .2, 0, .1, 0, 0, -.3, rep(0, p - 7L))
    s_scale <- abs(d$X1 + drop(d$Z %*% b2))
    a_obs <- rnorm(n_subjects, sd = sqrt(.5))[d$subject_id]
    Y <- drop(d$X %*% alpha_true + d$Z %*% beta_true) +
      s_scale * (a_obs + rnorm(d$N, sd = sqrt(.5)) - q)
  }
  c(d, list(Y = Y, beta_true = beta_true, alpha_true = alpha_true))
}

cda_lambda_grid <- function(N, penalty) {
  if (penalty == 'CONVEX') return(exp(seq(log(1e-4), log(.3), length.out = 60L)))
  u <- seq(0, 1, length.out = 30L)
  exp(log(N / 5000) + (log(N / 200) - log(N / 5000)) * (1 - (1 - u)^2))
}
rr_lambda_grid <- function(N) exp(seq(log(1e-4), log(.3), length.out = 60L))

# ---------- ALPqr (Ma) ----------
rr_cest <- function(Y, XX, ZZ, lambda, weights, tol = 1e-6) {
  penalty_rows <- diag(n_subjects * lambda * weights)
  design <- rbind(cbind(XX, ZZ), penalty_rows, -penalty_rows)
  augmented_y <- c(Y, rep(0, 2L * (ncol(XX) + ncol(ZZ))))
  constraint <- rbind(c(rep(0, ncol(XX)), rep(1, ncol(ZZ))),
                      c(rep(0, ncol(XX)), rep(-1, ncol(ZZ))))
  coef <- quantreg::rq.fit.fnc(design, augmented_y, constraint, c(0, 0), tau,
                               beta = .98, eps = 1e-4)$coef
  coef * (abs(coef) > tol)
}

fit_alpqr <- function(dat) {
  XX <- dat$X; ZZ <- dat$Z; N <- dat$N; lam <- rr_lambda_grid(N)
  sigma_hat <- sqrt(colMeans(ZZ^2)); standard_z <- sweep(ZZ, 2L, sigma_hat, '/')
  rlambda <- vapply(seq_len(N), function(i) {
    U <- runif(N)
    max(abs(drop((tau - (U <= tau)) %*% standard_z) / sqrt(tau * (1 - tau))))
  }, numeric(1))
  pilot_lambda <- as.numeric(stats::quantile(rlambda, .1)) / 2
  pilot <- rr_cest(dat$Y, XX, ZZ, pilot_lambda / (2 * n_subjects),
                   c(rep(0, r), sqrt(tau * (1 - tau)) * sigma_hat))
  adaptive <- 1 / abs(pilot[-seq_len(r)]); adaptive[!is.finite(adaptive)] <- 1e10
  fits <- vector('list', length(lam)); gic <- numeric(length(lam))
  for (k in seq_along(lam)) {
    cf <- rr_cest(dat$Y, XX, ZZ, lam[[k]], c(rep(0, r), adaptive))
    beta <- cf[-seq_len(r)]; resid <- dat$Y - drop(cbind(XX, ZZ) %*% cf)
    size <- sum(abs(beta) > 1e-5); if (size >= n_subjects) size <- 1e30
    loss <- sum(resid * (tau - (resid < 0))) / n_subjects
    gic[[k]] <- log(max(loss, .Machine$double.xmin)) +
      log(p) * log(log(n_subjects)) / n_subjects * (size - 1)
    fits[[k]] <- cf
  }
  idx <- which.min(gic)
  list(alpha = fits[[idx]][seq_len(r)], beta = fits[[idx]][r + seq_len(p)],
       lambda_best = lam[[idx]], lambda_index = idx, lambda = lam,
       diagnostics = data.frame(lambda = lam, GIC = gic, converged = TRUE,
                                iterations = NA_real_))
}

# ---------- run ----------
.libPaths(c(lib_dir, '/mnt/cda/R/library', .libPaths()))
set.seed(seed)
dat <- generate_data()

# initialise so a failed fit still produces a well-formed row
lam_used <- NULL
alpha <- NULL; beta <- NULL
lambda_best <- NA_real_; idx <- NA_integer_
diagnostics <- NULL
selected_iterations <- NA_real_; selected_converged <- NA
path_converged <- NA_integer_
package_version <- NA_character_

start <- proc.time()[['elapsed']]
status <- 'ok'; error_msg <- ''
fit <- NULL
tryCatch({
  if (startsWith(method, 'CDA_')) {
    suppressPackageStartupMessages(library(CDaLCqr, lib.loc = lib_dir))
    penalty <- c(CDA_L = 'CONVEX', CDA_M = 'MCP', CDA_S = 'SCAD')[[method]]
    lam <- cda_lambda_grid(dat$N, penalty)
    a_arg <- if (penalty == 'MCP') 1.05 else if (penalty == 'SCAD') 2.01 else NULL
    fit <- CDaLCqr(x = cbind(dat$X, dat$Z), y = dat$Y, r = r, p = p, n = n_subjects,
                   tau = tau, lambda = lam, kk = kk_fixed,
                   mu = mu_augmented, wgt_scale = 1, penalty = penalty, a = a_arg,
                   eps = eps, maxit = maxit, select_ka = FALSE)
    lam_used <- lam
    idx <- which.min(abs(lam - fit$lambda_best))
    alpha <- drop(fit$alp_rq); beta <- drop(fit$beta_rq)
    lambda_best <- fit$lambda_best
    diagnostics <- fit$path_diagnostics
    selected_iterations <- diagnostics$iterations[[idx]]
    selected_converged <- diagnostics$converged[[idx]]
    path_converged <- sum(diagnostics$converged)
    package_version <- as.character(utils::packageVersion('CDaLCqr'))
  } else if (method == 'MA_ALPqr') {
    fit <- fit_alpqr(dat)
    lam_used <- fit$lambda
    alpha <- fit$alpha; beta <- fit$beta
    lambda_best <- fit$lambda_best; idx <- fit$lambda_index
    diagnostics <- fit$diagnostics
    selected_iterations <- NA_real_; selected_converged <- TRUE
    path_converged <- TRUE
    package_version <- paste('quantreg', as.character(utils::packageVersion('quantreg')))
  } else {
    source(file.path(root, 'simulation', 'scripts', 'ma_lla.R'))
    penalty <- c(MA_M = 'MCP', MA_S = 'SCAD')[[method]]
    a_arg <- if (penalty == 'MCP') 1.05 else 2.01
    lam <- cda_lambda_grid(dat$N, penalty)
    fit <- ma_lla_path(dat$Y, dat$X, dat$Z, n_subjects, tau, lam, penalty, a_arg,
                       max_outer = 50L, coef_tol = 1e-6,
                       objective_tol = 1e-7, lp_eps = 1e-5)
    lam_used <- lam
    alpha <- fit$alpha; beta <- fit$beta
    lambda_best <- fit$lambda_best; idx <- fit$lambda_index
    diagnostics <- fit$diagnostics
    selected_iterations <- diagnostics$outer_iterations[[idx]]
    selected_converged <- diagnostics$converged[[idx]]
    path_converged <- sum(diagnostics$converged)
    package_version <- 'ma_lla.R'
  }
}, error = function(e) {
  status <<- 'failed'
  error_msg <<- gsub('[",\r\n]', ' ', conditionMessage(e))
})

elapsed <- proc.time()[['elapsed']] - start

row <- data.frame(
  setup = final_setup, tau = tau, p = p, replication = replication, method = method,
  status = status, error = error_msg, N = dat$N, seed = seed,
  lambda_count = if (exists('lam_used')) length(lam_used) else NA_integer_,
  lambda_best = if (status == 'ok') lambda_best else NA_real_,
  lambda_index = if (status == 'ok') idx else NA_integer_,
  time_total_path = elapsed,
  AEE_l1 = if (status == 'ok') sum(abs(beta - dat$beta_true)) else NA_real_,
  AEE_l2 = if (status == 'ok') sum((beta - dat$beta_true)^2) else NA_real_,
  AEE_linf = if (status == 'ok') max(abs(beta - dat$beta_true)) else NA_real_,
  alpha_AEE_l1 = if (status == 'ok') sum(abs(alpha - dat$alpha_true)) else NA_real_,
  SIZE = if (status == 'ok') sum(abs(beta) >= selection_threshold) else NA_integer_,
  FP = NA_integer_, FN = NA_integer_, PCF = NA_integer_,
  SUM = if (status == 'ok') abs(sum(beta)) else NA_real_,
  selected_iterations = if (status == 'ok') selected_iterations else NA_real_,
  selected_converged = if (status == 'ok') selected_converged else NA,
  path_converged = if (status == 'ok') path_converged else NA_integer_,
  package_version = package_version,
  stringsAsFactors = FALSE)

if (status == 'ok') {
  selected <- abs(beta) >= selection_threshold
  shown <- beta; shown[!selected] <- 0
  signal <- abs(dat$beta_true) > 0
  row$FP <- sum(selected & !signal)
  row$FN <- sum(!selected & signal)
  row$PCF <- as.integer(all(sign(shown) == sign(dat$beta_true)))
}

out_dir <- file.path(root, 'results')
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
stem <- sprintf('%s_%02d_p%d_rep%03d_%s', final_setup, round(tau * 10), p, replication, method)
out_file <- file.path(out_dir, paste0('worker_', worker, '.csv'))
new_file <- !file.exists(out_file)
write.table(row, out_file, sep = ',', row.names = FALSE,
            col.names = new_file, append = !new_file, quote = TRUE)

if (identical(Sys.getenv('SAVE_FIT'), '1') && status == 'ok') {
  bdir <- file.path(root, 'fits'); dir.create(bdir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(list(beta = beta, alpha = alpha, lambda_best = lambda_best,
               lambda = lam_used, seed = seed),
          file.path(bdir, paste0(stem, '.rds')))
}

cat(sprintf('%s %s %.1fs N=%d%s\n', toupper(status), stem, elapsed, dat$N,
            if (status == 'ok') sprintf(' lambda=%.6g AEE=%.4f SIZE=%d',
                                        lambda_best, row$AEE_l1, row$SIZE) else paste0(' err=', error_msg)))
