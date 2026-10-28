function y = apply_window(x, dim, window_type)
%APPLY_WINDOW Apply a 1-D window along one dimension of a (possibly 2-D) signal.
%
%   y = APPLY_WINDOW(x, dim, window_type) multiplies x by a window function of
%   type `window_type` (e.g. 'hamming') along dimension `dim`.
%
%   Rationale (decision D15): Phases 1-3 deliberately use NO window (rectangular),
%   since their verification is about peak LOCATION accuracy, which windowing does
%   not improve and which benefits from the simplest possible model. Phase 4's
%   CFAR stage is different: it was found, by executing the pipeline on a
%   multi-target scene, that unwindowed rectangular-FFT sidelobes from a strong
%   target create many spurious CFAR detections along that target's entire
%   range/Doppler row and column (slow ~1/n sidelobe rolloff) -- see
%   docs/engineering_decisions.md. Windowing suppresses this at the cost of a
%   slightly widened mainlobe (marginally coarser resolution), a standard and
%   explicit trade-off in real radar signal processing.
%
%   Inputs:
%       x           - input matrix
%       dim         - dimension to window along (1 or 2)
%       window_type - currently supports 'hamming' (uses base MATLAB's hamming
%                     if Signal Processing Toolbox is unavailable, a manual
%                     fallback formula is used so this function has no hard
%                     toolbox dependency)
%   Outputs:
%       y - x with the window applied along `dim`

    N = size(x, dim);
    if exist('hamming', 'file') == 2
        w = hamming(N);
    else
        n = (0:N-1)';
        w = 0.54 - 0.46*cos(2*pi*n/(N-1));   % manual Hamming window, no toolbox dependency
    end

    shape = ones(1, ndims(x));
    shape(dim) = N;
    w = reshape(w, shape);

    y = x .* w;

end
