# VitalFlow wellness algorithms

> **All VitalFlow scores are experimental wellness estimates.** They are not clinically
> validated, are not medical measurements, and must not be used to diagnose, treat or
> prevent any condition. Every formula below is implemented in
> `Packages/VitalFlowCore` and covered by unit tests in `Packages/VitalFlowCore/Tests`.

## 0. Principles

* **Personal baselines, not population norms.** Each physiological input is compared to the
  user's own recent history.
* **Robust statistics.** Baselines use the median and the scaled median absolute deviation
  (1.4826 × MAD) so one bad night or a sensor glitch doesn't distort them.
* **No invented values.** If a required input is missing, the score is
  `ScoreResult.notEnoughData(missing:)` and the UI shows “Not enough data” with a hint.
* **Transparent output.** Every score returns its components (value, baseline, standardised
  effect, weight) and a confidence level; the app shows them on the score detail screen.

## 1. Data preparation

| Step | Implementation | Notes |
|---|---|---|
| Day boundaries | `DayKey`, calendar-aware | Local midnight; 23 h / 25 h DST days handled by `Calendar`. |
| Cumulative metrics (steps, distance, energy, exercise, daylight, water) | `HKStatisticsCollectionQuery` with `.cumulativeSum` in production | HealthKit merges overlapping sources using the user's source priority. For demo data/tests `Deduplicator.mergedCumulativeTotal` reproduces this: for every elementary time slice only the highest-ranked source counts (Apple Watch > Apple device > third-party). Samples crossing midnight are split proportionally. |
| Discrete metrics (HR, HRV, RHR, SpO₂, respiratory rate, temperature, VO₂max, weight) | `Deduplicator.dedupeDiscrete` | Removes identical UUIDs and cross-source duplicates (same kind, start within 1 s, value within 0.1 %); keeps the highest-ranked source. |
| Sleep | `SleepAnalyzer` | See §2. |
| Workouts | Duplicate UUIDs ignored in `TrainingLoad.dailyLoad`. |
| Sync delays | The app refreshes on launch, on foreground, on pull-to-refresh and on `HKObserverQuery` callbacks (hourly background delivery on iOS). Scores are recomputed from scratch each time, so late-arriving Apple Watch data is incorporated automatically. |

## 2. Sleep

**Night attribution.** The night for wake day *D* is the window `[D−1 18:00, D 18:00)`.
Sessions entirely between 10:00 and 18:00 of *D* are naps (reported separately).

**Merging overlapping samples.**
1. Drop zero-length samples and duplicate UUIDs.
2. Pick a *primary source*: most staged sleep (core/deep/REM), then most asleep time, then source rank.
3. Sweep-line over all sample boundaries. For each slice the winner is the sample with the
   highest `(isPrimarySource, stagePriority)`; stage priority is
   `awake 6 > deep 5 > REM 4 > core 3 > asleep-unspecified 2 > in-bed 1`
   (awake wins conflicts so sleep is never over-counted). Secondary sources only fill gaps.
4. Adjacent slices with the same stage are merged; sessions are split at gaps > 90 min.
5. Leading/trailing awake time is trimmed. Awake segments ≥ 1 min inside a session count as
   interruptions; gaps between sessions of a split night count as awake time + 1 interruption.

**Sleep consistency (0–100).** Standard deviation σ of mid-sleep time (minutes from noon, so
the midnight wrap is continuous) over the last 7 nights: `ramp(σ, 15 → 100, 95 → 0)`.
Needs ≥ 4 nights.

**Sleep score (0–100).** Weighted average of sub-scores; weights are renormalised over the
components that are available.

| Component | Sub-score | Weight |
|---|---|---|
| Duration | `ramp(asleep / need, 0.5 → 0, 1.0 → 100)`; need defaults to 8 h (6–10 h user setting) | 40 % |
| Efficiency | `ramp(asleep / time-in-bed, 0.70 → 0, 0.90 → 100)` | 20 % |
| Restorative | `ramp((deep + REM) / asleep, 0.15 → 0, 0.40 → 100)` — only with stage data | 20 % |
| Interruptions | `100 − 15 × max(0, n − 1)` | 10 % |
| Consistency | consistency score | 10 % |

Requires ≥ 30 min of sleep. Confidence: high (stages + consistency), medium (stages), low (no stages).

## 3. Baselines

`BaselineCalculator`: days strictly before today, rolling 28-day window, **minimum 4 days**.
`median` and `spread = max(1.4826 × MAD, floor)`.

| Metric | Transform | Spread floor |
|---|---|---|
| HRV (SDNN) | natural log (HRV is log-normal) | 0.06 (≈ 6 %) |
| Resting HR | none | 1.5 bpm |
| Respiratory rate | none | 0.5 br/min |
| Wrist temperature | none | 0.15 °C |

Daily HRV = mean of SDNN samples recorded during the main sleep (falls back to the day's median).

Baseline confidence: < 14 days low, 14–20 medium, ≥ 21 high.

## 4. Recovery (0–100)

Effects (each clamped to ±3, positive = better):

| Input | Effect eᵢ | Weight wᵢ |
|---|---|---|
| HRV | `z(ln HRV)` | 0.45 |
| Resting HR | `−z(RHR)` | 0.25 |
| Sleep score | `(sleepScore − 70) / 15` | 0.20 |
| Respiratory rate | `−max(0, z)` (only elevation penalised) | 0.05 |
| Wrist temperature | `−max(0, |z| − 1)` | 0.05 |

`composite = Σ wᵢeᵢ / Σ wᵢ` over available inputs;
`recovery = round(100 × logistic(0.5 + 1.4 × composite))`.
A neutral day (all at baseline, sleep score 70) gives ≈ 62.

**Requirements:** HRV *or* RHR with a valid baseline **and** total available weight ≥ 0.45
(e.g. RHR + sleep). Otherwise “Not enough data”.
**Confidence:** best baseline confidence, capped to low if available weight < 0.65 and to
medium if < 0.85.

## 5. Stress (0–100)

Hourly, 07:00–23:00, only for hours that have ended, excluding hours that overlap a workout
or contain > 1 200 steps:

* `hrStress = clamp(100 × (median HR − RHR_baseline) / (0.35 × (HRmax − RHR_baseline)), 0, 100)`
  with `HRmax = 208 − 0.7 × age` (Tanaka) or 185 when age is unknown.
* if HRV samples exist in that hour: `hrvStress = clamp(50 − 25 × z(ln HRV), 0, 100)` and
  `level = 0.6 × hrStress + 0.4 × hrvStress`.

Daily stress = mean of valid hours. Needs an RHR baseline and ≥ 3 valid hours (each with
≥ 2 HR samples). Confidence low < 8 hours.

**Limitation:** heart rate rises for many non-stress reasons (caffeine, heat, illness,
digestion, posture). Apple Watch records heart rate intermittently outside workouts.

## 6. Body Battery (0–100)

An energy-reservoir model, simulated from wake time (or 07:00) to now:

* `morning = clamp(0.6 × recovery + 0.4 × sleepScore, 5, 100)`
  (recovery alone, or 0.9 × sleepScore alone, if one is missing; neither → not enough data).
* Per awake hour: `−2.0` baseline, `−0.04 × active kcal`, `−(stress − 50) / 25` when stress > 50,
  `+0.5` during calm hours (stress < 25 and < 300 steps). Clamped to 0–100.

Confidence is never higher than medium: this is a heuristic model.

## 7. Training load, readiness and balance

* **Workout load** (Banister TRIMP): `minutes × HRr × 0.64 × e^(1.92 × HRr)`,
  `HRr = (avgHR − RHR) / (HRmax − RHR)`. Without heart rate: `kcal / 8`; without either:
  `minutes × 0.5`.
* **ACWR** = mean daily load over 7 days / mean daily load over 28 days. Needs ≥ 14 days of
  history and chronic load > 0.5. Zones: < 0.8 under-training, 0.8–1.3 optimal,
  1.3–1.5 high, > 1.5 very high.
* **Load-balance score**: 75 below 0.8, 100 in 0.8–1.3, linear to 40 at 1.6 and 20 at 2.0.
* **Training readiness** = `0.65 × recovery + 0.35 × balanceScore` (recovery alone, low
  confidence, if ACWR is unavailable). Levels: ≥ 75 ready to push, 50–74 moderate,
  30–49 keep it light, < 30 rest.
* **Activity load (0–100)** = `100 × (1 − e^(−todayLoad / (1.5 × max(chronic, 20))))`.
* **Activity/recovery balance**: overreaching if load − recovery > 25; rest day if both < 40;
  room to push if recovery − load > 35; otherwise balanced.

## 8. Trends

Mean of the last *N* days vs the previous *N* days (each needs ≥ ⌈N/2⌉ values).
|change| < 3 % → stable; otherwise improving/declining according to whether higher is
better for that metric (lower is better for resting HR, respiratory rate and stress).

## 9. Gamification

* Goal targets are clamped to healthy ranges (e.g. steps 2 000–20 000, active energy
  150–900 kcal, sleep 6–10 h, water 1–3.5 L).
* The garden is a pure function of goal history: each completed goal adds one growth point
  to that goal's plant; 18 points = tree, then a new seed is planted. Missed days never
  remove growth. Streak = consecutive days with ≥ 2 goals.

## 10. Known limitations

* Not validated against clinical or laboratory measurements.
* HRV from Apple Watch is SDNN from short, irregular windows — not comparable to RMSSD-based
  products and sensitive to measurement timing.
* Baselines need ≥ 4 days and become reliable after ~3 weeks.
* Respiratory rate, wrist temperature and SpO₂ are only available on supported Apple Watch
  models and regions; scores degrade gracefully (weights renormalised, lower confidence).
* Illness, alcohol, travel, menstrual cycle, medication and altitude influence the inputs
  and are not modelled.
