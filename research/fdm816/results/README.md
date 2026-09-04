# FDM-816 reviewed result

The reviewed decision is **`NO-GO`** for production intelligent-hide geometry freshness on the pinned runtime.

The live experiment showed that pure tiled resize, floating drag/resize, and visual-proxy dock-boundary crossings emit no usable Hyprland socket event. The bounded sampler observed those changes only because the experiment started it manually. No production-available non-polling start trigger or deterministic stability-based stop signal was verified.

Without those signals, a sampler would need to stay active continuously to catch arbitrary movement. Continuous `hyprctl` polling is outside the accepted design, so FDM-817 remains blocked.

Run the reviewed classifier record with:

```bash
python3 research/fdm816/decision.py \
  research/fdm816/results/reviewed-result.json
```

Expected output:

```text
NO-GO
```

## Evidence handling

Only the sanitized reviewed record is committed. Raw client snapshots, window titles, process listings, journal output, event streams, and archives stay local because they can expose workstation data.

A future feasibility run may replace this result only after it verifies both:

1. a production-available, non-polling signal that starts the bounded refresh burst; and
2. a deterministic signal or measured condition that stops the burst without continuous polling.
