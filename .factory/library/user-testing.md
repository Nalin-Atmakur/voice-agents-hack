# User Testing

**What belongs here:** Testing surface, required testing skills/tools, resource cost classification.

---

## Validation Surface

- **Primary surface:** `xcodebuild test` output on iPhone 17 Pro simulator
- **Secondary:** `xcodebuild build` for iphoneos device destination
- **Tool:** Command-line xcodebuild (no browser, no agent-browser needed)
- **Auth/bootstrap:** None required. Tests use `--ui-test-skip-download` to bypass model download gate.

## Validation Concurrency

- **Max concurrent validators:** 1 (xcodebuild test runs all suites sequentially in one process; cannot parallelize without separate schemes)
- **Resource cost:** ~4 GB RAM for simulator + xcodebuild. Machine has 24 GB with ~6 GB baseline usage = ~18 GB headroom. Single validator is well within budget.
- **Constraint:** Only one xcodebuild instance can use the simulator at a time. Running two causes "Application failed preflight checks / Busy" errors.
