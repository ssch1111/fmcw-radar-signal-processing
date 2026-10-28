function plot_beat_fft(freq_axis, spectrum_db, f_theory, f_measured, bin_width, save_path)
%PLOT_BEAT_FFT Professional beat-signal FFT plot with theoretical/measured markers.
%
%   Inputs:
%       freq_axis   - 1 x N frequency axis [Hz]
%       spectrum_db - 1 x N magnitude spectrum [dB]
%       f_theory    - theoretical beat frequency [Hz]
%       f_measured  - measured (FFT peak) beat frequency [Hz]
%       bin_width   - FFT bin width [Hz]
%       save_path   - output PNG path, e.g. results/01_beat_signal_fft.png

    fig = figure('Color', 'w', 'Position', [100 100 900 550]);
    plot(freq_axis/1e6, spectrum_db, 'LineWidth', 1.2, 'Color', [0.10 0.30 0.55]);
    hold on;
    xline(f_theory/1e6, '--', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.5);
    plot(f_measured/1e6, interp1(freq_axis, spectrum_db, f_measured), ...
        'v', 'MarkerSize', 9, 'MarkerFaceColor', [0.85 0.33 0.10], 'MarkerEdgeColor', 'k');

    grid on; box on;
    xlabel('Beat Frequency (MHz)', 'FontSize', 12);
    ylabel('Magnitude (dB)', 'FontSize', 12);
    title('Phase 1 -- Beat Signal FFT (Single Stationary Target)', 'FontSize', 13, 'FontWeight', 'bold');
    legend({'Beat signal spectrum', ...
            sprintf('Theoretical f_{beat} = %.4f MHz', f_theory/1e6), ...
            sprintf('Measured peak = %.4f MHz (bin = %.4f MHz)', f_measured/1e6, bin_width/1e6)}, ...
            'Location', 'northeast', 'FontSize', 9);
    set(gca, 'FontSize', 11);
    xlim([0, max(freq_axis)/1e6]);

    exportgraphics(fig, save_path, 'Resolution', 200);
    close(fig);

end
