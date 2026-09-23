#!/usr/bin/env python3
"""
Hardware telemetry and system information probe for Tamlinux.
Universal dynamic sysfs/procfs/pci probing engine for fred.sysinfo.
Outputs a structured JSON object to stdout.
"""

import os
import glob
import time
import json
import re
import shlex
import subprocess
import stat
import sys

STATIC_CACHE_TTL = 300  # 5 minutes
MAX_CACHE_BYTES = 65536


def get_secure_cache_dir():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir and os.path.isdir(runtime_dir):
        return os.path.join(runtime_dir, "fred.sysinfo")
    cache_home = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(cache_home, "fred.sysinfo")


def open_secure_cache_dir(cache_dir=None):
    cache_dir = cache_dir or get_secure_cache_dir()
    try:
        os.makedirs(cache_dir, mode=0o700, exist_ok=True)
        fd = os.open(cache_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        info = os.fstat(fd)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            os.close(fd)
            raise ValueError("cache directory must be owned by this user and mode 0700")
        return fd
    except (OSError, ValueError) as exc:
        print(f"fred.sysinfo: refusing cache directory {cache_dir}: {exc}", file=sys.stderr)
        return None


def _safe_cache_name(name):
    return bool(name) and name not in (".", "..") and os.path.basename(name) == name


def write_private_file(name, data, cache_dir=None):
    if not _safe_cache_name(name) or len(data) > MAX_CACHE_BYTES:
        return False
    dfd = open_secure_cache_dir(cache_dir)
    if dfd is None:
        return False
    temp_name = f".{name}.{os.urandom(8).hex()}.tmp"
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
        fd = os.open(temp_name, flags, 0o600, dir_fd=dfd)
        try:
            with os.fdopen(fd, "wb", closefd=False) as stream:
                stream.write(data)
                stream.flush()
                os.fsync(fd)
        finally:
            os.close(fd)
        os.rename(temp_name, name, src_dir_fd=dfd, dst_dir_fd=dfd)
        temp_name = None
        os.fsync(dfd)
        return True
    except OSError as exc:
        print(f"fred.sysinfo: cache write failed: {exc}", file=sys.stderr)
        return False
    finally:
        if temp_name is not None:
            try:
                os.unlink(temp_name, dir_fd=dfd)
            except OSError:
                pass
        os.close(dfd)


def read_private_file(name, max_age=None, max_bytes=MAX_CACHE_BYTES, cache_dir=None):
    if not _safe_cache_name(name):
        return None
    dfd = open_secure_cache_dir(cache_dir)
    if dfd is None:
        return None
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK, dir_fd=dfd)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                return None
            if info.st_size > max_bytes or max_age is not None and time.time() - info.st_mtime > max_age:
                return None
            with os.fdopen(fd, "rb", closefd=False) as stream:
                data = stream.read(max_bytes + 1)
                return data if len(data) <= max_bytes else None
        finally:
            os.close(fd)
    except OSError:
        return None
    finally:
        os.close(dfd)


def read_file(path, default=""):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except Exception:
        return default


def parse_int(val, default=0):
    try:
        return int(val)
    except (ValueError, TypeError):
        return default


def parse_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def get_cpu_static():
    full_model = "Generic CPU"
    cores = 0
    threads = 0

    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
            for line in lines:
                if (line.startswith("model name") or line.startswith("Processor") or line.startswith("Model")) and full_model == "Generic CPU":
                    parts = line.split(":", 1)
                    if len(parts) > 1:
                        full_model = parts[1].strip()
                if line.startswith("processor"):
                    threads += 1
    except Exception:
        pass

    if threads == 0:
        threads = os.cpu_count() or 1

    # Physical cores detection via core_id sysfs
    core_ids = set()
    for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/topology/core_id"):
        cid = read_file(p)
        if cid:
            core_ids.add(cid)
    cores = len(core_ids) if core_ids else threads

    # Short model cleanup
    short_model = full_model
    # Strip common boilerplate
    cleanups = [
        r"\(R\)", r"\(TM\)", r"Core\(TM\)", r"Processor", r"CPU",
        r"with Radeon Graphics", r"with Radeon Vega Graphics",
        r"Dual-Core", r"Quad-Core", r"Octa-Core", r"Hexa-Core"
    ]
    for pattern in cleanups:
        short_model = re.sub(pattern, "", short_model, flags=re.IGNORECASE)
    short_model = " ".join(short_model.split()).strip()
    if short_model.startswith("AMD "):
        short_model = short_model[4:].strip()
    elif short_model.startswith("Intel "):
        short_model = short_model[6:].strip()
    if not short_model:
        short_model = full_model

    # Cache hierarchy calculation across unique slices
    cache_slices = {}
    for idx_path in sorted(glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cache/index*")):
        lvl_path = os.path.join(idx_path, "level")
        sz_path = os.path.join(idx_path, "size")
        id_path = os.path.join(idx_path, "id")
        if os.path.exists(lvl_path) and os.path.exists(sz_path):
            lvl = read_file(lvl_path)
            sz = read_file(sz_path)
            cid = read_file(id_path)
            key = (lvl, cid if cid else os.path.basename(idx_path))
            cache_slices[key] = sz

    # Sum cache by level
    level_totals = {}
    for (lvl, _), sz in cache_slices.items():
        m = re.match(r"^(\d+)([KkMmGg])?", sz)
        if m:
            num = int(m.group(1))
            unit = (m.group(2) or "K").upper()
            bytes_val = num * 1024 if unit == "K" else (num * 1024 * 1024 if unit == "M" else num)
            level_totals[lvl] = level_totals.get(lvl, 0) + bytes_val

    cache_parts = []
    for lvl in sorted(level_totals.keys()):
        bytes_val = level_totals[lvl]
        if bytes_val >= 1024 * 1024:
            sz_str = f"{round(bytes_val / (1024 * 1024))}M"
        else:
            sz_str = f"{round(bytes_val / 1024)}K"
        cache_parts.append(sz_str)
    cache_str = " / ".join(cache_parts) if cache_parts else "--"

    # Frequency limits
    min_limit = parse_float(read_file("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq", "400000")) / 1000.0
    max_limit = parse_float(read_file("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq", "4000000")) / 1000.0

    return {
        "model": short_model,
        "full_model": full_model,
        "cores": cores,
        "threads": threads,
        "topology": f"{cores}C / {threads}T",
        "architecture": os.uname().machine,
        "cache": cache_str,
        "min_limit_mhz": round(min_limit),
        "max_limit_mhz": round(max_limit)
    }


def get_dmi_static():
    dmi_path = "/sys/class/dmi/id"
    vendor = read_file(os.path.join(dmi_path, "sys_vendor"), "Unknown Vendor")
    product = read_file(os.path.join(dmi_path, "product_name"), "Standard PC")
    board = read_file(os.path.join(dmi_path, "board_name"), "Motherboard")
    bios_ver = read_file(os.path.join(dmi_path, "bios_version"), "--")
    bios_date = read_file(os.path.join(dmi_path, "bios_date"), "--")
    ec_ver = read_file(os.path.join(dmi_path, "ec_firmware_release"), "")

    chassis_code = parse_int(read_file(os.path.join(dmi_path, "chassis_type"), "3"))
    chassis_types = {
        1: "Other", 2: "Unknown", 3: "Desktop", 4: "Low Profile Desktop",
        5: "Pizza Box", 6: "Mini Tower", 7: "Tower", 8: "Portable",
        9: "Laptop", 10: "Notebook", 11: "Hand Held", 12: "Docking Station",
        13: "All in One", 14: "Sub Notebook", 15: "Space-saving",
        17: "Main Server", 23: "Rack Mount", 30: "Tablet", 31: "Convertible",
        34: "Mini PC", 35: "Stick PC"
    }
    chassis_name = chassis_types.get(chassis_code, "Desktop")
    arch = os.uname().machine

    return {
        "vendor": vendor,
        "product": product,
        "board": board,
        "bios_version": bios_ver,
        "bios_date": bios_date,
        "ec_version": f"v{ec_ver}" if ec_ver else "--",
        "chassis": f"{chassis_name} ({arch})"
    }


def resolve_root_disk_model():
    root_dev = ""
    try:
        with open("/proc/mounts", "r", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "/":
                    root_dev = parts[0]
                    break
    except Exception:
        pass

    dev_name = ""
    if root_dev.startswith("/dev/"):
        real_dev = os.path.basename(os.path.realpath(root_dev))
        slaves_dir = f"/sys/block/{real_dev}/slaves"
        if os.path.isdir(slaves_dir):
            slaves = os.listdir(slaves_dir)
            if slaves:
                dev_name = slaves[0]
        else:
            dev_name = real_dev

    # Strip partition numbers
    m_nvme = re.match(r"(nvme\d+n\d+)", dev_name)
    m_sd = re.match(r"([a-z]+)", dev_name)
    disk_name = m_nvme.group(1) if m_nvme else (m_sd.group(1) if m_sd else dev_name)

    model = read_file(f"/sys/block/{disk_name}/device/model")
    if not model:
        # Fallback to any primary disk
        for p in sorted(glob.glob("/sys/block/nvme*") + glob.glob("/sys/block/sd*")):
            b = os.path.basename(p)
            if "p" in b:
                continue
            model = read_file(f"{p}/device/model")
            if model:
                break

    # Clean up model
    clean_model = " ".join(model.split()).strip() if model else "System Drive"
    if "KINGSTON OM3PGP4" in clean_model.upper():
        clean_model = "Kingston OM3PGP4 (1TB NVMe)"
    return clean_model


def clean_pci_name(cls, vendor, device):
    desc = device if vendor.lower() in device.lower() else f"{vendor} {device}".strip()
    desc = re.sub(r"Semiconductor Co\.,? Ltd\.?", "", desc, flags=re.IGNORECASE)
    desc = re.sub(r"Corporation", "", desc, flags=re.IGNORECASE)
    desc = re.sub(r"Advanced Micro Devices,? Inc\.? \[AMD(/ATI)?\]", "AMD", desc, flags=re.IGNORECASE)
    desc = re.sub(r"Advanced Micro Devices,? Inc\.?", "AMD", desc, flags=re.IGNORECASE)
    desc = re.sub(r"Intel\(R\)", "Intel", desc, flags=re.IGNORECASE)
    desc = re.sub(r"\(802\.11ax\)", "", desc, flags=re.IGNORECASE)
    desc = re.sub(r"\[Typhoon Peak\]", "", desc, flags=re.IGNORECASE)
    desc = re.sub(r"2x2", "", desc, flags=re.IGNORECASE)
    desc = re.sub(r"Controller", "", desc, flags=re.IGNORECASE)
    desc = " ".join(desc.split()).strip()

    if "RTL8125" in desc:
        return "Realtek RTL8125 2.5GbE"
    if "AX210" in desc:
        return "Intel Wi-Fi 6E AX210"
    if "Lucienne" in desc:
        return "AMD Radeon Vega (Lucienne)"
    if "HDMI/DP Audio" in desc or "HD Audio" in desc:
        return "AMD HD Audio"
    return desc


def get_pci_devices_static():
    devs = {
        "ethernet": [],
        "wifi": [],
        "gpu": [],
        "audio": []
    }
    lspci_path = "/usr/bin/lspci"
    if os.path.isfile(lspci_path) and os.access(lspci_path, os.X_OK):
        try:
            out = subprocess.check_output([lspci_path, "-mm"], timeout=1.5).decode("utf-8", errors="ignore")
            for line in out.splitlines():
                parts = shlex.split(line)
                if len(parts) >= 4:
                    cls, vendor, device = parts[1], parts[2], parts[3]
                    cleaned = clean_pci_name(cls, vendor, device)
                    if "Ethernet" in cls:
                        devs["ethernet"].append(cleaned)
                    elif "Network controller" in cls or "Wireless" in cls:
                        devs["wifi"].append(cleaned)
                    elif "VGA" in cls or "3D" in cls or "Display" in cls:
                        devs["gpu"].append(cleaned)
                    elif "Audio" in cls:
                        devs["audio"].append(cleaned)
        except Exception:
            pass

    # Summarize ethernet if multiple identical
    eth_summary = "--"
    if devs["ethernet"]:
        counts = {}
        for eth in devs["ethernet"]:
            counts[eth] = counts.get(eth, 0) + 1
        eth_parts = [f"{cnt}x {name}" if cnt > 1 else name for name, cnt in counts.items()]
        eth_summary = ", ".join(eth_parts)

    wifi_summary = devs["wifi"][0] if devs["wifi"] else "--"
    gpu_summary = devs["gpu"][0] if devs["gpu"] else "Integrated Graphics"
    audio_summary = devs["audio"][0] if devs["audio"] else "HD Audio"

    return {
        "ethernet": eth_summary,
        "wifi": wifi_summary,
        "graphics": gpu_summary,
        "audio": audio_summary
    }


def get_static_data(force=False):
    cached = None if force else read_private_file("static_cache.json", max_age=STATIC_CACHE_TTL)
    if cached is not None:
        try:
            data = json.loads(cached)
            if isinstance(data, dict) and "cpu" in data and "system" in data:
                return data
        except Exception:
            pass

    cpu = get_cpu_static()
    dmi = get_dmi_static()
    disk_model = resolve_root_disk_model()
    pci = get_pci_devices_static()

    data = {
        "cpu": cpu,
        "system": dmi,
        "storage_model": disk_model,
        "pci": pci
    }

    write_private_file("static_cache.json", json.dumps(data).encode("utf-8"))

    return data


def get_dynamic_cpu(cpu_static):
    # Frequencies
    freqs = []
    for p in sorted(glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq")):
        val = parse_float(read_file(p))
        if val > 0:
            freqs.append(val / 1000.0)

    avg_freq = sum(freqs) / len(freqs) if freqs else 0.0
    min_freq = min(freqs) if freqs else 0.0
    max_freq = max(freqs) if freqs else 0.0
    governor = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "performance")

    # CPU usage delta from the private session cache.
    now = time.time()
    cur_stat_line = read_file("/proc/stat").split("\n")[0].split()[1:8]
    cur_vals = [parse_float(x) for x in cur_stat_line]
    cpu_usage = None

    cached = read_private_file("cpu_stat.json", max_age=60.0)
    if cached is not None:
        try:
            old = json.loads(cached)
            prev_vals = old["vals"]
            prev_time = old["time"]
            dt = now - prev_time
            if 0.05 <= dt <= 60.0 and len(cur_vals) >= 4 and len(prev_vals) >= 4:
                diffs = [c - p for c, p in zip(cur_vals, prev_vals)]
                idle = diffs[3] + (diffs[4] if len(diffs) > 4 else 0)
                total = sum(diffs)
                if total > 0:
                    cpu_usage = max(0.0, min(100.0, (1.0 - (idle / total)) * 100.0))
        except Exception:
            pass

    if cpu_usage is None:
        time.sleep(0.04)
        stat2_line = read_file("/proc/stat").split("\n")[0].split()[1:8]
        vals2 = [parse_float(x) for x in stat2_line]
        diffs = [c - p for c, p in zip(vals2, cur_vals)]
        idle = diffs[3] + (diffs[4] if len(diffs) > 4 else 0)
        total = sum(diffs)
        cpu_usage = max(0.0, min(100.0, (1.0 - (idle / total)) * 100.0)) if total > 0 else 0.0
        cur_vals = vals2
        now = time.time()

    write_private_file("cpu_stat.json", json.dumps({"vals": cur_vals, "time": now}).encode("utf-8"))

    loadavg = read_file("/proc/loadavg").split()[:3]
    load_str = ", ".join(loadavg) if loadavg else "0.00, 0.00, 0.00"

    # Platform profile: check sysfs -> state.ini -> busctl -> powerprofilesctl
    profile = read_file("/sys/firmware/acpi/platform_profile", "")
    if not profile:
        ini_text = read_file("/var/lib/power-profiles-daemon/state.ini", "")
        for line in ini_text.splitlines():
            if line.strip().startswith("Profile="):
                profile = line.split("=", 1)[1].strip()
                break
    if not profile:
        try:
            out = subprocess.check_output(
                ["/usr/bin/busctl", "get-property", "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "ActiveProfile"],
                timeout=0.2
            ).decode().strip()
            # output format: s "performance"
            parts = out.split('"')
            if len(parts) >= 2:
                profile = parts[1].strip()
        except Exception:
            pass
    if not profile:
        try:
            profile = subprocess.check_output(["powerprofilesctl", "get"], timeout=0.8).decode().strip()
        except Exception:
            profile = "balanced"

    return {
        "model": cpu_static["model"],
        "full_model": cpu_static["full_model"],
        "cores": cpu_static["cores"],
        "threads": cpu_static["threads"],
        "topology": cpu_static["topology"],
        "architecture": cpu_static["architecture"],
        "cache": cpu_static["cache"],
        "avg_freq_mhz": round(avg_freq),
        "min_freq_mhz": round(min_freq),
        "max_freq_mhz": round(max_freq),
        "min_limit_mhz": cpu_static["min_limit_mhz"],
        "max_limit_mhz": cpu_static["max_limit_mhz"],
        "governor": governor,
        "usage_percent": round(cpu_usage, 1),
        "load_avg": load_str,
        "power_profile": profile
    }


def get_dynamic_thermals_and_gpu():
    temps = {
        "cpu": None,
        "gpu": None,
        "nvme": None,
        "wifi": None,
        "lan1": None,
        "lan2": None
    }
    gpu_power = None
    gpu_sclk = None
    gpu_volt = None

    lan_temps = []

    for d in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        name = read_file(os.path.join(d, "name"))

        # CPU thermals
        if name in ("k10temp", "zenpower", "coretemp", "cpu_thermal", "soc_thermal"):
            for tf in sorted(glob.glob(os.path.join(d, "temp*_input"))):
                val_raw = read_file(tf)
                if val_raw:
                    val = round(parse_int(val_raw) / 1000.0, 1)
                    if val > 0:
                        temps["cpu"] = val
                        break

        # GPU thermals & telemetry
        elif name in ("amdgpu", "nouveau", "i915", "xe", "nvidia"):
            tf = os.path.join(d, "temp1_input")
            val_raw = read_file(tf)
            if val_raw:
                val = round(parse_int(val_raw) / 1000.0, 1)
                if val > 0:
                    temps["gpu"] = val

            p = read_file(os.path.join(d, "power1_input"))
            if p:
                gpu_power = round(parse_int(p) / 1000000.0, 1)

            clk = read_file(os.path.join(d, "freq1_input"))
            if clk:
                gpu_sclk = round(parse_int(clk) / 1000000.0)

            v = read_file(os.path.join(d, "in0_input"))
            if v:
                gpu_volt = round(parse_int(v) / 1000.0, 2)

        # NVMe thermals
        elif name == "nvme":
            val_raw = read_file(os.path.join(d, "temp1_input"))
            if val_raw:
                val = round(parse_int(val_raw) / 1000.0, 1)
                if val > 0:
                    temps["nvme"] = val

        # Wi-Fi thermals
        elif name.startswith("iwlwifi"):
            val_raw = read_file(os.path.join(d, "temp1_input"))
            if val_raw:
                val = round(parse_int(val_raw) / 1000.0, 1)
                if val > 0:
                    temps["wifi"] = val

        # Network card thermals
        elif name.startswith("r8169") or name.startswith("e1000") or name.startswith("igc"):
            val_raw = read_file(os.path.join(d, "temp1_input"))
            if val_raw:
                val = round(parse_int(val_raw) / 1000.0, 1)
                if val > 0:
                    lan_temps.append(val)

        # ACPI thermal fallback
        elif name.startswith("acpitz") and temps["cpu"] is None:
            val_raw = read_file(os.path.join(d, "temp1_input"))
            if val_raw:
                val = round(parse_int(val_raw) / 1000.0, 1)
                if val > 0:
                    temps["cpu"] = val

    if len(lan_temps) >= 1:
        temps["lan1"] = lan_temps[0]
    if len(lan_temps) >= 2:
        temps["lan2"] = lan_temps[1]

    return temps, {
        "power_w": gpu_power,
        "clock_mhz": gpu_sclk,
        "voltage_v": gpu_volt
    }


def get_dynamic_memory_and_storage(storage_model):
    meminfo = {}
    for line in read_file("/proc/meminfo").splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meminfo[k.strip()] = parse_int(v.split()[0])

    mem_total_kb = meminfo.get("MemTotal", 0)
    mem_avail_kb = meminfo.get("MemAvailable", 0)
    mem_used_kb = mem_total_kb - mem_avail_kb
    mem_used_pct = round((mem_used_kb / mem_total_kb) * 100.0, 1) if mem_total_kb else 0.0

    swap_total_kb = meminfo.get("SwapTotal", 0)
    swap_free_kb = meminfo.get("SwapFree", 0)
    swap_used_kb = swap_total_kb - swap_free_kb
    swap_used_pct = round((swap_used_kb / swap_total_kb) * 100.0, 1) if swap_total_kb else 0.0

    # Storage (Root /)
    st = os.statvfs("/")
    disk_total_gb = round((st.f_blocks * st.f_frsize) / (1024**3), 1)
    disk_free_gb = round((st.f_bavail * st.f_frsize) / (1024**3), 1)
    disk_used_gb = round(disk_total_gb - disk_free_gb, 1)
    disk_used_pct = round((disk_used_gb / disk_total_gb) * 100.0, 1) if disk_total_gb else 0.0

    return {
        "memory": {
            "total_gb": round(mem_total_kb / 1024 / 1024, 1),
            "used_gb": round(mem_used_kb / 1024 / 1024, 1),
            "avail_gb": round(mem_avail_kb / 1024 / 1024, 1),
            "used_percent": mem_used_pct,
            "swap_total_gb": round(swap_total_kb / 1024 / 1024, 1),
            "swap_used_gb": round(swap_used_kb / 1024 / 1024, 1),
            "swap_used_percent": swap_used_pct
        },
        "storage": {
            "model": storage_model,
            "total_gb": disk_total_gb,
            "used_gb": disk_used_gb,
            "free_gb": disk_free_gb,
            "used_percent": disk_used_pct
        }
    }


def get_usb_peripherals():
    usb_peripherals = []
    seen = set()
    for dev in sorted(glob.glob("/sys/bus/usb/devices/[0-9]*")):
        prod_file = os.path.join(dev, "product")
        if os.path.exists(prod_file):
            prod = read_file(prod_file)
            mfg = read_file(os.path.join(dev, "manufacturer"))
            desc = f"{mfg} {prod}".strip() if mfg and mfg not in prod else prod
            desc = " ".join(desc.split())
            if desc and "Host Controller" not in desc and "root hub" not in desc.lower() and desc not in seen:
                seen.add(desc)
                usb_peripherals.append(desc)
    return usb_peripherals


def get_stats(force_static=False):
    static_data = get_static_data(force=force_static)

    cpu_dyn = get_dynamic_cpu(static_data["cpu"])
    temps, gpu_telemetry = get_dynamic_thermals_and_gpu()
    mem_storage = get_dynamic_memory_and_storage(static_data["storage_model"])
    usb_devices = get_usb_peripherals()

    up_secs = parse_float(read_file("/proc/uptime", "0").split()[0])
    up_hrs = int(up_secs // 3600)
    up_mins = int((up_secs % 3600) // 60)
    up_days = up_hrs // 24
    if up_days > 0:
        uptime_str = f"{up_days}d {up_hrs % 24}h {up_mins}m"
    else:
        uptime_str = f"{up_hrs}h {up_mins}m"

    kernel = os.uname().release

    system_info = dict(static_data["system"])
    system_info["kernel"] = f"Linux {kernel.split('-')[0]}"
    system_info["uptime"] = uptime_str

    cpu_dyn["temp_c"] = temps["cpu"]

    gpu_info = {
        "model": static_data["pci"]["graphics"],
        "temp_c": temps["gpu"],
        "power_w": gpu_telemetry["power_w"],
        "clock_mhz": gpu_telemetry["clock_mhz"],
        "voltage_v": gpu_telemetry["voltage_v"]
    }

    io_info = {
        "ethernet": static_data["pci"]["ethernet"],
        "wifi": static_data["pci"]["wifi"],
        "graphics": static_data["pci"]["graphics"],
        "audio": static_data["pci"]["audio"],
        "usb_peripherals": usb_devices
    }

    return {
        "system": system_info,
        "cpu": cpu_dyn,
        "gpu": gpu_info,
        "temperatures": temps,
        "memory": mem_storage["memory"],
        "storage": mem_storage["storage"],
        "io": io_info
    }


if __name__ == "__main__":
    import sys
    force = "--refresh" in sys.argv or "--force" in sys.argv
    bench = "--bench" in sys.argv

    if bench:
        t0 = time.perf_counter()
        cold_stats = get_stats(force_static=True)
        t_cold = (time.perf_counter() - t0) * 1000.0

        t1 = time.perf_counter()
        warm_stats = get_stats(force_static=False)
        t_warm = (time.perf_counter() - t1) * 1000.0

        print(f"Benchmark: Cold run = {t_cold:.2f}ms, Warm run = {t_warm:.2f}ms")
        print(f"Data valid: CPU={warm_stats['cpu']['model']}, RAM={warm_stats['memory']['total_gb']}GB, Disk={warm_stats['storage']['model']}")
    else:
        print(json.dumps(get_stats(force_static=force)))
