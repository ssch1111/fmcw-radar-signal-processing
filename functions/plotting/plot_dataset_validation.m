function plot_dataset_validation(range_axis, velocity_axis, power_map_db, det_r, det_d, save_path, title_lines)
%PLOT_DATASET_VALIDATION Phase 7 (and 7b) real-data validation figure.
%
%   PLOT_DATASET_VALIDATION(range_axis, velocity_axis, power_map_db, det_r,
%   det_d, save_path) draws the non-coherent Range-Doppler power map (dB)
%   computed from REAL RaDICaL dataset ADC samples via this project's own
%   range_fft.m/doppler_fft.m, with CFAR detections overlaid.
%
%   UNLIKE every synthetic-scenario figure in this project (Phases 1-6), there
%   is NO ground-truth marker here -- real recorded data has no exactly-known
%   target state to plot against (see src/phase7_dataset_validation.m header).
%   The title says so explicitly, so this figure cannot be mistaken for a
%   synthetic-validation result at a glance.
%
%   Inputs:
%       range_axis, velocity_axis - from range_fft.m / doppler_fft.m
%       power_map_db              - dB, non-coherent power sum across elements
%       det_r, det_d               - CFAR/cluster detection bin indices (may be empty)
%       save_path                  - output PNG path
%       title_lines                - OPTIONAL cell array of title line strings (decision
%                                     D24). When omitted, defaults to the original Phase 7
%                                     title exactly as before -- src/phase7_dataset_validation.m's
%                                     call site and output are completely unchanged by this
%                                     addition. Added so src/phase7b_dataset_validation_mti_cfar.m
%                                     (which reuses this function unmodified otherwise) can label
%                                     its figure correctly instead of showing a leftover "Phase 7"
%                                     title on a Phase 7b result -- found by independent review,
%                                     not by this project's own execution; see decision D24.

    if nargin < 7 || isempty(title_lines)
        title_lines = {'Phase 7 -- REAL-DATA Validation (RaDICaL dataset, indoor recording)', ...
           'NOTE: no ground-truth marker -- real data has no exactly-known target state ' ...
           '(see docs/dataset_notes.md)'};
    end

    fig = figure('Color', 'w', 'Position', [80 80 900 650]);

    imagesc(velocity_axis, range_axis, power_map_db, [-40 0]);
    set(gca, 'YDir', 'normal'); colorbar; ylabel(colorbar, 'dB');
    xlabel('Velocity (m/s)'); ylabel('Range (m)');
    hold on;
    if ~isempty(det_r)
        plot(velocity_axis(det_d), range_axis(det_r), 'ro', 'MarkerSize', 9, 'LineWidth', 1.5);
        legend({'CFAR detection (real data)'}, 'Location', 'northeast', 'FontSize', 8);
    end
    title(title_lines, 'FontWeight', 'bold', 'FontSize', 10);

    exportgraphics(fig, save_path, 'Resolution', 200);
    close(fig);

end
