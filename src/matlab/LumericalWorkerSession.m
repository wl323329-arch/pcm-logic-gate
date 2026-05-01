classdef LumericalWorkerSession < handle
    properties
        h = []
        last_bits = []
        matA = ''
        matB = ''
    end

    methods
        function obj = LumericalWorkerSession(sim_file, lum_bin, lum_api, matA, matB, d)
            setenv('PATH', append_path_once(getenv('PATH'), lum_bin));
            addpath(lum_api);
            addpath(fileparts(mfilename('fullpath')));

            obj.matA = matA;
            obj.matB = matB;
            obj.last_bits = nan(d, 1);

            obj.h = open_lumerical_mode(sim_file);
        end

        function delete(obj)
            if ~isempty(obj.h)
                try
                    appclose(obj.h);
                catch
                end
                obj.h = [];
            end
        end

        function result = evalParticle(obj, L, train_data, train_target, size_train, size_target, tau, lambda_balance, full_eval)
            t_eval = tic;
            early_stopped = false;
            obj.doIncrementalSet(L);

            p = zeros(size_target);
            eps_val = 1e-30;
            CR_each = nan(size_train(1), 1);
            correct_vec = false(size_train(1), 1);

            for tt = 1:size_train(1)
                phs = train_data(tt,:) * 180/pi;
                p(tt,:) = train_out(obj.h, phs);

                if train_target(tt,1) > train_target(tt,2)
                    P_right = abs(p(tt,1));
                    P_wrong = abs(p(tt,2));
                else
                    P_right = abs(p(tt,2));
                    P_wrong = abs(p(tt,1));
                end
                CR_each(tt) = 10 * log10((P_right + eps_val) / (P_wrong + eps_val));
                correct_vec(tt) = (p(tt,1) > p(tt,2)) == (train_target(tt,1) > train_target(tt,2));

                correct_so_far = sum(double(correct_vec(1:tt)));
                if ~full_eval && tt - correct_so_far > 0
                    early_stopped = true;
                    nr = correct_so_far;
                    crw = min(CR_each(1:tt));
                    [~, worst_idx] = min(CR_each(1:tt));
                    F_soft = -inf;
                    p(tt+1:end,:) = NaN;
                    p_clean = p;
                    p_clean(isnan(p_clean)) = 0;
                    p_norm = p_clean / (max(p_clean, [], "all") + eps_val);
                    lmse = sumsqr(p_norm - train_target);
                    result = make_eval_result(nr, crw, lmse, CR_each, F_soft, ...
                        worst_idx, false, false, early_stopped, toc(t_eval));
                    return;
                end
            end

            nr = sum(double(correct_vec));
            crw = min(CR_each);
            [~, worst_idx] = min(CR_each);
            F_soft = softmin_score(CR_each, tau, lambda_balance);
            p_norm = p / (max(p, [], "all") + eps_val);
            lmse = sumsqr(p_norm - train_target);

            result = make_eval_result(nr, crw, lmse, CR_each, F_soft, ...
                worst_idx, true, false, early_stopped, toc(t_eval));
        end
    end

    methods (Access = private)
        function doIncrementalSet(obj, L)
            cur_bits = L(:);
            if any(isnan(obj.last_bits))
                set_slot(obj.h, cur_bits);
            else
                changed_idx = find(cur_bits ~= obj.last_bits);
                if ~isempty(changed_idx)
                    commands = cell(1, numel(changed_idx) + 1);
                    commands{1} = 'switchtolayout;';
                    for ci = 1:length(changed_idx)
                        idx_i = changed_idx(ci);
                        name = ['gra', num2str(idx_i)];
                        if cur_bits(idx_i) == 0
                            mat_name = obj.matA;
                        else
                            mat_name = obj.matB;
                        end
                        commands{ci + 1} = ['select("', name, '");', ...
                            'set("material","', mat_name, '");'];
                    end
                    appevalscript(obj.h, [commands{:}]);
                end
            end
            obj.last_bits = cur_bits;
        end
    end
end
