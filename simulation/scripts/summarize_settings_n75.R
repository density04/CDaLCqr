args <- commandArgs(trailingOnly = TRUE)
root <- args[[1L]]
f <- list.files(file.path(root, 'results'), '\\.csv$', full.names = TRUE)
if (!length(f)) { cat('no results yet\n'); quit(save = 'no') }
d <- do.call(rbind, lapply(f, function(x) tryCatch(read.csv(x, stringsAsFactors = FALSE),
                                                   error = function(e) NULL)))
if (is.null(d) || !nrow(d)) { cat('no rows\n'); quit(save = 'no') }
d$key <- paste(d$setup, d$tau, d$p, d$replication, d$method)
d <- d[order(d$status != 'ok'), ]
d <- d[!duplicated(d$key), ]
ok <- d[d$status == 'ok', ]
cat('rows', nrow(d), 'ok', nrow(ok), 'failed', sum(d$status == 'failed'), '\n')
if (nrow(ok)) {
  m <- aggregate(cbind(AEE_l1, SIZE, FN, FP, PCF, time_total_path) ~ setup + tau + p + method,
                 ok, function(x) mean(x, na.rm = TRUE))
  n <- aggregate(replication ~ setup + tau + p + method, ok,
                 function(x) length(unique(x)))
  names(n)[[5L]] <- 'n_ok'
  m <- merge(m, n, by = c('setup', 'tau', 'p', 'method'))
  rep_dir <- file.path(root, 'report'); dir.create(rep_dir, showWarnings = FALSE)
  write.csv(m, file.path(rep_dir, 'setting_summary.csv'), row.names = FALSE)
  sk <- unique(m[, c('setup', 'tau', 'p')])
  sk <- sk[order(sk$p, sk$setup, sk$tau), ]
  lines <- character(nrow(sk))
  for (i in seq_len(nrow(sk))) {
    s <- sk[i, ]
    cur <- m[m$setup == s$setup & m$tau == s$tau & m$p == s$p, ]
    aee <- cur$AEE_l1; names(aee) <- cur$method
    pcf <- cur$PCF; names(pcf) <- cur$method
    lines[[i]] <- sprintf('%s tau=%.1f p=%d n=%d | AEE %s | PCF %s',
                          s$setup, s$tau, s$p, max(cur$n_ok),
                          paste(sprintf('%s=%.3f', names(aee), aee), collapse = ' '),
                          paste(sprintf('%s=%.2f', names(pcf), pcf), collapse = ' '))
  }
  writeLines(lines, file.path(rep_dir, 'overview.txt'))
  cat('settings in report:', nrow(sk), '\n')
}
