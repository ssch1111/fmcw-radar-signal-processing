function plot_cfar_results(range_axis, velocity_axis, rd_map_db, threshold_db, detections, targets_rd, save_path)
%PLOT_CFAR_RESULTS Three-panel CFAR figure: (a) raw RD map, (b) threshold map,
%(c) detections overlaid on the RD map with ground truth markers.
%
%   targets_rd - N x 2 matrix of [range, velocity] ground-truth targets

    fig = figure('Color', 'w', 'Position', [80 80 1500 480]);

    subplot(1,3,1);
    imagesc(velocity_axis, range_axis, rd_map_db, [-40 0]);
    set(gca, 'YDir', 'normal'); colorbar; ylabel(colorbar, 'dB');
    xlabel('Velocity (m/s)'); ylabel('Range (m)');
    title('(a) Raw Range-Doppler Map', 'FontWeight', 'bold');

    subplot(1,3,2);
    imagesc(velocity_axis, range_axis, threshold_db, [-40 0]);
    set(gca, 'YDir', 'normal'); colorbar; ylabel(colorbar, 'dB (rel.)');
    xlabel('Velocity (m/s)'); ylabel('Range (m)');
    title('(b) CFAR Threshold Map', 'FontWeight', 'bold');

    subplot(1,3,3);
    imagesc(velocity_axis, range_axis, rd_map_db, [-40 0]);
    set(gca, 'YDir', 'normal');
    hold on;
    [r_idx, v_idx] = find(detections);
    plot(velocity_axis(v_idx), range_axis(r_idx), 'ro', 'MarkerSize', 6, 'LineWidth', 1.2);
    plot(targets_rd(:,2), targets_rd(:,1), 'w+', 'MarkerSize', 10, 'LineWidth', 2);
    legend({'CFAR detections', 'Ground truth'}, 'Location', 'northeast', 'FontSize', 8);
    xlabel('Velocity (m/s)'); ylabel('Range (m)');
    title('(c) Detections on RD Map', 'FontWeight', 'bold');

    sgtitle('Phase 4 -- CA-CFAR Detection (2D, Range-Doppler)', 'FontWeight', 'bold', 'FontSize', 14);

    exportgraphics(fig, save_path, 'Resolution', 200);
    close(fig);

end
