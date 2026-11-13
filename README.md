# Network Digital Twin Proof-of-Concept (POC)

A real-time Network Digital Twin utilizing **Batfish** for control plane simulation and **Godot 4** for rendering the network topology, dynamic link failures, live packet traces, and interactive configuration testing.

---

## Architecture & Topology

```
   [ CORE TIER ]           [ DISTRIBUTION TIER ]       [ EDGE / ACCESS TIER ]

   +-----------+              +-----------+               +-----------+
   |  core-r1  +==============+  dist-r1  +===============+  edge-r1  |--> 192.168.10.0/24
   +-----+-----+ \          / +-----+-----+ \           / +-----------+
         |        \        /        |        \         /
         |         \      /         |         \       /
         |          \    /          |          \     /
         |           \  /           |           \   /
   +-----+-----+      \/      +-----+-----+      \ /      +-----------+
   |  core-r2  +==============+  dist-r2  +===============+  edge-r2  |--> 192.168.20.0/24
   +-----------+              +-----------+               +-----------+
```

- **6 Fully-Meshed Routers**: `core-r1`, `core-r2`, `dist-r1`, `dist-r2`, `edge-r1`, `edge-r2`.
- **Dynamic OSPF Routing**: Real-time convergence computed by Batfish.
- **Failover / Broken Link Detection**: Down interfaces are detected automatically via Batfish Layer 3 adjacency analysis and rendered in dashed red with warning indicators.

---

## Interactive Scenarios Available in Godot UI

1. **1. Normal (Healthy)**:
   - All 9 transit links are UP.
   - Primary route from `core-r1` to `192.168.10.1` traverses `core-r1 -> dist-r1 -> edge-r1` (`ACCEPTED`).
2. **2. Failover (dist-r1 Gi0/0 Down)**:
   - Simulates primary upstream link failure.
   - Link turns dashed red with a fault marker.
   - OSPF dynamically re-routes traffic via `dist-r2` (`core-r1 -> dist-r2 -> edge-r1`).
3. **3. Blackhole (edge-r1 Links Cut)**:
   - Both downstream links into `edge-r1` are severed.
   - Traceroute detects no viable path (`NO_ROUTE`) and displays the drop location.
4. **4. Security (ACL Drop)**:
   - Injects a Cisco access-list blocking host `192.168.10.1`.
   - Simulation shows packet arriving at `edge-r1` and getting rejected with `DENIED_IN`.
5. **Live Cisco Config Editor**:
   - Click **"Cisco Config Editor"** in Godot to inspect or edit any router's exact IOS configuration.
   - Toggle interfaces (`shutdown` / `no shutdown`), adjust OSPF costs, or write ACL rules.
   - Click **"Apply Changes & Re-simulate"** to push to Batfish and see instant forwarding changes.

---

## Quickstart

### 1. Launch Services via Docker Compose
```bash
cd network-twin-poc
docker compose up -d
```

### 2. Run in Godot 4
1. Open the project in Godot 4.
2. Press **F5** to run `Main.tscn`.
3. Try clicking the scenario buttons (**Failover**, **Blackhole**, **Security**) or **Run Trace Simulation** to watch live packet traces and link animations!
