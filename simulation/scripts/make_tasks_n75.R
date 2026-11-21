args <- commandArgs(trailingOnly = TRUE)
root <- args[[1L]]
rep_from <- if (length(args) >= 2L) as.integer(args[[2L]]) else 1L
rep_to <- if (length(args) >= 3L) as.integer(args[[3L]]) else 20L
setups <- c('I', 'II', 'III', 'IV')
taus <- c(0.2, 0.5, 0.8)
ps <- seq(500L, 1000L, by = 100L)
methods <- c('CDA_L', 'CDA_M', 'CDA_S', 'MA_ALPqr', 'MA_M', 'MA_S')
reps <- seq.int(rep_from, rep_to)
tasks <- list(); b <- 1L
for (p in ps) for (s in setups) for (tau in taus) for (rep in reps) for (m in methods) {
  tasks[[b]] <- data.frame(setup = s, tau = tau, p = p, rep = rep, method = m,
                           stringsAsFactors = FALSE)
  b <- b + 1L
}
d <- do.call(rbind, tasks)
stopifnot(nrow(d) == length(ps) * length(setups) * length(taus) * length(reps) * length(methods))
write.csv(d, file.path(root, 'tasks.csv'), row.names = FALSE, quote = FALSE)
cat('tasks', nrow(d), 'settings', length(ps) * length(setups) * length(taus),
    'reps', length(reps), '\n')
