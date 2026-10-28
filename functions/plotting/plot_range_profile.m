function plot_range_profile(range_axis, profiles_db, true_ranges, labels, save_path)
%PLOT_RANGE_PROFILE Professional multi-target range profile plot.
%
%   Inputs:
%       range_axis  - 1 x N range axis [m]
%       profiles_db - cell array of 1 x N magnitude profiles [dB], one per test case
%       true_ranges - vector of injected ranges [m], one per test case
%       labels      - cell array of legend strings, one per test case
%       save_path   - output PNG path

    fig = figure('Color', 'w', 'Position', [100 100 950 550]);
    colors = lines(numel(profiles_db));
    hold on;
    for i = 1:numel(profiles_db)
        plot(range_axis, profiles_db{i}, 'LineWidth', 1.3, 'Color', colors(i,:));
        xline(true_ranges(i), '--', 'Color', colors(i,:)*0.6, 'LineWidth', 1.0, 'HandleVisibility','off');
    end
    grid on; box on;
    xlabel('Range (m)', 'FontSize', 12);
    ylabel('Magnitude (dB)', 'FontSize', 12);
    title('Phase 2 -- Range Profile (Multiple Targets, AWGN)', 'FontSize', 13, 'FontWeight', 'bold');
    legend(labels, 'Location', 'northeast', 'FontSize', 9);
    set(gca, 'FontSize', 11);
    xlim([0, max(range_axis)]);

    exportgraphics(fig, save_path, 'Resolution', 200);
    close(fig);

end
