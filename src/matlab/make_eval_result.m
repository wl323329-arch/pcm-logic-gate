function result = make_eval_result(nr, crw, lmse, CR_each, F_soft, worst_idx, is_full, cache_hit, early_stopped, duration_sec)
%MAKE_EVAL_RESULT Standard result struct for cached and worker evaluations.
result = struct();
result.n_right = nr;
result.CR_worst = crw;
result.loss_mse = lmse;
result.CR_each = CR_each(:);
result.F_soft = F_soft;
result.worst_idx = worst_idx;
result.is_full = is_full;
result.cache_hit = cache_hit;
result.early_stopped = early_stopped;
result.duration_sec = duration_sec;
end
