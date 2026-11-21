args <- commandArgs(trailingOnly = TRUE)
root <- args[[1L]]
nworkers <- if (length(args) >= 2L) as.integer(args[[2L]]) else 96L
q <- list.files(file.path(root, 'queue'), '\\.task$')
ids <- sub('\\.task$', '', q)
dn <- list.files(file.path(root, 'done'))
rem <- setdiff(ids, dn)
inflight <- setdiff(list.files(file.path(root, 'assign')), dn)
cat(sprintf('queue=%d done=%d inflight=%d remaining=%d workers=%d\n',
            length(ids), length(dn), length(inflight), length(rem), nworkers))
f <- list.files(file.path(root, 'results'), '\\.csv$', full.names = TRUE)
if (length(f)) {
  d <- do.call(rbind, lapply(f, function(x) tryCatch(read.csv(x, stringsAsFactors = FALSE),
                                                     error = function(e) NULL)))
  d <- d[!is.na(d$status), ]
  d$key <- paste(d$setup, d$tau, d$p, d$replication, d$method)
  d <- d[order(d$status != 'ok'), ]
  d <- d[!duplicated(d$key), ]
  cat('rows', nrow(d), 'ok', sum(d$status == 'ok'), 'failed', sum(d$status == 'failed'),
      'reps_done_pct', sprintf('%.1f%%', 100 * nrow(d) / length(ids)), '\n')
  ok <- d[d$status == 'ok', ]
  if (nrow(ok) && length(rem)) {
    tm <- aggregate(time_total_path ~ method, ok, function(x) mean(x, na.rm = TRUE))
    tmp <- aggregate(time_total_path ~ method + p, ok, function(x) mean(x, na.rm = TRUE))
    names(tmp)[[3L]] <- 't_mp'
    pm <- data.frame(method = sub('^[0-9]+_[^_]+_t[^_]+_p[0-9]+_r[0-9]+_', '', rem),
                     p = as.integer(sub('^[0-9]+_[^_]+_t[^_]+_p([0-9]+)_r[0-9]+_.*$', '\\1', rem)))
    cnt <- aggregate(n_rem ~ method + p, data = transform(pm, n_rem = 1L), FUN = sum)
    est <- merge(cnt, tmp, by = c('method', 'p'), all.x = TRUE)
    est <- merge(est, tm, by = 'method', all.x = TRUE)
    est$t_use <- ifelse(!is.na(est$t_mp), est$t_mp, est$time_total_path)
    est$eta_core_h <- est$n_rem * est$t_use / 3600
    bym <- aggregate(cbind(n_rem, eta_core_h) ~ method, est, sum)
    bym$eta_wall_h <- bym$eta_core_h / nworkers
    bym <- bym[order(-bym$eta_core_h), ]
    print(bym, row.names = FALSE, digits = 3)
    cat(sprintf('TOTAL remaining core-h %.0f wall-h %.1f\n', sum(bym$eta_core_h),
                sum(bym$eta_core_h) / nworkers))
  }
}
