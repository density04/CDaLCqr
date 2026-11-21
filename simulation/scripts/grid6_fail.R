#!/usr/bin/env Rscript
# Record a failure row when a worker task times out or dies without writing.
# Usage: Rscript grid6_fail.R ROOT SETUP TAU P REP METHOD WORKER RC
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 8L) stop('Usage: ROOT SETUP TAU P REP METHOD WORKER RC')
root <- args[[1L]]; setup <- toupper(args[[2L]]); tau <- as.numeric(args[[3L]])
p <- as.integer(args[[4L]]); replication <- as.integer(args[[5L]])
method <- args[[6L]]; worker <- args[[7L]]; rc <- as.integer(args[[8L]])

msg <- if (rc == 124L) 'timeout' else paste0('exit_', rc)
row <- data.frame(
  setup = setup, tau = tau, p = p, replication = replication, method = method,
  status = 'failed', error = msg, N = NA_integer_, seed = NA_integer_,
  lambda_count = NA_integer_, lambda_best = NA_real_, lambda_index = NA_integer_,
  time_total_path = NA_real_, AEE_l1 = NA_real_, AEE_l2 = NA_real_,
  AEE_linf = NA_real_, alpha_AEE_l1 = NA_real_, SIZE = NA_integer_,
  FP = NA_integer_, FN = NA_integer_, PCF = NA_integer_, SUM = NA_real_,
  selected_iterations = NA_real_, selected_converged = NA,
  path_converged = NA_integer_, package_version = NA_character_,
  stringsAsFactors = FALSE)

out_dir <- file.path(root, 'results')
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_file <- file.path(out_dir, paste0('worker_', worker, '.csv'))
new_file <- !file.exists(out_file)
write.table(row, out_file, sep = ',', row.names = FALSE,
            col.names = new_file, append = !new_file, quote = TRUE)
cat(sprintf('FAIL %s_%02d_p%d_rep%03d_%s %s\n', setup, round(tau * 10), p, replication, method, msg))
