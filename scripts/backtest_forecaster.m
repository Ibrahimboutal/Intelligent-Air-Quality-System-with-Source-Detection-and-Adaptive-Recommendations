%% backtest_forecaster.m
% Master's Level Enhancement - Phase 4: Forecasting Rigor
%
% This script performs a rigorous backtesting analysis of the Holt-Winters
% forecaster, answering the Master's-level research question:
%   "How does forecast accuracy degrade as the prediction horizon increases?"
%
% NOTE: Local functions hw_update / hw_forecast are defined at the BOTTOM
%       of this file, as required by MATLAB for scripts with local functions.

clear; close all; clc;

% ===========================================================================
% 1. LOAD DATA
% ===========================================================================
logDir = 'logs';
logFiles = dir(fullfile(logDir, '*.csv'));
if isempty(logFiles)
    error('No log files found in %s.', logDir);
end

allData = table();
for i = 1:length(logFiles)
    T = readtable(fullfile(logDir, logFiles(i).name));
    if ismember('PM25', T.Properties.VariableNames)
        allData = [allData; T];
    end
end

pm25 = allData.PM25;
pm25 = pm25(~isnan(pm25));
N    = length(pm25);

if N < 60
    error('Need at least 60 samples for backtesting. Run a longer session.');
end
fprintf('Loaded %d PM2.5 samples for backtesting.\n', N);

% ===========================================================================
% 2. HW HYPERPARAMETERS
% ===========================================================================
horizons = [1, 3, 5, 10, 15];
alpha_hw = 0.5;
beta_hw  = 0.3;
phi_hw   = 0.98;

rmse_per_horizon = zeros(1, length(horizons));
mae_per_horizon  = zeros(1, length(horizons));

% Warm-up: run filter for 20 steps before evaluating
warmup = 20;
L = pm25(1); T_hw = 0;
for k = 2:warmup
    [L, T_hw] = hw_update(pm25(k), L, T_hw, alpha_hw, beta_hw, phi_hw);
end

% ===========================================================================
% 3. MULTI-HORIZON BACKTESTING
% ===========================================================================
fprintf('\n--- Backtesting Results ---\n');
fprintf('%-10s | %-10s | %-10s\n', 'Horizon', 'RMSE', 'MAE');
fprintf('%s\n', repmat('-', 1, 36));

for hi = 1:length(horizons)
    h      = horizons(hi);
    errors = [];
    L_i    = L; T_i = T_hw;

    for k = warmup+1 : N-h+1
        predicted     = hw_forecast(L_i, T_i, phi_hw, h);
        actual        = pm25(k - 1 + h);
        errors(end+1) = predicted - actual; %#ok<AGROW>
        [L_i, T_i]   = hw_update(pm25(k), L_i, T_i, alpha_hw, beta_hw, phi_hw);
    end

    rmse_per_horizon(hi) = sqrt(mean(errors.^2));
    mae_per_horizon(hi)  = mean(abs(errors));
    fprintf('%-10d | %-10.3f | %-10.3f\n', h, rmse_per_horizon(hi), mae_per_horizon(hi));
end

% ===========================================================================
% 4. HYPERPARAMETER SENSITIVITY: alpha vs beta at 15-min horizon
% ===========================================================================
fprintf('\nRunning hyperparameter sensitivity analysis...\n');
alphas    = 0.1:0.1:0.9;
betas     = 0.1:0.1:0.5;
rmse_grid = zeros(length(alphas), length(betas));

for ai = 1:length(alphas)
    for bi = 1:length(betas)
        L_i = pm25(1); T_i = 0;
        for k = 2:warmup
            [L_i, T_i] = hw_update(pm25(k), L_i, T_i, alphas(ai), betas(bi), phi_hw);
        end
        errs = [];
        for k = warmup+1 : N-15+1
            predicted   = hw_forecast(L_i, T_i, phi_hw, 15);
            errs(end+1) = predicted - pm25(k-1+15); %#ok<AGROW>
            [L_i, T_i]  = hw_update(pm25(k), L_i, T_i, alphas(ai), betas(bi), phi_hw);
        end
        rmse_grid(ai, bi) = sqrt(mean(errs.^2));
    end
end

% ===========================================================================
% 5. RESIDUAL AUTOCORRELATION (white noise test)
% ===========================================================================
L_i = pm25(1); T_i = 0;
for k = 2:warmup
    [L_i, T_i] = hw_update(pm25(k), L_i, T_i, alpha_hw, beta_hw, phi_hw);
end
residuals = [];
for k = warmup+1 : N-1
    predicted     = hw_forecast(L_i, T_i, phi_hw, 1);
    residuals(end+1) = pm25(k) - predicted; %#ok<AGROW>
    [L_i, T_i]   = hw_update(pm25(k), L_i, T_i, alpha_hw, beta_hw, phi_hw);
end

% ===========================================================================
% 6. VISUALIZATION
% ===========================================================================
figure('Name', 'Phase 4 - Forecasting Rigor', 'Color', 'w', 'Position', [50, 50, 1100, 850]);

% Panel 1: Error vs Horizon
ax1 = subplot(2, 2, 1);
yyaxis left
plot(horizons, rmse_per_horizon, 'b-o', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', 'b');
ylabel('RMSE (\mug/m^3)', 'Color', 'b');
yyaxis right
plot(horizons, mae_per_horizon, 'r--s', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', 'r');
ylabel('MAE (\mug/m^3)', 'Color', 'r');
xlabel('Forecast Horizon (minutes)');
title('Forecast Error vs. Prediction Horizon', 'FontWeight', 'bold');
legend('RMSE', 'MAE', 'Location', 'northwest');
grid on; xticks(horizons); ax1.XColor = 'k';

% Panel 2: Sensitivity Heatmap
ax2 = subplot(2, 2, 2);
imagesc(betas, alphas, rmse_grid);
colormap(ax2, hot); colorbar;
xlabel('Beta (\beta) - Trend Smoothing');
ylabel('Alpha (\alpha) - Level Smoothing');
title('RMSE Heatmap: \alpha vs \beta (15-min horizon)', 'FontWeight', 'bold');
xticks(betas); yticks(alphas);
hold on;
[~, a_idx] = min(abs(alphas - alpha_hw));
[~, b_idx] = min(abs(betas  - beta_hw));
plot(betas(b_idx), alphas(a_idx), 'g*', 'MarkerSize', 15, 'LineWidth', 2);
legend('Current \alpha,\beta', 'Location', 'best');

% Panel 3: Residual ACF
ax3 = subplot(2, 2, 3);
max_lag = min(30, floor(length(residuals)/4));
[acf_vals, lags, acf_bounds] = autocorr(residuals, 'NumLags', max_lag);
bar(ax3, lags, acf_vals, 'FaceColor', [0.2 0.6 0.8]);
hold on;
yline(acf_bounds(1),  'r--', 'LineWidth', 1.5, 'Label', '95% CI');
yline(-acf_bounds(1), 'r--', 'LineWidth', 1.5);
yline(0, 'k-');
xlabel('Lag'); ylabel('Autocorrelation');
title('Residual ACF: Is Forecast Error White Noise?', 'FontWeight', 'bold');
grid on;
pct_outside = sum(abs(acf_vals(2:end)) > acf_bounds(1)) / max_lag * 100;
text(max_lag*0.5, max(acf_vals)*0.85, ...
    sprintf('%.0f%% lags exceed 95%% CI\n(ideal: <5%%)', pct_outside), ...
    'FontSize', 9, 'BackgroundColor', 'w', 'EdgeColor', 'k');

% Panel 4: Actual vs 15-min Forecast with RMSE band
ax4 = subplot(2, 2, 4);
test_window = min(200, N - warmup - 15);
actual_seg  = pm25(warmup + 15 + 1 : warmup + 15 + test_window);

L_i = pm25(1); T_i = 0;
for k = 2:warmup
    [L_i, T_i] = hw_update(pm25(k), L_i, T_i, alpha_hw, beta_hw, phi_hw);
end
pred_seg = zeros(test_window, 1);
for k = 1:test_window
    pred_seg(k) = hw_forecast(L_i, T_i, phi_hw, 15);
    [L_i, T_i]  = hw_update(pm25(warmup+k), L_i, T_i, alpha_hw, beta_hw, phi_hw);
end

t_seg = 1:test_window;
plot(ax4, t_seg, actual_seg, 'k-',  'LineWidth', 1.5, 'DisplayName', 'Actual PM2.5');
hold on;
plot(ax4, t_seg, pred_seg,   'r--', 'LineWidth', 1.5, 'DisplayName', '15-min Forecast');
fill(ax4, [t_seg, fliplr(t_seg)], ...
    [pred_seg' + rmse_per_horizon(end), fliplr(pred_seg' - rmse_per_horizon(end))], ...
    'r', 'FaceAlpha', 0.1, 'EdgeColor', 'none', 'DisplayName', '\pm RMSE Band');
xlabel('Sample Index'); ylabel('PM2.5 (\mug/m^3)');
title('Actual vs. 15-min Forecast (with RMSE Uncertainty Band)', 'FontWeight', 'bold');
legend('Location', 'best'); grid on;

fprintf('\nPhase 4 (Forecasting Rigor) complete.\n');

% ===========================================================================
% LOCAL FUNCTIONS — must appear at the END of a MATLAB script file
% ===========================================================================
function [level, trend] = hw_update(y, L_prev, T_prev, alpha, beta, phi)
    % One recursive Holt-Winters update step with dampened trend.
    L_new = alpha * y + (1 - alpha) * (L_prev + phi * T_prev);
    T_new = beta * (L_new - L_prev) + (1 - beta) * phi * T_prev;
    level = L_new;
    trend = T_new;
end

function forecast = hw_forecast(L, T, phi, h)
    % Multi-step dampened-trend forecast over horizon h.
    steps    = 1:h;
    forecast = max(0, L + sum(phi .^ steps) * T);
end
