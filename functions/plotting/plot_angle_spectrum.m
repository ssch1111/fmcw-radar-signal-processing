function plot_angle_spectrum(theta_grid_deg, P_music_a, P_dbf_a, true_a, ...
                              P_music_b, P_dbf_b, true_b, save_path)
%PLOT_ANGLE_SPECTRUM Two-panel MUSIC vs. DBF comparison: (a) single target,
%(b) two closely-spaced targets (resolution differentiator).

    fig = figure('Color', 'w', 'Position', [80 80 1300 480]);

    subplot(1,2,1);
    plot(theta_grid_deg, 10*log10(P_music_a/max(P_music_a)+eps), 'LineWidth', 1.5); hold on;
    plot(theta_grid_deg, 10*log10(P_dbf_a/max(P_dbf_a)+eps), 'LineWidth', 1.5);
    for k = 1:numel(true_a)
        xline(true_a(k), 'r--', 'LineWidth', 1.2);
    end
    grid on; ylim([-40 2]);
    xlabel('Angle (deg)'); ylabel('Normalized spectrum (dB)');
    legend({'MUSIC','Conventional (Bartlett)','True angle'}, 'Location', 'northwest', 'FontSize', 8);
    title(sprintf('(a) Single target at %.0f%s', true_a(1), char(176)), 'FontWeight', 'bold');

    subplot(1,2,2);
    plot(theta_grid_deg, 10*log10(P_music_b/max(P_music_b)+eps), 'LineWidth', 1.5); hold on;
    plot(theta_grid_deg, 10*log10(P_dbf_b/max(P_dbf_b)+eps), 'LineWidth', 1.5);
    for k = 1:numel(true_b)
        xline(true_b(k), 'r--', 'LineWidth', 1.2);
    end
    grid on; ylim([-40 2]);
    xlabel('Angle (deg)'); ylabel('Normalized spectrum (dB)');
    legend({'MUSIC','Conventional (Bartlett)','True angles'}, 'Location', 'northwest', 'FontSize', 8);
    title(sprintf('(b) Two targets %.0f%s apart -- resolution test', abs(true_b(2)-true_b(1)), char(176)), 'FontWeight', 'bold');

    sgtitle('Phase 5 -- Angle Estimation: MUSIC vs. Conventional Beamforming', 'FontWeight', 'bold', 'FontSize', 14);

    exportgraphics(fig, save_path, 'Resolution', 200);
    close(fig);

end
