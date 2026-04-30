# Intelligent Air Quality System with Source Detection
[![Tests](https://github.com/Ibrahimboutal/Intelligent-Air-Quality-System-with-Source-Detection-and-Adaptive-Recommendations/actions/workflows/ci.yml/badge.svg)](https://github.com/Ibrahimboutal/Intelligent-Air-Quality-System-with-Source-Detection-and-Adaptive-Recommendations/actions/workflows/ci.yml)
![MATLAB](https://img.shields.io/badge/MATLAB-R2023a+-blue.svg)
![Raspberry Pi](https://img.shields.io/badge/Raspberry_Pi-Supported-red.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
[![codecov](https://codecov.io/gh/Ibrahimboutal/Intelligent-Air-Quality-System-with-Source-Detection-and-Adaptive-Recommendations/branch/main/graph/badge.svg)](https://codecov.io/gh/Ibrahimboutal/Intelligent-Air-Quality-System-with-Source-Detection-and-Adaptive-Recommendations)

A professional-grade, distributed air quality monitoring system implementing a full **Master's level data science pipeline** — from real-time sensor denoising and supervised classification to unsupervised novelty detection and rigorous statistical validation.

---

## 🌟 Research Highlights

*   **Zero-Latency Telemetry:** High-performance TCP socket link ($<1ms$ latency) with **Exponential Backoff** resilience.
*   **Bayesian Signal Denoising:** Recursive **Kalman Filter** removes sensor noise with robust **NaN-gap bridging** logic.
*   **Temporal Feature Engineering:** **8D Feature Vector** including Acceleration (2nd derivative) to differentiate leaks from ambient buildup.
*   **Leakage-Free Validation:** Strict **Time-Series Expanding-Window Cross-Validation** prevents future-data leakage.
*   **Advanced Evaluation:** Macro-averaged F1-Scores and **Precision-Recall (PR) Curves** for imbalanced hazardous events.
*   **Explainable AI (XAI):** Permutation importance, per-class heatmaps, and local **SHAP breakdown** for specific alerts.
*   **Rigorous Forecasting:** Holt-Winters backtesting with **strict causality verification** (fixed offset leakage).
*   **Unsupervised Novelty Detection:** From-scratch **Isolation Forest** (normalized multi-pollutant scaling) for zero-day event detection.

---

## ⚙️ System Architecture

The system utilizes a **"Thin-Edge / Heavy-Brain"** distributed architecture:

```mermaid
flowchart TD
    subgraph "Edge Layer (Raspberry Pi)"
        A[SDS011 Laser Sensor] -->|Serial| B[Python Edge Service]
        B -->|Persistent| C[(SQLite Database)]
        B -->|Real-Time| D{TCP Socket Client}
    end

    subgraph "Intelligence Layer (MATLAB)"
        D -->|JSON Stream| E[Intelligence Hub]
        E --> KF["Kalman Filter (Phase 2: NaN-Resilient)"]
        KF --> F[8D Feature Extraction (Phase 1: +Acceleration)]
        F --> G["Random Forest Classifier (Phase 1 & 3)"]
        F --> IF["Isolation Forest (Phase 5: Scaled)"]
        E --> H["Recursive HW Forecaster (Phase 4: Causality-Fixed)"]
        G --> I["Adaptive Logic (Dynamic Thresholding)"]
        IF --> I
        H --> I
        I --> J[Live Dashboard]
    end

    subgraph "Offline Analysis Pipeline"
        C -.->|logs/*.csv| P1["Phase 1: Statistical Validation"]
        C -.->|logs/*.csv| P3["Phase 3: XAI Explainability"]
        C -.->|logs/*.csv| P4["Phase 4: Forecast Backtesting"]
        C -.->|logs/*.csv| P5["Phase 5: Novelty Detection"]
    end
```






---

## 🛠️ Scientific Modules

### 1. Edge Data Acquisition (Python)
The `scripts/air_quality_monitor.py` service runs as a `systemd` daemon. It handles:
*   **Hardware Sync:** Robust frame-parsing of SDS011 laser sensor packets.
*   **Fail-Safe Buffering:** "Hold-Last-Valid" logic ensures continuous time-series even during sensor glitches.
*   **Dual Persistence:** Local SQLite storage for provenance and TCP telemetry for real-time analysis.

### 2. Signal Denoising — Kalman Filter
`src/KalmanFilter1D.m` implements a recursive Bayesian estimator with Joseph-form covariance update. `scripts/compare_filter_performance.m` conducts a comparative study (Raw vs. Kalman vs. Savitzky-Golay), quantifying SNR improvement in dB and measuring downstream ML accuracy impact.

### 3. Feature Engineering & Machine Learning
*   **8D Feature Vector:** Ratio, ROC, **Acceleration (2nd Derivative)**, Moving Averages (5/15s), Volatility, Skewness, Kurtosis.
*   **Ensemble Classification:** A pre-trained Random Forest detects pollution sources (Traffic, Dust, Local Combustion).
*   **Adaptive Recommendation:** Dynamic thresholds calculated via moving-window statistics ($ \mu + 3\sigma $) rather than hardcoded limits.

### 4. Statistical Validation
*   `scripts/evaluate_model_performance.m` — PR Curves, AUC, and Macro-F1 on chronological holdouts.
*   `scripts/cross_validate_system.m` — **Rolling-Origin Expanding-Window CV** (Time-Series Aware).

### 5. Explainability (XAI)
`scripts/explain_model.m` provides deep interpretability:
*   **Global:** Permutation Importance and PCA projection.
*   **Local:** **SHAP Value Breakdown** (using MATLAB `shapley`) to explain precisely *why* a specific alert was triggered (e.g. "80% driven by sudden ROC spike").

### 6. Predictive Intelligence & Backtesting
`scripts/backtest_forecaster.m` evaluates the Holt-Winters forecaster at horizons of 1, 3, 5, 10, and 15 minutes — producing RMSE/MAE curves, an $\alpha$/$\beta$ sensitivity heatmap, a residual ACF white-noise test, and an actual-vs-predicted plot with uncertainty bands.

### 8. Zero-Latency Intelligence Dashboard
The `scripts/socket_intelligence_dashboard.m` is the primary monitoring interface. It:
*   **Decouples Acquisition from Analysis:** Receives JSON packets via TCP, allowing the Raspberry Pi to be located anywhere on the network.
*   **Dual-View Visualization:** Real-time filtered time-series (top) and dynamic source classification (bottom).
*   **Headless-Compatible:** Detects CI environments and runs without a GUI to satisfy automated testing requirements.

---

## 🚀 Deployment Guide

### 1. Hardware Setup
Connect your **SDS011 sensor** to the Raspberry Pi via USB.

### 2. Edge Configuration
Configure your `.env` and start the Python daemon:
```bash
sudo cp air_quality.service /etc/systemd/system/
sudo systemctl enable air_quality.service
sudo systemctl start air_quality.service
```

### 3. Intelligence Hub Setup (MATLAB)
```matlab
% 1. Train your room-specific models (Run Once)
run('scripts/train_offline_model.m') 
run('scripts/detect_novelty.m')

% 2. Start the Live Intelligence Dashboard
run('scripts/socket_intelligence_dashboard.m')
```

### 4. Post-Session Analysis
```matlab
run('scripts/compare_filter_performance.m')  % Signal denoising study
run('scripts/explain_model.m')               % XAI analysis
run('scripts/backtest_forecaster.m')         % Forecast evaluation
```

---

## 🧪 Testing & Reliability

The system is guarded by a **comprehensive dual-language testing suite** (11 test classes, 20+ test methods) integrated with **GitHub Actions** and **Codecov**:

*   **Edge Tests (Pytest):** Frame parsing, SQLite persistence, socket failure recovery.
*   **Hub Tests (MATLAB):** Feature extraction, forecasting stability, Kalman Filter convergence & reset, Isolation Forest outlier detection & score range, and novelty buffer integrity.
*   **CI/CD:** Every commit verified on Linux runners ensuring zero regression.

---

## 📁 Project Structure

```
src/
  AirQualitySystem.m      ← Real-time intelligence hub
  KalmanFilter1D.m        ← Bayesian signal denoising
  IsolationForestAD.m     ← Unsupervised anomaly detection

scripts/
  air_quality_monitor.py        ← Edge service (Raspberry Pi)
  evaluate_model_performance.m  ← Confusion matrix & F1-Score
  cross_validate_system.m       ← K-fold cross-validation
  compare_filter_performance.m  ← Raw vs Kalman vs SG study
  explain_model.m               ← XAI & feature importance
  backtest_forecaster.m         ← Multi-horizon RMSE/MAE
  detect_novelty.m              ← Isolation Forest pipeline
```

---
*Implemented as a Master's level data science project in distributed sensor intelligence, statistical machine learning, and signal processing.*
