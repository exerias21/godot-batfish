import os
import sys
import time
import logging
from contextlib import asynccontextmanager
from typing import Dict, Any, List, Set

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pybatfish.client.session import Session
try:
    from pybatfish.datamodel import HeaderConstraints
except ImportError:
    HeaderConstraints = None

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("network-twin")

BATFISH_HOST = os.environ.get("BATFISH_HOST", "batfish")
SNAPSHOT_PATH = os.environ.get("SNAPSHOT_PATH", "/app/snapshot")
CONFIGS_DIR = os.path.join(SNAPSHOT_PATH, "configs")
NETWORK_NAME = "poc_net"

# Baseline router configs (Healthy State)
HEALTHY_CONFIGS: Dict[str, str] = {
    "core-r1": """hostname core-r1
!
interface Loopback0
 ip address 10.0.0.1 255.255.255.255
 no shutdown
!
interface GigabitEthernet0/0
 description Primary to dist-r1
 ip address 10.1.3.1 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/1
 description Secondary to dist-r2
 ip address 10.1.4.1 255.255.255.0
 ip ospf cost 20
 no shutdown
!
interface GigabitEthernet0/2
 description Inter-Core to core-r2
 ip address 10.1.1.1 255.255.255.0
 ip ospf cost 10
 no shutdown
!
router ospf 1
 router-id 10.0.0.1
 network 10.0.0.0 0.255.255.255 area 0
!
""",
    "core-r2": """hostname core-r2
!
interface Loopback0
 ip address 10.0.0.2 255.255.255.255
 no shutdown
!
interface GigabitEthernet0/0
 description Link to dist-r1
 ip address 10.2.3.2 255.255.255.0
 ip ospf cost 20
 no shutdown
!
interface GigabitEthernet0/1
 description Link to dist-r2
 ip address 10.2.4.2 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/2
 description Inter-Core to core-r1
 ip address 10.1.1.2 255.255.255.0
 ip ospf cost 10
 no shutdown
!
router ospf 1
 router-id 10.0.0.2
 network 10.0.0.0 0.255.255.255 area 0
!
""",
    "dist-r1": """hostname dist-r1
!
interface Loopback0
 ip address 10.0.0.3 255.255.255.255
 no shutdown
!
interface GigabitEthernet0/0
 description Upstream to core-r1
 ip address 10.1.3.3 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/1
 description Upstream to core-r2
 ip address 10.2.3.3 255.255.255.0
 ip ospf cost 20
 no shutdown
!
interface GigabitEthernet0/2
 description Downstream to edge-r1
 ip address 10.3.5.3 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/3
 description Downstream to edge-r2
 ip address 10.3.6.3 255.255.255.0
 ip ospf cost 10
 no shutdown
!
router ospf 1
 router-id 10.0.0.3
 network 10.0.0.0 0.255.255.255 area 0
!
""",
    "dist-r2": """hostname dist-r2
!
interface Loopback0
 ip address 10.0.0.4 255.255.255.255
 no shutdown
!
interface GigabitEthernet0/0
 description Upstream to core-r1
 ip address 10.1.4.4 255.255.255.0
 ip ospf cost 20
 no shutdown
!
interface GigabitEthernet0/1
 description Upstream to core-r2
 ip address 10.2.4.4 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/2
 description Downstream to edge-r1
 ip address 10.4.5.4 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/3
 description Downstream to edge-r2
 ip address 10.4.6.4 255.255.255.0
 ip ospf cost 10
 no shutdown
!
router ospf 1
 router-id 10.0.0.4
 network 10.0.0.0 0.255.255.255 area 0
!
""",
    "edge-r1": """hostname edge-r1
!
interface Loopback0
 ip address 10.0.0.5 255.255.255.255
 no shutdown
!
interface GigabitEthernet0/0
 description Upstream to dist-r1
 ip address 10.3.5.5 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/1
 description Upstream to dist-r2
 ip address 10.4.5.5 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/2
 description Host Subnet 192.168.10.0/24
 ip address 192.168.10.1 255.255.255.0
 no shutdown
!
router ospf 1
 router-id 10.0.0.5
 network 10.0.0.0 0.255.255.255 area 0
 network 192.168.10.0 0.0.0.255 area 0
!
""",
    "edge-r2": """hostname edge-r2
!
interface Loopback0
 ip address 10.0.0.6 255.255.255.255
 no shutdown
!
interface GigabitEthernet0/0
 description Upstream to dist-r1
 ip address 10.3.6.6 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/1
 description Upstream to dist-r2
 ip address 10.4.6.6 255.255.255.0
 ip ospf cost 10
 no shutdown
!
interface GigabitEthernet0/2
 description Host Subnet 192.168.20.0/24
 ip address 192.168.20.1 255.255.255.0
 no shutdown
!
router ospf 1
 router-id 10.0.0.6
 network 10.0.0.0 0.255.255.255 area 0
 network 192.168.20.0 0.0.0.255 area 0
!
"""
}

# Physical topology edges (full mesh)
PHYSICAL_EDGES = [
    {"source": "core-r1", "target": "core-r2"},
    {"source": "core-r1", "target": "dist-r1"},
    {"source": "core-r1", "target": "dist-r2"},
    {"source": "core-r2", "target": "dist-r1"},
    {"source": "core-r2", "target": "dist-r2"},
    {"source": "dist-r1", "target": "edge-r1"},
    {"source": "dist-r1", "target": "edge-r2"},
    {"source": "dist-r2", "target": "edge-r1"},
    {"source": "dist-r2", "target": "edge-r2"},
]

ALL_NODES = ["core-r1", "core-r2", "dist-r1", "dist-r2", "edge-r1", "edge-r2"]

# Global state
bf_session: Session = None
active_scenario: str = "healthy"
topology_data = {
    "nodes": ALL_NODES,
    "edges": PHYSICAL_EDGES,
    "active_edges": PHYSICAL_EDGES,
    "broken_edges": [],
    "scenario": "healthy"
}


def write_configs(configs: Dict[str, str]):
    os.makedirs(CONFIGS_DIR, exist_ok=True)
    for existing in os.listdir(CONFIGS_DIR):
        if existing.endswith(".cfg") and existing[:-4] not in configs:
            try:
                os.remove(os.path.join(CONFIGS_DIR, existing))
            except Exception:
                pass
    for node, text in configs.items():
        cfg_path = os.path.join(CONFIGS_DIR, f"{node}.cfg")
        with open(cfg_path, "w") as f:
            f.write(text)


def extract_topology(session: Session) -> Dict[str, Any]:
    active_edge_keys: Set[tuple] = set()

    try:
        edges_df = session.q.layer3Edges().answer().frame()
        for _, row in edges_df.iterrows():
            u_iface = row.get("Interface")
            v_iface = row.get("Remote_Interface")

            u_node = getattr(u_iface, "hostname", None) or (u_iface.get("hostname") if isinstance(u_iface, dict) else None)
            v_node = getattr(v_iface, "hostname", None) or (v_iface.get("hostname") if isinstance(v_iface, dict) else None)

            if not u_node and u_iface:
                u_node = str(u_iface).split("[")[0]
            if not v_node and v_iface:
                v_node = str(v_iface).split("[")[0]

            if u_node and v_node:
                key = tuple(sorted([u_node, v_node]))
                if key[0] != key[1]:
                    active_edge_keys.add(key)
    except Exception as e:
        logger.error(f"Error querying layer3Edges: {e}")

    active_edges = []
    broken_edges = []

    for pe in PHYSICAL_EDGES:
        key = tuple(sorted([pe["source"], pe["target"]]))
        if key in active_edge_keys:
            active_edges.append(pe)
        else:
            broken_edges.append(pe)

    return {
        "nodes": ALL_NODES,
        "edges": PHYSICAL_EDGES,
        "active_edges": active_edges,
        "broken_edges": broken_edges,
        "scenario": active_scenario
    }


def reload_batfish_snapshot(snap_name_prefix: str = "snap"):
    global bf_session, topology_data
    if bf_session is None:
        return
    snap_id = f"{snap_name_prefix}_{int(time.time() * 1000)}"
    logger.info(f"Re-initializing Batfish snapshot: {snap_id}")
    bf_session.init_snapshot(SNAPSHOT_PATH, name=snap_id, overwrite=True)
    topology_data = extract_topology(bf_session)
    logger.info(f"Snapshot reloaded. Active links: {len(topology_data['active_edges'])}, Broken: {len(topology_data['broken_edges'])}")


def toggle_interface_in_file(node: str, interface: str):
    cfg_path = os.path.join(CONFIGS_DIR, f"{node}.cfg")
    if not os.path.exists(cfg_path):
        return
    with open(cfg_path, "r") as f:
        content = f.read()

    # Find the interface block
    iface_hdr = f"interface {interface}"
    pos = content.find(iface_hdr)
    if pos == -1:
        return

    end_pos = content.find("!", pos)
    if end_pos == -1:
        end_pos = len(content)

    block = content[pos:end_pos]
    if "no shutdown" in block:
        new_block = block.replace("no shutdown", "shutdown")
    elif "shutdown" in block:
        new_block = block.replace("shutdown", "no shutdown")
    else:
        new_block = block + " shutdown\n"

    content = content[:pos] + new_block + content[end_pos:]
    with open(cfg_path, "w") as f:
        f.write(content)


def apply_scenario(scenario_name: str):
    global active_scenario
    active_scenario = scenario_name
    configs = {k: v for k, v in HEALTHY_CONFIGS.items()}

    if scenario_name == "healthy":
        pass  # healthy baseline

    elif scenario_name == "failover":
        configs["dist-r1"] = configs["dist-r1"].replace(
            "interface GigabitEthernet0/0\n description Upstream to core-r1\n ip address 10.1.3.3 255.255.255.0\n ip ospf cost 10\n no shutdown",
            "interface GigabitEthernet0/0\n description Upstream to core-r1\n ip address 10.1.3.3 255.255.255.0\n ip ospf cost 10\n shutdown"
        )

    elif scenario_name == "severed":
        configs["dist-r1"] = configs["dist-r1"].replace(
            "interface GigabitEthernet0/2\n description Downstream to edge-r1\n ip address 10.3.5.3 255.255.255.0\n ip ospf cost 10\n no shutdown",
            "interface GigabitEthernet0/2\n description Downstream to edge-r1\n ip address 10.3.5.3 255.255.255.0\n ip ospf cost 10\n shutdown"
        )
        configs["dist-r2"] = configs["dist-r2"].replace(
            "interface GigabitEthernet0/2\n description Downstream to edge-r1\n ip address 10.4.5.4 255.255.255.0\n ip ospf cost 10\n no shutdown",
            "interface GigabitEthernet0/2\n description Downstream to edge-r1\n ip address 10.4.5.4 255.255.255.0\n ip ospf cost 10\n shutdown"
        )

    elif scenario_name == "acl":
        acl_def = """ip access-list extended BLOCK_HOST
 deny ip any host 192.168.10.1
 permit ip any any
!
"""
        edge1 = configs["edge-r1"]
        edge1 = edge1.replace("interface GigabitEthernet0/0\n", "interface GigabitEthernet0/0\n ip access-group BLOCK_HOST in\n")
        edge1 = edge1.replace("interface GigabitEthernet0/1\n", "interface GigabitEthernet0/1\n ip access-group BLOCK_HOST in\n")
        edge1 = edge1 + "\n" + acl_def
        configs["edge-r1"] = edge1

    write_configs(configs)
    reload_batfish_snapshot(f"scenario_{scenario_name}")


def execute_trace(session: Session, src: str, dst_ip: str):
    if session is None:
        return [], "BATFISH_NOT_CONNECTED"

    if not src:
        src = "core-r1"
    if not dst_ip:
        dst_ip = "192.168.10.1"

    try:
        logger.info(f"Running traceroute: startLocation={src}, dstIps={dst_ip}")
        if HeaderConstraints is not None:
            headers = HeaderConstraints(dstIps=dst_ip)
            tr_df = session.q.traceroute(startLocation=src, headers=headers).answer().frame()
        else:
            tr_df = session.q.traceroute(startLocation=src, headers={"dstIps": dst_ip}).answer().frame()

        hops: List[str] = []
        status = "UNKNOWN"

        if not tr_df.empty and "Traces" in tr_df.columns:
            traces_col = tr_df["Traces"].iloc[0]
            trace_list = list(traces_col) if isinstance(traces_col, (set, list)) else [traces_col]
            if trace_list:
                first_trace = trace_list[0]
                status = getattr(first_trace, "disposition", None) or (first_trace.get("disposition") if isinstance(first_trace, dict) else "UNKNOWN")
                raw_hops = getattr(first_trace, "hops", None) or (first_trace.get("hops") if isinstance(first_trace, dict) else [])
                for hop in raw_hops:
                    node_name = getattr(hop, "node", None) or (hop.get("node") if isinstance(hop, dict) else str(hop))
                    hops.append(str(node_name))

        logger.info(f"Traceroute finished: hops={hops}, status={status}")
        return hops, str(status)
    except Exception as e:
        logger.error(f"Traceroute error: {e}", exc_info=True)
        return [], f"ERROR: {e}"


def connect_and_init_batfish(max_retries: int = 30, retry_delay: int = 2):
    global bf_session, topology_data
    logger.info(f"Connecting to Batfish at host '{BATFISH_HOST}'...")
    bf = Session(host=BATFISH_HOST)

    connected = False
    for attempt in range(1, max_retries + 1):
        try:
            bf.set_network(NETWORK_NAME)
            connected = True
            logger.info("Connected to Batfish.")
            break
        except Exception as e:
            logger.info(f"Waiting for Batfish ({attempt}/{max_retries}): {e}")
            time.sleep(retry_delay)

    if not connected:
        logger.error("Could not connect to Batfish.")
        return

    bf_session = bf
    apply_scenario("healthy")


@asynccontextmanager
async def lifespan(app: FastAPI):
    connect_and_init_batfish()
    yield
    logger.info("Shutting down network-twin backend.")


app = FastAPI(title="Network Digital Twin POC Backend", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def get_root():
    return {
        "status": "online",
        "batfish_connected": bf_session is not None,
        "scenario": active_scenario,
        "nodes": topology_data["nodes"],
        "active_edges": topology_data["active_edges"],
        "broken_edges": topology_data["broken_edges"]
    }


@app.get("/topology")
def get_topology():
    return topology_data


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    logger.info("WebSocket client connected.")

    try:
        # Send initial topology state
        init_payload = {
            "type": "init",
            "nodes": topology_data["nodes"],
            "edges": topology_data["edges"],
            "active_edges": topology_data["active_edges"],
            "broken_edges": topology_data["broken_edges"],
            "scenario": active_scenario
        }
        await websocket.send_json(init_payload)

        while True:
            data = await websocket.receive_json()
            action = data.get("action")
            logger.info(f"Received action: '{action}' | payload: {data}")

            if action == "trace":
                src = data.get("src") or "core-r1"
                dst_ip = data.get("dst_ip") or "192.168.10.1"
                hops, status = execute_trace(bf_session, src, dst_ip)
                await websocket.send_json({
                    "type": "trace_result",
                    "hops": hops,
                    "status": status,
                    "src": src,
                    "dst_ip": dst_ip
                })

            elif action == "break_link":
                link_id = data.get("link_id", "")
                if link_id == "core1_dist1":
                    toggle_interface_in_file("dist-r1", "GigabitEthernet0/0")
                elif link_id == "dist1_edge1":
                    toggle_interface_in_file("dist-r1", "GigabitEthernet0/2")
                elif link_id == "dist2_edge1":
                    toggle_interface_in_file("dist-r2", "GigabitEthernet0/2")
                elif link_id == "restore_all":
                    apply_scenario("healthy")

                if link_id != "restore_all":
                    reload_batfish_snapshot(f"break_{link_id}")

                await websocket.send_json({
                    "type": "init",
                    "nodes": topology_data["nodes"],
                    "edges": topology_data["edges"],
                    "active_edges": topology_data["active_edges"],
                    "broken_edges": topology_data["broken_edges"],
                    "scenario": "custom"
                })

                # Automatically trigger a trace to give immediate visual feedback
                src = data.get("src") or "core-r1"
                dst_ip = data.get("dst_ip") or "192.168.10.1"
                hops, status = execute_trace(bf_session, src, dst_ip)
                await websocket.send_json({
                    "type": "trace_result",
                    "hops": hops,
                    "status": status,
                    "src": src,
                    "dst_ip": dst_ip
                })

            elif action == "load_scenario":
                scen = data.get("scenario", "healthy")
                logger.info(f"Applying scenario: {scen}")
                apply_scenario(scen)
                await websocket.send_json({
                    "type": "init",
                    "nodes": topology_data["nodes"],
                    "edges": topology_data["edges"],
                    "active_edges": topology_data["active_edges"],
                    "broken_edges": topology_data["broken_edges"],
                    "scenario": active_scenario
                })

                # Automatically trigger trace simulation so the result updates immediately
                src = data.get("src") or "core-r1"
                dst_ip = data.get("dst_ip") or "192.168.10.1"
                hops, status = execute_trace(bf_session, src, dst_ip)
                await websocket.send_json({
                    "type": "trace_result",
                    "hops": hops,
                    "status": status,
                    "src": src,
                    "dst_ip": dst_ip
                })

            elif action == "get_config":
                node = data.get("node", "core-r1")
                cfg_path = os.path.join(CONFIGS_DIR, f"{node}.cfg")
                content = ""
                if os.path.exists(cfg_path):
                    with open(cfg_path, "r") as f:
                        content = f.read()
                await websocket.send_json({
                    "type": "config_data",
                    "node": node,
                    "content": content
                })

            elif action == "save_config":
                node = data.get("node", "core-r1")
                content = data.get("content", "")
                cfg_path = os.path.join(CONFIGS_DIR, f"{node}.cfg")
                with open(cfg_path, "w") as f:
                    f.write(content)
                reload_batfish_snapshot(f"custom_{node}")
                await websocket.send_json({
                    "type": "init",
                    "nodes": topology_data["nodes"],
                    "edges": topology_data["edges"],
                    "active_edges": topology_data["active_edges"],
                    "broken_edges": topology_data["broken_edges"],
                    "scenario": "custom"
                })

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
    except Exception as e:
        logger.error(f"WebSocket session error: {e}")
