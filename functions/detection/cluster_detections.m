function [det_r, det_d] = cluster_detections(det_map, power_map, radius)
%CLUSTER_DETECTIONS Group adjacent CFAR-flagged cells into single detections.
%
%   [det_r, det_d] = CLUSTER_DETECTIONS(det_map, power_map, radius) groups the
%   logical detection map `det_map` (output of ca_cfar_2d) into connected
%   clusters of flagged cells and returns one (range_idx, doppler_idx) pair per
%   cluster: the cell with the largest value in `power_map` within that cluster.
%
%   RATIONALE: a single physical target's mainlobe (plus any residual sidelobe
%   energy CA-CFAR still flags near it, see decision D15 in
%   docs/engineering_decisions.md) can trip CFAR in more than one adjacent Range-Doppler
%   cell. Without clustering, one target would be double-counted as multiple
%   detections in Phase 6's summary table. This uses a simple flood-fill
%   (breadth-first search) over cells that are BOTH flagged by CFAR and within
%   `radius` bins of an already-clustered flagged cell -- i.e. connectivity is
%   defined only through other detected cells, not through the whole grid.
%
%   Inputs:
%       det_map   - Nrange x Ndoppler logical CFAR detection map
%       power_map - Nrange x Ndoppler power map used to pick each cluster's peak
%                   (same size as det_map; typically the non-coherent power sum
%                   used for detection, per decision in phase6_full_pipeline.m)
%       radius    - integer bin radius defining adjacency (default 2)
%   Outputs:
%       det_r - Ndet x 1 range-bin indices, one per cluster (peak-power cell)
%       det_d - Ndet x 1 Doppler-bin indices, one per cluster (peak-power cell)

    if nargin < 3
        radius = 2;
    end

    [Nr, Nd] = size(det_map);
    [rr, cc] = find(det_map);

    visited = false(Nr, Nd);
    det_r = zeros(0, 1);
    det_d = zeros(0, 1);

    for i = 1:numel(rr)
        r0 = rr(i); d0 = cc(i);
        if visited(r0, d0)
            continue;
        end

        % Breadth-first flood-fill over detected cells within `radius` bins
        stack = [r0, d0];
        visited(r0, d0) = true;
        cluster = [r0, d0];

        while ~isempty(stack)
            cur = stack(end, :);
            stack(end, :) = [];
            for dr = -radius:radius
                for dd = -radius:radius
                    nr = cur(1) + dr;
                    nd = cur(2) + dd;
                    if nr < 1 || nr > Nr || nd < 1 || nd > Nd
                        continue;
                    end
                    if det_map(nr, nd) && ~visited(nr, nd)
                        visited(nr, nd) = true;
                        stack(end+1, :) = [nr, nd]; %#ok<AGROW>
                        cluster(end+1, :) = [nr, nd]; %#ok<AGROW>
                    end
                end
            end
        end

        lin_idx = sub2ind([Nr, Nd], cluster(:,1), cluster(:,2));
        [~, pk] = max(power_map(lin_idx));
        det_r(end+1, 1) = cluster(pk, 1); %#ok<AGROW>
        det_d(end+1, 1) = cluster(pk, 2); %#ok<AGROW>
    end

end
