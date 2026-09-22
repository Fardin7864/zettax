# TimedDirectionContract Engine

Timed direction contracts are demo-only. The server fixes entry and expiry
timestamps and stores deterministic demo provider timestamps, prices, source,
and sequences. Two crash-isolated financial workers claim due contracts; row
locking, the unique settlement key, and the ledger idempotency key guarantee one
settlement. UP wins only above entry, DOWN only below, and equality returns the
stake as DRAW. Both directions use the same mark without a directional spread.
The settlement and its durable private-account event commit atomically. These
simulation workers are not an approved real execution or market-data adapter.
