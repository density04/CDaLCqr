# ETA model v2: fill MA_M/MA_S with power-law in p; calibrate n-scale on observed p500.
files50 <- list.files(Sys.getenv('GRID6_N50', '/mnt/cda/repro3/grid6/results'), '\\.csv$', full.names = TRUE)
d50 <- do.call(rbind, lapply(files50, read.csv, stringsAsFactors = FALSE))
d50 <- d50[d50$status == 'ok' & !is.na(d50$time_total_path), ]
d50$key <- paste(d50$setup, d50$tau, d50$p, d50$replication, d50$method)
d50 <- d50[!duplicated(d50$key), ]
t50 <- aggregate(time_total_path ~ method + p, d50, function(x) mean(x, na.rm = TRUE))
files75 <- list.files(Sys.getenv('GRID6_N75', '/mnt/cda/repro3/grid6_n75/results'), '\\.csv$', full.names = TRUE)
d75 <- do.call(rbind, lapply(files75, read.csv, stringsAsFactors = FALSE))
d75 <- d75[d75$status == 'ok' & !is.na(d75$time_total_path), ]
d75$key <- paste(d75$setup, d75$tau, d75$p, d75$replication, d75$method)
d75 <- d75[!duplicated(d75$key), ]
t75 <- aggregate(time_total_path ~ method + p, d75, function(x) mean(x, na.rm = TRUE))
ps <- c(500, 600, 700, 800, 900, 1000)
methods <- c('CDA_L', 'CDA_M', 'CDA_S', 'MA_ALPqr', 'MA_M', 'MA_S')
cat('observed n50 (s):\n'); print(round(xtabs(time_total_path ~ p + method, t50), 1))
cat('\nobserved n75 (s):\n'); print(round(xtabs(time_total_path ~ p + method, t75), 1))
# n-scale f per method from p=500 where both exist; else median
f <- sapply(methods, function(m) {
  a <- t75$time_total_path[t75$method == m & t75$p == 500]
  b <- t50$time_total_path[t50$method == m & t50$p == 500]
  if (length(a) && length(b) && b > 0) a / b else NA_real_
})
f[is.na(f)] <- median(f, na.rm = TRUE)
cat('\nn-scale f(method) at p500:\n'); print(round(f, 3))
# base cost at n50 for each method,p: observed if present, else power law through available points
base <- matrix(NA_real_, length(ps), length(methods), dimnames = list(ps, methods))
for (m in methods) {
  obs <- t50[t50$method == m, ]
  for (p0 in ps) {
    hit <- obs$time_total_path[obs$p == p0]
    if (length(hit)) base[as.character(p0), m] <- hit[[1]]
  }
  ok <- !is.na(base[, m])
  if (sum(ok) >= 2) {
    fit <- lm(log(base[ok, m]) ~ log(ps[ok]))
    cf <- coef(fit)
    base[!ok, m] <- exp(cf[[1]] + cf[[2]] * log(ps[!ok]))
  } else if (sum(ok) == 1) {
    base[!ok, m] <- base[ok, m] * (ps[!ok] / ps[ok])^1.5
  }
}
# MA_S: no n50 history at all -> use MA_M shape, calibrate level on observed n75 p500
t_hat <- sweep(base, 2L, f, '*')
if (all(is.na(base[, 'MA_S']))) {
  ratio <- t75$time_total_path[t75$method == 'MA_S' & t75$p == 500] /
           t75$time_total_path[t75$method == 'MA_M' & t75$p == 500]
  ratio <- if (length(ratio)) ratio[[1]] else 0.5
  t_hat[, 'MA_S'] <- t_hat[, 'MA_M'] * ratio
}
# observed n75 p500 sanity check
cat('\ncalibration check at n75 p500 (model vs observed):\n')
chk <- data.frame(method = methods,
                  model = round(t_hat['500', ], 1),
                  observed = round(sapply(methods, function(m) {
                    v <- t75$time_total_path[t75$method == m & t75$p == 500]
                    if (length(v)) v[[1]] else NA_real_
                  }), 1))
print(chk, row.names = FALSE)
# remaining tasks by method,p (20 reps per setting; done from results)
grid <- expand.grid(setup = c('I', 'II', 'III', 'IV'), tau = c(0.2, 0.5, 0.8), p = ps,
                    method = methods, stringsAsFactors = FALSE)
grid$gk <- paste(grid$setup, grid$tau, grid$p, grid$method)
d75$gk <- paste(d75$setup, d75$tau, d75$p, d75$method)
nd <- table(factor(d75$gk, levels = unique(grid$gk)))
grid$done <- as.integer(nd[grid$gk]); grid$done[is.na(grid$done)] <- 0L
grid$remaining <- pmax(20L - grid$done, 0L)
grid$t_hat <- mapply(function(m, p0) t_hat[as.character(p0), m], grid$method, grid$p)
grid$core_h <- grid$remaining * grid$t_hat / 3600
cat('\nremaining core-hours by p x method:\n')
print(round(xtabs(core_h ~ p + method, grid), 1))
tot <- sum(grid$core_h, na.rm = TRUE)
cat('\ntotal remaining core-hours:', round(tot, 1), ' done tasks:', sum(grid$done), '/', nrow(grid) * 20, '\n')
for (w in c(96, 140, 155, 172)) cat(sprintf('at %d workers: %.1f h = %.2f d\n', w, tot / w, tot / w / 24))
cat('\ncore-hours by p:\n'); print(round(xtabs(core_h ~ p, grid), 1))
