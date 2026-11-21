args <- commandArgs(trailingOnly = TRUE)
root <- args[[1L]]
rep_from <- as.integer(args[[2L]])
rep_to   <- as.integer(args[[3L]])
idx0     <- as.integer(args[[4L]])
setups <- c('I', 'II', 'III', 'IV')
taus <- c(0.2, 0.5, 0.8)
ps <- seq(500L, 1000L, by = 100L)
methods <- c('CDA_L', 'CDA_M', 'CDA_S', 'MA_ALPqr', 'MA_M', 'MA_S')
reps <- seq.int(rep_from, rep_to)
qdir <- file.path(root, 'queue')
dir.create(qdir, recursive = TRUE, showWarnings = FALSE)
idx <- idx0; n <- 0L
for (p in ps) for (s in setups) for (tau in taus) for (rep in reps) for (m in methods) {
  idx <- idx + 1L
  id <- sprintf('%05d_%s_t%.1f_p%d_r%03d_%s', idx, s, tau, p, rep, m)
  f <- file.path(qdir, paste0(id, '.task'))
  if (!file.exists(f)) {
    writeLines(sprintf('%s,%s,%d,%d,%s', s, tau, p, rep, m), f)
    n <- n + 1L
  }
}
cat(sprintf('%s new_tasks=%d reps=%d-%d idx=%d..%d\n', format(Sys.time()),
            n, rep_from, rep_to, idx0 + 1L, idx))
