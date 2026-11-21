args <- commandArgs(trailingOnly = TRUE)
root <- args[[1L]]
Q <- file.path(root, 'queue'); RQ <- file.path(root, 'req')
AS <- file.path(root, 'assign'); FD <- file.path(root, 'feed'); DN <- file.path(root, 'done')
ST <- file.path(root, 'start')
for (d in c(Q, RQ, AS, FD, DN, ST)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
ids <- sort(sub('\\.task$', '', list.files(Q, '\\.task$')))
cat(sprintf('%s COORD START ids=%d\n', format(Sys.time()), length(ids)))
ptr <- 1L; last_scan <- Sys.time(); last_sweep <- Sys.time(); assigned_n <- 0L
next_id <- function() {
  while (ptr <= length(ids)) {
    cand <- ids[[ptr]]
    ok <- !file.exists(file.path(AS, cand)) && !file.exists(file.path(DN, cand))
    ptr <<- ptr + 1L
    if (ok) return(cand)
  }
  NA_character_
}
while (TRUE) {
  reqs <- list.files(RQ)
  if (length(reqs)) {
    for (r in reqs) {
      wid <- sub('__.*$', '', r)
      id <- next_id()
      if (is.na(id)) {
        cat('DONE\n', file = file.path(FD, paste0(wid, '.DONE')), append = TRUE)
      } else {
        cat(wid, '\n', sep = '', file = file.path(AS, id))
        cat(id, '\n', sep = '', file = file.path(FD, wid), append = TRUE)
        assigned_n <- assigned_n + 1L
        if (assigned_n %% 250L == 0L) cat(sprintf('%s assigned=%d ptr=%d\n', format(Sys.time()), assigned_n, ptr))
      }
      unlink(file.path(RQ, r))
    }
  }
  now <- Sys.time()
  if (difftime(now, last_scan, units = 'secs') > 60) {
    last_scan <- now
    new_ids <- sort(sub('\\.task$', '', list.files(Q, '\\.task$')))
    add <- setdiff(new_ids, ids)
    if (length(add)) { ids <- c(ids, add); cat('queued_added', length(add), '\n') }
  }
  if (difftime(now, last_sweep, units = 'secs') > 120) {
    last_sweep <- now
    for (a in list.files(AS)) {
      if (file.exists(file.path(DN, a))) { unlink(file.path(AS, a)); next }
      fi <- file.info(file.path(AS, a))
      if (is.na(fi$mtime[[1L]])) next
      age <- as.numeric(difftime(now, fi$mtime[[1L]], units = 'secs'))
      started <- file.exists(file.path(ST, a))
      if ((!started && age > 600) || (started && age > 18000)) {
        unlink(file.path(AS, a)); unlink(file.path(ST, a))
        cat('requeued', a, '\n')
      }
    }
  }
  Sys.sleep(0.2)
}
