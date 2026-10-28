function plot_range_doppler_map(range_axis, velocity_axis, rd_map_db, ground_truth, save_path)
%PLOT_RANGE_DOPPLER_MAP Professional Range-Doppler map plot.
%
%   Inputs:
%       range_axis    - 1 x Nrange [m]
%       velocity_axis - 1 x Nchirps [m/s]
%       rd_map_db     - Nrange x Nchirps magnitude [dB], already normalized
%       ground_truth  - struct with fields .range, .velocity (for the marker)
%       save_path     - output PNG path

    fig = figure('Color', 'w', 'Position', [100 100 950 620]);
    imagesc(velocity_axis, range_axis, rd_map_db, [-40 0]);
    set(gca, 'YDir', 'normal');
    axis([velocity_axis(1) velocity_axis(end) 0 range_axis(end)]);
    colormap(gca, 'parula');
    cb = colorbar;
    ylabel(cb, 'Magnitude (dB)', 'FontSize', 11);

    hold on;
    plot(ground_truth.velocity, ground_truth.range, 'rx', 'MarkerSize', 12, 'LineWidth', 2);
    legend({'Ground truth'}, 'Location', 'northeast');

    xlabel('Velocity (m/s)', 'FontSize', 12);
    ylabel('Range (m)', 'FontSize', 12);
    title(sprintf('Phase 3 -- Range-Doppler Map (target at %.1f m, %+.1f m/s)', ...
        ground_truth.range, ground_truth.velocity), 'FontSize', 13, 'FontWeight', 'bold');
    set(gca, 'FontSize', 11);

    exportgraphics(fig, save_path, 'Resolution', 200);
    close(fig);

end
