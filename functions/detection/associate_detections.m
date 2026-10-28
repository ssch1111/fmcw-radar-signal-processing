function results_table = associate_detections(detections, targets, gate_m)
%ASSOCIATE_DETECTIONS Nearest-range association of pipeline detections to
%ground-truth targets, for validation/reporting only.
%
%   results_table = ASSOCIATE_DETECTIONS(detections, targets, gate_m) matches
%   each ground-truth target in `targets` to the closest not-yet-used detection
%   in `detections` by RANGE (the discriminating dimension in this project's
%   well-separated-range test scenarios; see phase6_full_pipeline.m), accepting
%   the match only if the range difference is below `gate_m`.
%
%   This function is for VALIDATION/REPORTING only -- it uses ground truth to
%   check the pipeline's output and must never feed back into detection or
%   estimation itself.
%
%   Inputs:
%       detections - Ndet x 1 struct array with fields R_est, v_est, theta_est
%       targets    - Ntgt x 1 struct array with fields id, R, v, theta_deg
%       gate_m     - maximum range difference [m] accepted as a valid match
%   Outputs:
%       results_table - Ntgt x 1 struct array with fields:
%           id, R_true, v_true, theta_true, detected (logical), and -- only
%           when detected is true -- R_est, R_err, v_est, v_err, theta_est,
%           theta_err

    Ndet = numel(detections);
    used = false(1, Ndet);

    for k = 1:numel(targets)
        best = -1;
        best_dist = inf;
        for i = 1:Ndet
            if used(i)
                continue;
            end
            dist = abs(detections(i).R_est - targets(k).R);
            if dist < best_dist
                best_dist = dist;
                best = i;
            end
        end

        results_table(k).id = targets(k).id; %#ok<AGROW>
        results_table(k).R_true = targets(k).R; %#ok<AGROW>
        results_table(k).v_true = targets(k).v; %#ok<AGROW>
        results_table(k).theta_true = targets(k).theta_deg; %#ok<AGROW>

        if best > 0 && best_dist < gate_m
            used(best) = true;
            d = detections(best);
            results_table(k).detected = true; %#ok<AGROW>
            results_table(k).R_est = d.R_est; %#ok<AGROW>
            results_table(k).R_err = abs(d.R_est - targets(k).R); %#ok<AGROW>
            results_table(k).v_est = d.v_est; %#ok<AGROW>
            results_table(k).v_err = abs(d.v_est - targets(k).v); %#ok<AGROW>
            results_table(k).theta_est = d.theta_est; %#ok<AGROW>
            results_table(k).theta_err = abs(d.theta_est - targets(k).theta_deg); %#ok<AGROW>
        else
            results_table(k).detected = false; %#ok<AGROW>
            results_table(k).R_est = NaN; %#ok<AGROW>
            results_table(k).R_err = NaN; %#ok<AGROW>
            results_table(k).v_est = NaN; %#ok<AGROW>
            results_table(k).v_err = NaN; %#ok<AGROW>
            results_table(k).theta_est = NaN; %#ok<AGROW>
            results_table(k).theta_err = NaN; %#ok<AGROW>
        end
    end

end
