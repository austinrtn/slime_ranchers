# Fix Later

## Redundant getSlot calls in getComponent

**Location:** Prescient.zig:217 and PoolInterface.zig:72

**Issue:** The `getComponent` call chain calls `getSlot` twice:
1. First in `Prescient.zig:217` to get the entity slot
2. Again in `PoolInterface.zig:72` to get the same slot

**Impact:** Minor - just two array lookups, but could be optimized by passing the slot directly from Prescient to PoolInterface instead of re-fetching it.

**Priority:** Low - each getSlot is just an array lookup and generation check, so the overhead is negligible (a few nanoseconds per call).
