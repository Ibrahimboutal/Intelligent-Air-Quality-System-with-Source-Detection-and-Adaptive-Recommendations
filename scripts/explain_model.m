%% explain_model.m
% Master's Level Enhancement - Phase 3: Explainability (XAI)
%
% This script answers the key academic question:
%   "WHY does the model classify a reading as Combustion vs. Dust?"
%
% Techniques implemented:
%   1. Global Feature Importance  — which features matter most overall
%   2. Per-Class Contribution     — which features drive each specific source
%   3. Permutation Importance     — model-agnostic importance via shuffling
%   4. Decision Boundary Viz      — 2D projection of the classification space

clear; close all; clc;
addpath(fullfile(fileparts(mfilename('fullpath')), '../src'));

FEATURE_NAMES = {'PM2.5/PM10 Ratio', 'Rate of Change', 'Acceleration', ...
                 'MA-5s', 'MA-15s', 'Volatility (Std)', ...
                 'Skewness', 'Kurtosis'};

% ===========================================================================
% 1. LOAD DATA & TRAIN MODEL
% ===========================================================================
logDir = 'logs';
logFiles = dir(fullfile(logDir, '*.csv'));
if isempty(logFiles)
    error('No log files found in %s.', logDir);
end

allData = table();
for i = 1:length(logFiles)
    T = readtable(fullfile(logDir, logFiles(i).name));
    % Reconstruct Features matrix from CSV-split columns
    featCols = T.Properties.VariableNames(startsWith(T.Properties.VariableNames, 'Features_'));
    if ~isempty(featCols)
        T.Features = T{:, featCols};
        T = removevars(T, featCols);
    end
    % Only merge tables that have the required columns AND compatible width
    if ismember('Features', T.Properties.VariableNames) && ismember('Source', T.Properties.VariableNames) ...
            && (isempty(allData) || width(T) == width(allData))
        allData = [allData; T];
    end
end

validIdx = ~isnan(allData.PM25) & ~strcmp(allData.Source, '');
data     = allData(validIdx, :);
X        = data.Features;
y        = categorical(data.Source);
classes  = categories(y);
numClasses = numel(classes);

fprintf('Loaded %d labeled samples across %d classes.\n', size(X,1), numClasses);

% 80/20 chronological split
splitIdx = floor(0.8 * size(X,1));
X_train = X(1:splitIdx, :);   y_train = y(1:splitIdx);
X_test  = X(splitIdx+1:end,:); y_test  = y(splitIdx+1:end);

fprintf('Training Random Forest for explainability analysis...\n');
numTrees = 100;
B = TreeBagger(numTrees, X_train, y_train, ...
    'Method', 'classification', ...
    'PredictorNames', FEATURE_NAMES, ...
    'OOBPrediction', 'on', ...
    'OOBPredictorImportance', 'on');

% ===========================================================================
% 2. GLOBAL FEATURE IMPORTANCE (Gini Impurity Decrease)
% ===========================================================================
importance = B.OOBPermutedPredictorDeltaError;

% Normalize to [0, 1]
importance_norm = importance / max(importance);
[sorted_imp, sort_idx] = sort(importance_norm, 'descend');
sorted_names = FEATURE_NAMES(sort_idx);

figure('Name', 'Phase 3 - XAI: Feature Importance', 'Color', 'w', 'Position', [50, 50, 1100, 850]);

%% Panel 1: Global Feature Importance
ax1 = subplot(2, 2, 1);
hb = barh(sorted_imp, 'FaceColor', 'flat');
cmap = parula(8);
for i = 1:length(sorted_imp)
    hb.CData(i,:) = cmap(i,:);
end
set(ax1, 'YTick', 1:8, 'YTickLabel', flip(sorted_names));
xlabel('Normalized Importance Score');
title('Global Feature Importance (OOB Permutation)', 'FontWeight', 'bold');
grid on; xlim([0 1.1]);
% Add value labels
for i = 1:length(sorted_imp)
    text(sorted_imp(i) + 0.02, i, sprintf('%.3f', sorted_imp(i)), ...
        'VerticalAlignment', 'middle', 'FontSize', 9);
end

% ===========================================================================
% 3. PER-CLASS FEATURE CONTRIBUTION (Approximated via mean feature value)
% ===========================================================================
ax2 = subplot(2, 2, 2);
class_means = zeros(numClasses, 8);
for c = 1:numClasses
    class_mask = y_train == classes{c};
    if any(class_mask)
        class_means(c,:) = mean(X_train(class_mask,:), 1, 'omitnan');
    end
end

% Normalize per feature for heatmap visualization
class_means_norm = class_means;
for f = 1:8
    col = class_means(:,f);
    rng_f = max(col) - min(col);
    if rng_f > 0
        class_means_norm(:,f) = (col - min(col)) / rng_f;
    end
end

imagesc(class_means_norm);
colormap(ax2, hot);
colorbar;
set(ax2, 'XTick', 1:8, 'XTickLabel', FEATURE_NAMES, 'XTickLabelRotation', 30, ...
         'YTick', 1:numClasses, 'YTickLabel', classes);
title('Per-Class Feature Contribution Heatmap', 'FontWeight', 'bold');
xlabel('Feature'); ylabel('Pollution Source');

% ===========================================================================
% 4. PERMUTATION IMPORTANCE (Model-Agnostic)
% ===========================================================================
ax3 = subplot(2, 2, 3);
y_pred_base = categorical(predict(B, X_test));
base_acc = sum(y_pred_base == y_test) / numel(y_test);

perm_importance = zeros(1, 8);
for f = 1:8
    X_perm = X_test;
    X_perm(:,f) = X_perm(randperm(size(X_perm,1)), f); % Shuffle feature f
    y_pred_perm = categorical(predict(B, X_perm));
    perm_acc = sum(y_pred_perm == y_test) / numel(y_test);
    perm_importance(f) = base_acc - perm_acc; % Drop in accuracy = importance
end

[~, perm_sort_idx] = sort(perm_importance, 'descend');
bar(ax3, perm_importance(perm_sort_idx), 'FaceColor', [0.2 0.5 0.8]);
set(ax3, 'XTick', 1:8, 'XTickLabel', FEATURE_NAMES(perm_sort_idx), ...
    'XTickLabelRotation', 30);
ylabel('Drop in Accuracy (baseline - permuted)');
title('Permutation Feature Importance (Model-Agnostic)', 'FontWeight', 'bold');
yline(0, 'k--'); grid on;

fprintf('\n--- Permutation Importance (Drop in Accuracy) ---\n');
for f = 1:8
    fprintf('  %-25s: %.4f\n', FEATURE_NAMES{perm_sort_idx(f)}, perm_importance(perm_sort_idx(f)));
end
fprintf('  Baseline Accuracy: %.2f%%\n', base_acc * 100);

% ===========================================================================
% 5. 2D DECISION BOUNDARY (Top-2 Features via PCA projection)
% ===========================================================================
ax4 = subplot(2, 2, 4);
[coeff, score_train] = pca(X_train);
score_test  = (X_test - mean(X_train)) * coeff;

% Create a meshgrid in PCA space
x1_range = linspace(min(score_train(:,1))-1, max(score_train(:,1))+1, 80);
x2_range = linspace(min(score_train(:,2))-1, max(score_train(:,2))+1, 80);
[xx, yy] = meshgrid(x1_range, x2_range);
grid_pca = [xx(:), yy(:), zeros(numel(xx), size(X_train,2)-2)];

% Reconstruct approximate original space for prediction
grid_orig = grid_pca * coeff' + mean(X_train);
grid_pred = categorical(predict(B, grid_orig));
grid_num  = double(grid_pred);
contourf(ax4, xx, yy, reshape(grid_num, size(xx)), 'LineColor', 'none');
colormap(ax4, parula(numClasses)); hold(ax4, 'on');

% Overlay test points
colors = lines(numClasses);
for c = 1:numClasses
    idx_c = y_test == classes{c};
    scatter(ax4, score_test(idx_c,1), score_test(idx_c,2), 40, colors(c,:), ...
        'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.5, 'DisplayName', classes{c});
end
title('Decision Boundary (PCA 2D Projection)', 'FontWeight', 'bold');
xlabel('PC1'); ylabel('PC2');
legend('Location', 'best', 'FontSize', 8);
grid on;

% ===========================================================================
% 6. LOCAL INTERPRETABILITY (SHAP VALUES)
% ===========================================================================
fprintf('\nComputing SHAP values for a specific anomaly prediction...\n');

% Find a test sample predicted as an anomaly (not 'Clean' or 'Normal')
anomaly_idx = find(y_pred_base ~= 'Clean' & y_pred_base ~= 'Normal', 1);
if isempty(anomaly_idx)
    anomaly_idx = 1; % Fallback
end

queryPoint = X_test(anomaly_idx, :);
predictedClass = string(y_pred_base(anomaly_idx));

try
    % Use MATLAB's built-in shapley function (requires R2022b+)
    % TreeBagger might need a custom wrapper for probabilities, but we will try directly
    explainer = shapley(B, X_train, 'QueryPoint', queryPoint);
    
    figure('Name', 'Phase 3 - XAI: Local SHAP Explanation', 'Color', 'w', 'Position', [100, 100, 800, 500]);
    plot(explainer);
    title(sprintf('SHAP Explanation for Detected "%s" Event', predictedClass), 'FontWeight', 'bold');
    
    fprintf('Local SHAP explanation generated for a "%s" prediction.\n', predictedClass);
    
catch ME
    fprintf('Note: Could not generate SHAP values via built-in function (requires newer MATLAB version).\n');
    fprintf('Error: %s\n', ME.message);
    
    % Fallback: Simple heuristic breakdown based on feature deviation from mean
    fprintf('Falling back to Z-score deviation breakdown...\n');
    global_mean = mean(X_train, 1, 'omitnan');
    
    deviation = abs(queryPoint - global_mean);
    total_dev = sum(deviation);
    if total_dev == 0, total_dev = 1; end
    
    fprintf('\n--- Local Feature Breakdown for Alert: %s ---\n', predictedClass);
    for f = 1:8
        pct = (deviation(f) / total_dev) * 100;
        if pct > 10
            fprintf('  %.1f%% driven by %s\n', pct, FEATURE_NAMES{f});
        end
    end
end

fprintf('\nPhase 3 (XAI) complete.\n');
