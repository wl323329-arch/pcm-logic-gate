function F = softmin_score(CR_each, tau, lambda_balance)
%SOFTMIN_SCORE Continuous score for logic-state contrast margins.
vals = double(CR_each(:));
vals = vals(isfinite(vals));
if isempty(vals)
    F = -inf;
    return;
end

F = -tau * log(sum(exp(-vals / tau))) - lambda_balance * std(vals);
end
