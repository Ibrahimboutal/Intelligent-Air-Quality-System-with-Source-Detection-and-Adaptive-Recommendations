classdef IsolationForestAD < handle
    % IsolationForestAD - Isolation Forest Anomaly Detector
    %
    % Master's Level Enhancement - Phase 5: Unsupervised Learning
    %
    % The Isolation Forest algorithm detects anomalies by isolating observations
    % via random recursive partitioning. Anomalous points are isolated faster
    % (shorter average path length) than normal points.
    %
    % Reference: Liu, F.T., Ting, K.M. & Zhou, Z.H. (2008).
    %   "Isolation Forest." IEEE ICDM. DOI: 10.1109/ICDM.2008.17
    %
    % Usage:
    %   iforest = IsolationForestAD(numTrees, subSampleSize);
    %   iforest.fit(X_train);           % Unsupervised fit on clean data
    %   scores = iforest.score(X_test); % Anomaly scores in [0,1]
    %   labels = iforest.predict(X_test, threshold); % 1=anomaly, 0=normal

    properties
        NumTrees        % Number of isolation trees
        SubSampleSize   % Sub-sample size per tree (default 256)
        Trees           % Cell array of trained isolation trees
        NFitted         % Number of samples used in training
        Threshold       % Decision boundary (default 0.5 score)
        FeatureMins     % Min of each feature (for normalization)
        FeatureMaxs     % Max of each feature
    end

    methods
        function obj = IsolationForestAD(numTrees, subSampleSize)
            if nargin < 1, numTrees      = 100; end
            if nargin < 2, subSampleSize = 256;  end
            obj.NumTrees      = numTrees;
            obj.SubSampleSize = subSampleSize;
            obj.Trees         = {};
            obj.Threshold     = 0.5;
        end

        function fit(obj, X)
            % Fit the Isolation Forest on training data X (n_samples x n_features).
            % X should represent "normal" / expected sensor behavior.
            n = size(X, 1);
            obj.NFitted = n;
            obj.FeatureMins = min(X);
            obj.FeatureMaxs = max(X);
            obj.Trees = cell(obj.NumTrees, 1);

            psi = min(obj.SubSampleSize, n);   % effective sub-sample size
            hlim = ceil(log2(psi));             % height limit

            fprintf('Fitting Isolation Forest: %d trees, sub-sample=%d...\n', ...
                obj.NumTrees, psi);
            for t = 1:obj.NumTrees
                % Draw a random sub-sample (without replacement)
                idx = randperm(n, psi);
                obj.Trees{t} = obj.buildTree(X(idx, :), 0, hlim);
            end
            fprintf('Isolation Forest fitted successfully.\n');
        end

        function scores = score(obj, X)
            % Compute anomaly scores for each row of X.
            % Score in (0,1]: closer to 1 = more anomalous.
            n = size(X, 1);
            path_lengths = zeros(n, obj.NumTrees);

            for t = 1:obj.NumTrees
                for i = 1:n
                    path_lengths(i, t) = obj.pathLength(X(i,:), obj.Trees{t}, 0);
                end
            end

            avg_path = mean(path_lengths, 2);
            psi = min(obj.SubSampleSize, obj.NFitted);
            c_psi = obj.expectedPathLength(psi);

            % Anomaly score: s(x,n) = 2^(-avg_h(x)/c(n))
            scores = 2 .^ (-avg_path / c_psi);
        end

        function labels = predict(obj, X, threshold)
            % Predict anomaly labels (1 = anomaly, 0 = normal).
            if nargin < 3, threshold = obj.Threshold; end
            s = obj.score(X);
            labels = s > threshold;
        end

        function plotScores(obj, scores, y_true_labels, title_str)
            % Visualize anomaly scores with ground-truth labels overlay.
            if nargin < 3, y_true_labels = []; end
            if nargin < 4, title_str = 'Isolation Forest Anomaly Scores'; end

            figure('Color', 'w', 'Name', title_str);
            n = length(scores);
            t = 1:n;

            area(t, scores, 'FaceColor', [0.8 0.9 1.0], 'EdgeColor', 'b', ...
                'LineWidth', 1, 'DisplayName', 'Anomaly Score');
            hold on;
            yline(obj.Threshold, 'r--', 'LineWidth', 2, ...
                'Label', sprintf('Threshold = %.2f', obj.Threshold));

            % Overlay true anomaly labels if provided
            if ~isempty(y_true_labels)
                anom_idx = find(y_true_labels == 1);
                scatter(anom_idx, scores(anom_idx), 60, 'r', 'filled', ...
                    'MarkerEdgeColor', 'k', 'DisplayName', 'True Anomaly');
            end

            detected_idx = find(scores > obj.Threshold);
            scatter(detected_idx, scores(detected_idx), 40, 'm', '^', ...
                'DisplayName', 'Detected Anomaly');

            xlabel('Sample Index'); ylabel('Anomaly Score');
            title(title_str, 'FontWeight', 'bold');
            legend('Location', 'best'); grid on;
            ylim([0 1.05]);
        end
    end

    methods (Access = private)
        function node = buildTree(obj, X, depth, hlim)
            % Recursively build a single isolation tree.
            n = size(X, 1);
            node = struct('isLeaf', true, 'size', n, 'splitFeature', [], ...
                          'splitValue', [], 'left', [], 'right', []);

            % Termination conditions
            if depth >= hlim || n <= 1
                return;
            end

            nFeatures = size(X, 2);
            % Pick a random feature with non-zero range
            valid_features = [];
            for f = 1:nFeatures
                if max(X(:,f)) > min(X(:,f))
                    valid_features(end+1) = f;
                end
            end

            if isempty(valid_features)
                return;  % All features are constant — cannot split
            end

            q = valid_features(randi(length(valid_features)));
            p = min(X(:,q)) + rand() * (max(X(:,q)) - min(X(:,q)));

            left_mask  = X(:,q) < p;
            right_mask = ~left_mask;

            node.isLeaf       = false;
            node.splitFeature = q;
            node.splitValue   = p;
            node.left  = obj.buildTree(X(left_mask, :),  depth+1, hlim);
            node.right = obj.buildTree(X(right_mask, :), depth+1, hlim);
        end

        function h = pathLength(~, x, node, current_depth)
            % Calculate path length of point x through a tree.
            if node.isLeaf
                % Add adjustment for unresolved instances at leaf
                h = current_depth + IsolationForestAD.expectedPathLength(node.size);
                return;
            end
            if x(node.splitFeature) < node.splitValue
                h = pathLength([], x, node.left,  current_depth + 1);
            else
                h = pathLength([], x, node.right, current_depth + 1);
            end
        end
    end

    methods (Static)
        function c = expectedPathLength(n)
            % Expected path length of an unsuccessful binary search tree.
            % c(n) = 2*H(n-1) - (2*(n-1)/n), where H is harmonic number.
            if n <= 1
                c = 0;
            elseif n == 2
                c = 1;
            else
                H = log(n - 1) + 0.5772156649;  % Euler-Mascheroni constant
                c = 2 * H - (2 * (n-1) / n);
            end
        end
    end
end
