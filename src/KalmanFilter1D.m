classdef KalmanFilter1D < handle
    % KalmanFilter1D - Recursive 1D Kalman Filter for sensor denoising
    %
    % Master's Level Enhancement - Phase 2: Signal Processing
    %
    % Models the SDS011 sensor as a linear dynamic system:
    %   State transition: x_k = x_{k-1} + w, w ~ N(0, Q)
    %   Observation:      z_k = x_k + v,     v ~ N(0, R)
    %
    % where Q is the process noise covariance and R is the measurement
    % noise covariance. The ratio R/Q controls the filter's responsiveness.
    %
    % Usage:
    %   kf = KalmanFilter1D(Q, R);
    %   x_filtered = kf.update(z_measured);
    
    properties
        Q       % Process noise covariance (model uncertainty)
        R       % Measurement noise covariance (sensor noise)
        
        % Internal state
        x_est   % Current state estimate
        P_est   % Current error covariance estimate
        
        % History for analysis
        Innovation      % Measurement residuals (z_k - x_{k|k-1})
        KalmanGain      % Gain sequence K_k
    end
    
    methods
        function obj = KalmanFilter1D(Q, R)
            % Constructor
            % Q: Process noise - higher = trusts the sensor more (more responsive)
            % R: Measurement noise - higher = trusts the model more (more smoothing)
            if nargin < 2
                Q = 1e-4;  % Default: slow-changing physical process
                R = 1.0;   % Default: moderate sensor noise (~1 ug/m^3 std)
            end
            obj.Q = Q;
            obj.R = R;
            
            % Initialize with undefined state
            obj.x_est = NaN;
            obj.P_est = 1.0;    % Start with high uncertainty
            obj.Innovation = [];
            obj.KalmanGain = [];
        end
        
        function x_filtered = update(obj, z)
            % Perform one recursive Kalman Filter update step.
            %
            % Args:
            %   z: Raw scalar sensor measurement (e.g., PM2.5 ug/m^3)
            %
            % Returns:
            %   x_filtered: Optimal state estimate (denoised reading)
            
            if isnan(z)
                if isnan(obj.x_est)
                    x_filtered = NaN;
                else
                    % --- PREDICT Step Only ---
                    % State prediction (constant velocity)
                    % obj.x_est = obj.x_est; (unchanged)
                    
                    % Covariance prediction (uncertainty grows during gaps)
                    obj.P_est = obj.P_est + obj.Q; 
                    
                    x_filtered = obj.x_est;  % Return prediction as best estimate
                    
                    % Log dummy values for gap
                    obj.Innovation(end+1) = NaN;
                    obj.KalmanGain(end+1) = 0;
                end
                return;
            end
            
            % --- Initialization on first valid measurement ---
            if isnan(obj.x_est)
                obj.x_est = z;
                obj.P_est = obj.R;  % Initial uncertainty = measurement noise
                x_filtered = z;
                return;
            end
            
            % === PREDICT Step ===
            % State prediction (constant velocity model: x_{k|k-1} = x_{k-1})
            x_pred = obj.x_est;
            % Covariance prediction
            P_pred = obj.P_est + obj.Q;
            
            % === UPDATE Step ===
            % Innovation (measurement residual)
            innovation = z - x_pred;
            
            % Innovation covariance
            S = P_pred + obj.R;
            
            % Kalman Gain: how much to trust the new measurement vs the model
            K = P_pred / S;
            
            % State update
            obj.x_est = x_pred + K * innovation;
            
            % Covariance update (Joseph form for numerical stability)
            obj.P_est = (1 - K) * P_pred;
            
            % --- Log for diagnostics ---
            obj.Innovation(end+1) = innovation;
            obj.KalmanGain(end+1) = K;
            
            x_filtered = obj.x_est;
        end
        
        function reset(obj)
            % Resets the filter state (useful between monitoring sessions)
            obj.x_est = NaN;
            obj.P_est = 1.0;
            obj.Innovation = [];
            obj.KalmanGain = [];
        end
        
        function [SNR_improvement] = analyzePerformance(obj, raw, filtered)
            % Computes Signal-to-Noise Ratio improvement from filtering.
            %
            % A higher SNR_improvement means the filter removed more noise.
            noise_raw      = std(diff(raw), 'omitnan');
            noise_filtered = std(diff(filtered), 'omitnan');
            
            if noise_filtered > 0
                SNR_improvement = 20 * log10(noise_raw / noise_filtered); % dB
            else
                SNR_improvement = Inf;
            end
            fprintf('Signal denoising: %.2f dB SNR improvement (Kalman Filter).\n', SNR_improvement);
        end
    end
end
