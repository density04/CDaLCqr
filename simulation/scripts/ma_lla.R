ma_check_loss <- function(residual, tau) residual * (tau - (residual < 0))

ma_penalty_value <- function(u, lambda, penalty, a) {
  u <- abs(u)
  if (penalty == 'MCP') {
    return(ifelse(u <= a * lambda, lambda * u - u^2 / (2 * a),
                  a * lambda^2 / 2))
  }
  if (penalty == 'SCAD') {
    return(ifelse(u <= lambda, lambda * u,
                  ifelse(u <= a * lambda,
                         (2 * a * lambda * u - u^2 - lambda^2) / (2 * (a - 1)),
                         (a + 1) * lambda^2 / 2)))
  }
  stop('penalty must be MCP or SCAD')
}

ma_penalty_derivative <- function(u, lambda, penalty, a) {
  u <- abs(u)
  if (penalty == 'MCP') return(pmax(lambda - u / a, 0))
  if (penalty == 'SCAD') {
    return(ifelse(u <= lambda, lambda,
                  ifelse(u <= a * lambda, (a * lambda - u) / (a - 1), 0)))
  }
  stop('penalty must be MCP or SCAD')
}

# weights are the complete coefficients of |beta_j| in the normalized objective.
# The two pseudo-observations for coordinate j have +/- n*weights[j], since
# rho_tau(v) + rho_tau(-v) = |v| for every tau in (0,1).
ma_weighted_lp <- function(y, X, Z, n, tau, weights, lp_eps = 1e-5,
                           lp_beta = 0.98) {
  X <- as.matrix(X); Z <- as.matrix(Z)
  storage.mode(X) <- 'double'; storage.mode(Z) <- 'double'
  y <- as.double(y); weights <- as.double(weights)
  N <- length(y); r <- ncol(X); p <- ncol(Z)
  stopifnot(nrow(X) == N, nrow(Z) == N, length(weights) == p,
            all(is.finite(weights)), all(weights >= 0),
            is.finite(n), n > 0, tau > 0, tau < 1)
  if (any(!is.finite(y)) || any(!is.finite(X)) || any(!is.finite(Z)))
    stop('y, X and Z must be finite')
  active <- which(weights > 0)
  m <- length(active)
  design <- matrix(0, nrow = N + 2L * m, ncol = r + p)
  design[seq_len(N), ] <- cbind(X, Z)
  if (m) {
    col <- r + active
    design[cbind(N + seq_len(m), col)] <- n * weights[active]
    design[cbind(N + m + seq_len(m), col)] <- -n * weights[active]
  }
  response <- c(y, rep(0, 2L * m))
  constraint <- rbind(c(rep(0, r), rep(1, p)),
                      c(rep(0, r), rep(-1, p)))
  fit <- quantreg::rq.fit.fnc(x = design, y = response, R = constraint,
                              r = c(0, 0), tau = tau, beta = lp_beta,
                              eps = lp_eps)
  coefficient <- as.double(fit$coef)
  if (length(coefficient) != r + p || any(!is.finite(coefficient)))
    stop('rq.fit.fnc returned invalid coefficients')
  list(alpha = coefficient[seq_len(r)], beta = coefficient[r + seq_len(p)],
       constraint_residual = sum(coefficient[r + seq_len(p)]),
       penalized_coordinates = m)
}

ma_nonconvex_objective <- function(y, X, Z, n, tau, alpha, beta,
                                   lambda, penalty, a) {
  residual <- as.double(y - drop(X %*% alpha + Z %*% beta))
  sum(ma_check_loss(residual, tau)) / n +
    sum(ma_penalty_value(beta, lambda, penalty, a))
}

ma_lla_fit <- function(y, X, Z, n, tau, lambda, penalty, a,
                       initial_alpha, initial_beta, max_outer = 30L,
                       coef_tol = 1e-6, objective_tol = 1e-7,
                       lp_eps = 1e-5, lp_beta = 0.98) {
  penalty <- toupper(penalty)
  if (penalty == 'MCP' && !(is.finite(a) && a > 1)) stop('MCP needs a > 1')
  if (penalty == 'SCAD' && !(is.finite(a) && a > 2)) stop('SCAD needs a > 2')
  if (!is.finite(lambda) || lambda <= 0) stop('lambda must be positive')
  if (max_outer < 1L) stop('max_outer must be >= 1')
  X <- as.matrix(X); Z <- as.matrix(Z)
  alpha <- as.double(initial_alpha); beta <- as.double(initial_beta)
  if (length(alpha) != ncol(X) || length(beta) != ncol(Z))
    stop('initial coefficient lengths do not match design')
  if (any(!is.finite(c(alpha, beta)))) stop('initial coefficients must be finite')
  initial_objective <- ma_nonconvex_objective(y, X, Z, n, tau, alpha, beta,
                                              lambda, penalty, a)
  previous_objective <- initial_objective
  history <- vector('list', max_outer)
  converged <- FALSE
  for (outer in seq_len(max_outer)) {
    derivative <- ma_penalty_derivative(beta, lambda, penalty, a)
    next_fit <- ma_weighted_lp(y, X, Z, n, tau, derivative, lp_eps, lp_beta)
    next_objective <- ma_nonconvex_objective(y, X, Z, n, tau,
                                             next_fit$alpha, next_fit$beta,
                                             lambda, penalty, a)
    change <- max(abs(c(next_fit$alpha - alpha, next_fit$beta - beta)))
    scale <- 1 + max(abs(c(alpha, beta)))
    increase <- next_objective - previous_objective
    history[[outer]] <- data.frame(iteration = outer, objective = next_objective,
      objective_change = increase, coefficient_change = change,
      constraint_residual = next_fit$constraint_residual,
      penalized_coordinates = next_fit$penalized_coordinates)
    alpha <- next_fit$alpha; beta <- next_fit$beta
    if (increase > objective_tol * max(1, abs(previous_objective))) {
      warning(sprintf('LLA objective increased at outer iteration %d by %.3g',
                      outer, increase))
    }
    previous_objective <- next_objective
    if (change <= coef_tol * scale &&
        abs(increase) <= objective_tol * max(1, abs(next_objective))) {
      converged <- TRUE
      break
    }
  }
  list(alpha = alpha, beta = beta, lambda = lambda, penalty = penalty, a = a,
       initial_objective = initial_objective, objective = previous_objective,
       outer_iterations = outer, converged = converged,
       history = do.call(rbind, history[seq_len(outer)]),
       constraint_residual = sum(beta))
}

# Belloni-Chernozhukov pilot lambda draw, implemented independently of CDaLCqr.
ma_bc_rlambda <- function(Z, sigma_hat, tau, block = 500L) {
  N <- nrow(Z)
  if (!is.finite(block) || block < 1) stop('block must be positive')
  standardized <- sweep(Z, 2L, sigma_hat, '/')
  out <- numeric(N)
  start <- 1L
  while (start <= N) {
    nb <- min(as.integer(block), N - start + 1L)
    uniforms <- matrix(stats::runif(N * nb), nrow = N)
    score <- crossprod(tau - (uniforms <= tau), standardized)
    out[start:(start + nb - 1L)] <-
      apply(abs(score), 1L, max) / sqrt(tau * (1 - tau))
    start <- start + nb
  }
  out
}

# Reproduces the pilot initialization used by CDaLCqr, without calling it.
# Call with the same RNG state immediately after generating the data.
ma_cda_bc_pilot <- function(y, X, Z, n, tau) {
  sigma_hat <- sqrt(colMeans(Z^2))
  if (any(sigma_hat <= 0)) stop('Z contains a zero-variance column')
  rlambda <- ma_bc_rlambda(Z, sigma_hat, tau)
  pilot_lambda <- as.numeric(stats::quantile(rlambda, 0.1)) / 2
  w <- sqrt(tau * (1 - tau)) * sigma_hat
  fit <- ma_weighted_lp(y, X, Z, n, tau,
                        weights = pilot_lambda * w / n,
                        lp_eps = 1e-4, lp_beta = 0.98)
  fit$pilot_lambda <- pilot_lambda
  fit
}

ma_lla_path <- function(y, X, Z, n, tau, lambda_grid, penalty, a,
                        initial = NULL, max_outer = 30L, coef_tol = 1e-6,
                        objective_tol = 1e-7, lp_eps = 1e-5,
                        selection_threshold = 1e-5) {
  X <- as.matrix(X); Z <- as.matrix(Z)
  p <- ncol(Z)
  lambda_grid <- as.double(lambda_grid)
  if (!length(lambda_grid) || any(!is.finite(lambda_grid)) ||
      any(lambda_grid <= 0)) stop('lambda_grid must contain positive values')
  start <- proc.time()[['elapsed']]
  pilot <- if (is.null(initial)) ma_cda_bc_pilot(y, X, Z, n, tau) else initial
  if (is.null(pilot$alpha) || is.null(pilot$beta))
    stop('initial must contain alpha and beta')
  fits <- lapply(lambda_grid, function(lambda) {
    ma_lla_fit(y, X, Z, n, tau, lambda, penalty, a,
               pilot$alpha, pilot$beta, max_outer = max_outer,
               coef_tol = coef_tol, objective_tol = objective_tol,
               lp_eps = lp_eps)
  })
  diagnostics <- do.call(rbind, lapply(seq_along(fits), function(i) {
    f <- fits[[i]]
    residual <- as.double(y - drop(X %*% f$alpha + Z %*% f$beta))
    loss <- sum(ma_check_loss(residual, tau)) / n
    size <- sum(abs(f$beta) >= selection_threshold)
    GIC <- if (size >= n) Inf else
      log(max(loss, .Machine$double.xmin)) +
      pmax(size - 1L, 0L) * log(p) * log(log(n)) / n
    data.frame(lambda = lambda_grid[[i]], GIC = GIC, size = size,
               outer_iterations = f$outer_iterations, converged = f$converged,
               objective = f$objective,
               constraint_residual = f$constraint_residual)
  }))
  if (all(!is.finite(diagnostics$GIC)))
    stop('no admissible lambda on this grid')
  best <- which.min(diagnostics$GIC)
  list(alpha = fits[[best]]$alpha, beta = fits[[best]]$beta,
       lambda_best = lambda_grid[[best]], lambda_index = best,
       lambda_grid = lambda_grid, diagnostics = diagnostics,
       fits = fits, initial = pilot,
       elapsed = proc.time()[['elapsed']] - start)
}
