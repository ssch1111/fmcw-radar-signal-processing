function plot_full_scenario(range_axis, velocity_axis, power_map_db, targets, results_table, save_path, mean_R_err, mean_v_err, mean_th_err)
%PLOT_FULL_SCENARIO Phase 6 summary figure: non-coherent Range-Doppler map with
%ground-truth/detection markers, plus a summary comparison table.
%
%   PLOT_FULL_SCENARIO(range_axis, velocity_axis, power_map_db, targets,
%   results_table, save_path, mean_R_err, mean_v_err, mean_th_err) draws a
%   two-panel figure: (left) the non-coherent Range-Doppler power map (dB,
%   per-element power summed -- see phase6_full_pipeline.m) with white '+'
%   ground-truth markers and red 'o' estimated-detection markers; (right) a
%   text table of True/Est/Error for range, velocity, and angle, one row per
%   target, plus the mean-error summary line the specification asks for.
%
%   The summary table is rendered with `text()` on a plain axes, NOT `uitable`
%   (see docs/engineering_decisions.md decision D20): `uitable` is a UI
%   component, and `exportgraphics` silently omits UI components from its
%   output ("UI components will not be included in the output" warning) --
%   found when a run of the pipeline produced this exact warning, meaning
%   every previously-generated copy of this figure was missing its entire
%   right-hand summary panel. `text()` is a plain graphics object and exports
%   correctly.
%
%   Inputs:
%       range_axis    - 1 x Nrange [m]
%       velocity_axis - 1 x Nchirps [m/s]
%       power_map_db  - Nrange x Nchirps, dB, non-coherent power sum across
%                       receive elements (detection-stage map)
%       targets       - Ntgt x 1 struct array, fields id, R, v, theta_deg
%       results_table - output of associate_detections.m
%       save_path     - output PNG path
%       mean_R_err    - mean range error over detected targets [m]
%       mean_v_err    - mean velocity error over detected targets [m/s]
%       mean_th_err   - mean angle error over detected targets [deg]

    fig = figure('Color', 'w', 'Position', [80 80 1900 700]);

    subplot(1, 2, 1);
    imagesc(velocity_axis, range_axis, power_map_db, [-40 0]);
    set(gca, 'YDir', 'normal'); colorbar; ylabel(colorbar, 'dB');
    xlabel('Velocity (m/s)'); ylabel('Range (m)');
    title({'Non-coherent Range-Doppler Map', '(white + = truth, red o = detection)'}, 'FontWeight', 'bold');
    hold on;
    for k = 1:numel(targets)
        plot(targets(k).v, targets(k).R, 'w+', 'MarkerSize', 12, 'LineWidth', 2);
    end
    for k = 1:numel(results_table)
        if results_table(k).detected
            plot(results_table(k).v_est, results_table(k).R_est, 'ro', ...
                'MarkerSize', 9, 'LineWidth', 1.5);
        end
    end

    subplot(1, 2, 2);
    axis off;
    n = numel(results_table);

    % Table text layout (see docs/engineering_decisions.md decision D20 and its two
    % follow-ups): text() does not wrap or auto-shrink, so a fixed-width monospace
    % block sized by guessing at a character count is fragile -- it depends on the
    % exact font metrics the machine running this script substitutes. Two rounds
    % of manually shortening the format still left the last column clipped. Fixed
    % properly below: the text is drawn once, then its actual rendered extent is
    % measured and the font size is shrunk (if needed) until it provably fits
    % within the axes -- this is correct on any machine/font, not just the one
    % used to eyeball a screenshot.
    header = sprintf('%-4s %7s %7s %7s  %7s %7s %7s  %7s %7s %7s', ...
        'Tgt', 'TrueR', 'EstR', 'Rerr', 'TrueV', 'EstV', 'Verr', 'TrueTh', 'EstTh', 'ThErr');
    rule = repmat('-', 1, length(header));
    row_lines = cell(n, 1);
    for k = 1:n
        r = results_table(k);
        if r.detected
            row_lines{k} = sprintf('%-4s %7.2f %7.3f %7.3f  %7.2f %7.3f %7.3f  %7.2f %7.2f %7.2f', ...
                r.id, r.R_true, r.R_est, r.R_err, r.v_true, r.v_est, r.v_err, ...
                r.theta_true, r.theta_est, r.theta_err);
        else
            row_lines{k} = sprintf('%-4s %7.1f %7s %7s  %7s %7s %7s  %7s %7s %7s', ...
                r.id, r.R_true, 'MISS', '-', '-', '-', '-', '-', '-', '-');
        end
    end
    summary_line = sprintf('Mean (detected): dR=%.4f m  dv=%.4f m/s  d-theta=%.4f deg', ...
        mean_R_err, mean_v_err, mean_th_err);
    table_text = strjoin([{header, rule}, row_lines', {'', summary_line}], newline);

    h_table = text(0.0, 0.95, table_text, 'FontName', 'Courier New', 'FontSize', 10, ...
        'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', 'Units', 'normalized', ...
        'Interpreter', 'none');
    drawnow;
    ext = get(h_table, 'Extent');   % [x y width height], normalized to this axes
    min_font_size = 5;
    while (ext(1) + ext(3) > 1.0) && (get(h_table, 'FontSize') > min_font_size)
        set(h_table, 'FontSize', get(h_table, 'FontSize') - 0.5);
        drawnow;
        ext = get(h_table, 'Extent');
    end
    if ext(1) + ext(3) > 1.0
        warning('plot_full_scenario:tableOverflow', ...
            ['Summary table still exceeds the axes width at the minimum font size ' ...
             '(%.1fpt) -- it may be clipped in the saved figure. Consider widening ' ...
             'the figure in this function.'], min_font_size);
    end
    title('Phase 6 Summary: Ground Truth vs. Estimate (units: m, m/s, deg)', 'FontWeight', 'bold');

    sgtitle('Phase 6 -- Full Multi-Target Pipeline', 'FontWeight', 'bold', 'FontSize', 14);

    exportgraphics(fig, save_path, 'Resolution', 200);
    close(fig);

end
