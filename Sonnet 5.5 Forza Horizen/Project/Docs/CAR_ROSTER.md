# Garage roster — 10 original cars (no real manufacturers, models or logos)

Game title: **Roamline: Open Roads** (original). C++ class prefix `Roam`. UE content root `/Game/Forza/...`.
All cars are authored in Blender from scratch (never one mesh scaled into another). Dimensions are targets (m); the Blender script is the source of truth and writes the final values to the sidecar JSON.

| # | Id | Display name | Class (PI band) | Drivetrain | Silhouette brief | L × W × H | Wheelbase | Wheel radius F/R | Mass | Power | Character |
|---|----|--------------|-----------------|-----------|------------------|-----------|-----------|------------------|------|-------|-----------|
| 1 | `car01_hatch_pulse` | **Pulse** | D/C (≈ 380) | FWD | compact 3-door hot hatch: short overhangs, steep hatch tail, roof spoiler, small twin exhaust, 17" alloys | 3.95 × 1.78 × 1.44 | 2.52 | 0.32 / 0.32 | 1250 kg | 155 kW | agile, light understeer, lift-off oversteer |
| 2 | `car02_sedan_cadence` | **Cadence** | D (≈ 330) | FWD | everyday 4-door three-box sedan, conservative roof line, chrome window trim, modest 16" wheels | 4.70 × 1.82 × 1.46 | 2.76 | 0.31 / 0.31 | 1480 kg | 120 kW | stable, comfy, safe understeer, soft body roll |
| 3 | `car03_muscle_thunderline` | **Thunderline** | B (≈ 580) | RWD | classic V8 two-door fastback muscle: long hood with scoop, short deck, wide rear haunches, black stripes option, fat rear tyres | 4.85 × 1.92 × 1.32 | 2.75 | 0.33 / 0.35 | 1650 kg | 310 kW | huge torque, tail-happy, wheelspin |
| 4 | `car04_coupe_vesper` | **Vesper** | A (≈ 650) | RWD | 2-door sports coupe: low, sleek, long nose, small cabin, ducktail, 19" wheels | 4.40 × 1.85 × 1.30 | 2.58 | 0.34 / 0.35 | 1380 kg | 285 kW | precise, balanced, rotates on throttle |
| 5 | `car05_gt_meridian` | **Meridian GT** | A/S1 (≈ 720) | RWD (front-engine) | grand tourer: very long hood, set-back cabin, fastback roof, wide haunches, quad exhaust, 20" wheels | 4.80 × 1.95 × 1.34 | 2.88 | 0.35 / 0.36 | 1700 kg | 410 kW | fast, planted, stable at 300 km/h |
| 6 | `car06_super_aether` | **Aether** | S2 (≈ 850) | AWD (mid-engine) | wedge supercar: cab-forward, side intakes, rear diffuser + wing, scissor-style roof glass, 20/21" wheels | 4.50 × 2.02 × 1.14 | 2.70 | 0.34 / 0.36 | 1450 kg | 540 kW | enormous grip & traction, sharp turn-in |
| 7 | `car07_rally_ridge` | **Ridge** | B (≈ 600) | AWD | rally hatch: raised ride height, bonnet vents, huge rear wing, mud flaps, roof scoop, spotlights pod, 15" gravel wheels | 4.15 × 1.84 × 1.48 | 2.60 | 0.33 / 0.33 | 1260 kg | 235 kW | superb on gravel/dirt, slide-friendly |
| 8 | `car08_suv_ranger` | **Ranger** | C (≈ 480) | AWD | tall boxy off-road SUV: roof rack, snorkel, bull bar, big knobbly tyres, high clearance | 4.60 × 1.92 × 1.92 | 2.78 | 0.40 / 0.40 | 2150 kg | 220 kW | tall suspension, rough-road capability, body roll |
| 9 | `car09_pickup_mule` | **Mule** | C (≈ 450) | RWD (AWD optional) | double-cab pickup truck: open bed with tailgate, tall stance, chunky bumpers, 18" tyres | 5.30 × 1.96 × 1.88 | 3.25 | 0.38 / 0.38 | 2350 kg | 250 kW | heavy, strong body roll, long braking distances |
| 10 | `car10_roadster_classic` | **Brisa** | D (≈ 300) | RWD | vintage open roadster: round headlights on fenders, separate curved wings, spoked wheels, folded soft-top, tiny windscreen | 3.85 × 1.62 × 1.22 | 2.30 | 0.30 / 0.31 | 900 kg | 70 kW | light, slow, charming, easy to slide |

Traffic vehicles (simpler, lower-poly, drivable only by AI): `traffic01_compact`, `traffic02_van`, `traffic03_lorry` (rigid 3-axle box truck), `traffic04_bus`, `traffic05_tractor` (farm roads, slow), `traffic06_pickup` — all in `Tools/blender/traffic/`.

Common requirements: see `Docs/BLENDER_CONTRACT.md` (parts, pivots, materials, export). Paint system: `M_Paint` (primary) + `M_Paint2` (accent) are swapped in UE (gloss / matte / metallic).
