## Unreleased

- Reduced synchronization latency by throttling full HTTP reachability probes
  while connectivity remains online, aligning the default monitor check
  interval with engine polling (500 ms), and fixing the example to probe the
  API endpoint instead of external endpoints every poll.
- The Flutter example now uses the deployed HTTPS JSON Server endpoint and no
  longer includes or permits a local cleartext mock server.

## 0.1.0

- Initial offline-first queue backed by SQLite.
- Persistent local entity documents with offline reads and observation.
- Migration of existing queued payloads into the local document store.
- Connectivity stream exposed publicly, with auto-sync polling fallback when
  native network restoration events are missed.
- Failed operations become eligible for a fresh retry round when connectivity
  returns, while retaining their historical retry count.
- Online connectivity confirmations now retry pending and failed work even
  without a new offline-to-online transition.
- Retry backoff restarts per synchronization run so long offline/API outages
  do not leave recovered operations waiting on an ever-growing delay.
- Interrupted `syncing` items are recovered, and repeated creates check the
  remote identifier before posting again to avoid duplicate submissions.
- Network-restoration events interrupt an in-progress retry wait immediately;
  the default missed-event connectivity check interval is now 500 milliseconds.
- Remote adapter calls are gated by live connectivity checks, and a connection
  loss during a request restores the operation to `pending` without spending a retry.
- **Breaking:** replaced `connectivity_plus` with
  `internet_connection_checker_plus`. Default monitor is now
  `InternetConnectionMonitor` (real HTTP reachability). `ConnectivityPlusMonitor`
  is a deprecated alias.
- The JSON Server example uses a 500 ms internet fallback, 100 ms retry base
  delay, and 300 ms request timeouts for prompt synchronization after reconnecting.
- Automatic and manual synchronization with connectivity observation.
- Configurable retry/backoff and conflict resolution strategies.
- Generic API adapter and Dio REST implementation.
- Background integration entry point and runnable Task example backed by JSON Server.
